#pragma once

#include <atomic>
#include <chrono>
#include <cstdint>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include "client_service.h"
#include "thread_pool.h"
#include "types.h"

namespace mooncake {

class FileStorage;
class ClientRequester;
struct SsdMetric;

// Throttle state for best-effort SSD prefetch. Two mechanisms:
//   1. Memory-pressure cooldown: when promotion fails because DRAM is
//      saturated (NO_AVAILABLE_HANDLE), open a short cooldown window during
//      which prefetch is a no-op, so prefetch (which *adds* to DRAM) stops
//      competing with eviction/offload (which *frees* DRAM) on the holder.
//   2. Per-key in-flight dedup / rate-limit: suppress duplicate prefetch
//      triggers for the same key from concurrent exist/get probes within a
//      TTL window, cutting the RPC/thread storm that starves offload.
// Held via shared_ptr so detached prefetch threads can use it safely without
// capturing a raw RealClient* that may outlive the work.
class PrefetchThrottle {
   public:
    enum class State : uint8_t {
        kTriggered = 0,
        kInFlight = 1,
        kCompleted = 2,
        kFailed = 3,
        kAlreadyResident = 4,
    };

    struct Entry {
        int64_t trigger_ms{-1};
        int64_t completed_ms{-1};
        State state{State::kTriggered};
        // Set when RegisterPrefetchTask + PrefetchKeys path runs for this key.
        bool promote_attempted{false};
    };

    static int64_t NowMs() {
        return std::chrono::duration_cast<std::chrono::milliseconds>(
                   std::chrono::steady_clock::now().time_since_epoch())
            .count();
    }

    // Reconfigure from mooncake.json (values come in as seconds, stored as ms).
    // Non-positive values keep the current setting. A 0 cooldown disables the
    // memory-pressure backoff; a 0 dedup TTL disables per-key rate-limiting.
    void configure(int64_t cooldown_sec, int64_t dedup_ttl_sec) {
        if (cooldown_sec >= 0) {
            cooldown_ms_.store(cooldown_sec * 1000, std::memory_order_relaxed);
        }
        if (dedup_ttl_sec >= 0) {
            dedup_ttl_ms_.store(dedup_ttl_sec * 1000,
                                std::memory_order_relaxed);
        }
    }

    bool inCooldown() const {
        return NowMs() < cooldown_until_ms_.load(std::memory_order_relaxed);
    }

    // Open the memory-pressure backoff window. No-op if cooldown is disabled.
    void enterCooldown() {
        const int64_t cooldown_ms =
            cooldown_ms_.load(std::memory_order_relaxed);
        if (cooldown_ms <= 0) {
            return;
        }
        cooldown_until_ms_.store(NowMs() + cooldown_ms,
                                 std::memory_order_relaxed);
    }

    // Returns the subset of keys not seen within the dedup TTL, registering
    // them as triggered synchronously (before the async prefetch job runs).
    std::vector<std::string> reserve(const std::vector<std::string> &keys) {
        const int64_t ttl_ms = dedup_ttl_ms_.load(std::memory_order_relaxed);
        const int64_t now = NowMs();
        std::vector<std::string> out;
        out.reserve(keys.size());
        std::lock_guard<std::mutex> lock(mutex_);
        if (ttl_ms <= 0) {
            for (const auto &key : keys) {
                entries_[key] = Entry{.trigger_ms = now,
                                      .completed_ms = -1,
                                      .state = State::kTriggered};
                out.push_back(key);
            }
            return out;
        }
        for (auto it = entries_.begin(); it != entries_.end();) {
            const int64_t last_ms = it->second.completed_ms >= 0
                                        ? it->second.completed_ms
                                        : it->second.trigger_ms;
            if (now - last_ms > ttl_ms) {
                it = entries_.erase(it);
            } else {
                ++it;
            }
        }
        for (const auto &key : keys) {
            if (entries_.find(key) != entries_.end()) {
                continue;
            }
            entries_[key] = Entry{.trigger_ms = now,
                                  .completed_ms = -1,
                                  .state = State::kTriggered};
            out.push_back(key);
        }
        return out;
    }

    void markInFlight(const std::string &key) {
        std::lock_guard<std::mutex> lock(mutex_);
        auto it = entries_.find(key);
        if (it == entries_.end()) {
            return;
        }
        it->second.state = State::kInFlight;
        it->second.promote_attempted = true;
    }

    void markCompleted(const std::string &key) {
        const int64_t now = NowMs();
        std::lock_guard<std::mutex> lock(mutex_);
        auto it = entries_.find(key);
        if (it == entries_.end()) {
            entries_[key] = Entry{.trigger_ms = now,
                                  .completed_ms = now,
                                  .state = State::kCompleted};
            return;
        }
        it->second.state = State::kCompleted;
        it->second.completed_ms = now;
    }

    void markFailed(const std::string &key) {
        std::lock_guard<std::mutex> lock(mutex_);
        auto it = entries_.find(key);
        if (it == entries_.end()) {
            return;
        }
        it->second.state = State::kFailed;
    }

    // Shared by triggerSsdPrefetch / runLocalPrefetch. Optional metric is the
    // existing SsdMetric on Client (no new metrics layer).
    static std::function<void(const std::string &, bool)> CompletionCallback(
        std::shared_ptr<PrefetchThrottle> self, SsdMetric *metric = nullptr);

    // Async prefetch decided the key is not SSD-only (e.g. MEMORY already
    // present). Clears in-flight semantics without treating as promotion done.
    void markAlreadyResident(const std::string &key) {
        std::lock_guard<std::mutex> lock(mutex_);
        auto it = entries_.find(key);
        if (it == entries_.end()) {
            return;
        }
        it->second.state = State::kAlreadyResident;
        it->second.promote_attempted = false;
    }

    bool promoteAttempted(const std::string &key) const {
        std::lock_guard<std::mutex> lock(mutex_);
        auto it = entries_.find(key);
        if (it == entries_.end()) {
            return false;
        }
        return it->second.promote_attempted;
    }

    int64_t triggeredAt(const std::string &key) const {
        std::lock_guard<std::mutex> lock(mutex_);
        auto it = entries_.find(key);
        if (it == entries_.end()) {
            return -1;
        }
        return it->second.trigger_ms;
    }

    int64_t completedAt(const std::string &key) const {
        std::lock_guard<std::mutex> lock(mutex_);
        auto it = entries_.find(key);
        if (it == entries_.end() || it->second.state != State::kCompleted) {
            return -1;
        }
        return it->second.completed_ms;
    }

    State stateOf(const std::string &key) const {
        std::lock_guard<std::mutex> lock(mutex_);
        auto it = entries_.find(key);
        if (it == entries_.end()) {
            return State::kFailed;
        }
        return it->second.state;
    }

    // Poll until promotion completes or the budget expires. Returns true only
    // when the key reaches kCompleted before the deadline.
    bool waitForCompletion(const std::string &key, int64_t max_wait_ms,
                           int64_t poll_ms = 1) const {
        if (max_wait_ms <= 0) {
            return false;
        }
        const int64_t deadline = NowMs() + max_wait_ms;
        const int64_t step_ms = std::max<int64_t>(poll_ms, 1);
        while (NowMs() < deadline) {
            {
                std::lock_guard<std::mutex> lock(mutex_);
                auto it = entries_.find(key);
                if (it == entries_.end()) {
                    return false;
                }
                if (it->second.state == State::kCompleted) {
                    return true;
                }
                if (it->second.state == State::kFailed) {
                    return false;
                }
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(step_ms));
        }
        return stateOf(key) == State::kCompleted;
    }

   private:
    std::atomic<int64_t> cooldown_until_ms_{0};
    std::atomic<int64_t> cooldown_ms_{DEFAULT_SSD_PREFETCH_COOLDOWN_SEC * 1000};
    std::atomic<int64_t> dedup_ttl_ms_{DEFAULT_SSD_PREFETCH_DEDUP_TTL_SEC *
                                       1000};
    mutable std::mutex mutex_;
    std::unordered_map<std::string, Entry> entries_;
};

// Returns refreshed QueryResult when master sees a COMPLETE MEMORY replica.
// Was file-local in real_client.cpp; get-path is the only caller and stays
// there, so this has to be visible after the move.
std::optional<QueryResult> TryRefreshBestMemoryReplica(
    Client *client, const std::string &key,
    const std::unordered_set<std::string> &local_endpoints);

class SsdPrefetcher {
   public:
    // Refs, not copies: triggerSsdPrefetch reads client_requester_ at
    // exist/RPC time, and setup_internal assigns it after initPrefetchRuntime.
    SsdPrefetcher(std::shared_ptr<Client> &client,
                  std::shared_ptr<FileStorage> &file_storage,
                  std::shared_ptr<ClientRequester> &client_requester,
                  const std::string &local_rpc_addr,
                  int64_t &ssd_get_wait_ms,
                  int64_t &ssd_get_wait_ms_config);

    SsdPrefetcher(const SsdPrefetcher &) = delete;
    SsdPrefetcher &operator=(const SsdPrefetcher &) = delete;

    void triggerSsdPrefetch(const std::vector<std::string> &keys);

    // Read env-tunables and build prefetch_pool_. Called once from
    // setup_internal when SSD offload is enabled.
    void initPrefetchRuntime();

    // Submit a best-effort prefetch job to the bounded prefetch_pool_ so
    // high-frequency probes don't explode into unbounded detached threads.
    // Falls back to a detached std::thread only if the pool is unavailable
    // (e.g. enqueue after shutdown).
    void submitPrefetchJob(std::function<void()> job);

    /**
     * @brief Run prefetch promotion for keys whose LOCAL_DISK replica is held
     * by THIS node. Registers a promotion task per key (this node is the
     * holder) and stages the objects from SSD into DRAM via prefetch_pool_.
     * Called from prefetch_offload_object (remote holder RPC). Best-effort;
     * runs asynchronously. Register + PrefetchKeys execution is delegated to
     * RunLocalPrefetchRegisterAndPromote (same as triggerSsdPrefetch local
     * branch).
     * @param keys Keys to promote (LOCAL_DISK replica held by this node).
     * @param sizes Object sizes (bytes), index-aligned with keys.
     */
    void runLocalPrefetch(const std::vector<std::string> &keys,
                          const std::vector<int64_t> &sizes);

    bool waitForCompletion(const std::string &key, int64_t max_wait_ms,
                           int64_t poll_ms = 1) const {
        return prefetch_throttle_->waitForCompletion(key, max_wait_ms, poll_ms);
    }

    // Read-only get re-check. Fills *out with the latest replica list; caller
    // keeps SelectBestReplica. Returns true only when a MEMORY replica appears
    // before the budget expires.
    bool waitForPromotion(const std::string &key, int64_t budget_ms,
                          std::vector<Replica::Descriptor> *out);

    // Same shared_ptr RealClient used to hold as prefetch_throttle_.
    // get-path leftover (triggeredAt / completedAt / stateOf / promoteAttempted
    // / configure) keeps calling these methods; no new get-wait facade.
    std::shared_ptr<PrefetchThrottle> prefetch_throttle_ =
        std::make_shared<PrefetchThrottle>();

   private:
    std::shared_ptr<Client> &client_;
    std::shared_ptr<FileStorage> &file_storage_;
    std::shared_ptr<ClientRequester> &client_requester_;
    const std::string &local_rpc_addr;
    int64_t &ssd_get_wait_ms_;
    int64_t &ssd_get_wait_ms_config_;

    // Bounded worker pool for SSD prefetch promotion jobs. Fixed size (see
    // initPrefetchRuntime), consistent with ClientService's task pool; bounds
    // concurrent SSD reads / DRAM allocations and avoids unbounded detached
    // threads.
    std::shared_ptr<ThreadPool> prefetch_pool_;
};

}  // namespace mooncake
