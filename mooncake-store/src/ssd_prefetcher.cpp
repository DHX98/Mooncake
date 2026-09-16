#include "ssd_prefetcher.h"

#include <algorithm>
#include <cstdlib>
#include <exception>
#include <unordered_map>
#include <utility>

#include <glog/logging.h>

#include "client_buffer.h"
#include "client_metric.h"
#include "file_storage.h"
#include "pyclient.h"
#include "replica_selection.h"

namespace mooncake {

[[maybe_unused]] constexpr const char kRefacP11Marker[] = "REFAC_P11_20260910";

namespace {
// Parse a non-negative integer env var, returning `fallback` when unset or
// invalid.
int64_t GetEnvInt64(const char *name, int64_t fallback) {
    const char *raw = std::getenv(name);
    if (raw == nullptr || *raw == '\0') {
        return fallback;
    }
    try {
        return static_cast<int64_t>(std::stoll(raw));
    } catch (const std::exception &) {
        LOG(WARNING) << "Invalid value for env " << name << "='" << raw
                     << "', using default " << fallback;
        return fallback;
    }
}

constexpr size_t kPrefetchMetadataChunkSize = 128;

struct SsdPrefetchRoute {
    int64_t local_disk_size{0};
    std::string holder_endpoint;
};

std::optional<SsdPrefetchRoute> ClassifySsdPrefetchRoute(
    const std::vector<Replica::Descriptor> &replicas) {
    bool has_memory = false;
    bool has_local_disk = false;
    SsdPrefetchRoute route;
    for (const auto &replica : replicas) {
        if (replica.status != ReplicaStatus::COMPLETE &&
            replica.status != ReplicaStatus::PROCESSING) {
            continue;
        }
        if (replica.is_memory_replica()) {
            has_memory = true;
            break;
        }
        if (replica.is_local_disk_replica()) {
            has_local_disk = true;
            route.local_disk_size =
                static_cast<int64_t>(calculate_total_size(replica));
            route.holder_endpoint =
                replica.get_local_disk_descriptor().transport_endpoint;
        }
    }
    if (has_memory || !has_local_disk || route.local_disk_size <= 0) {
        return std::nullopt;
    }
    return route;
}

void RunLocalPrefetchRegisterAndPromote(
    const std::shared_ptr<Client> &client, FileStorage *file_storage,
    const std::shared_ptr<PrefetchThrottle> &throttle,
    const FileStorage::PrefetchKeyCallback &on_key_done,
    const std::vector<std::string> &local_keys,
    const std::vector<int64_t> &local_sizes) {
    if (local_keys.empty() || file_storage == nullptr) {
        return;
    }
    std::vector<std::string> prefetch_keys;
    std::vector<int64_t> prefetch_sizes;
    prefetch_keys.reserve(local_keys.size());
    prefetch_sizes.reserve(local_keys.size());
    for (size_t i = 0; i < local_keys.size(); ++i) {
        auto register_result = client->RegisterPrefetchTask(local_keys[i]);
        if (!register_result) {
            VLOG(1) << "SSD prefetch: RegisterPrefetchTask failed for"
                    << "key=" << local_keys[i]
                    << ", error=" << register_result.error();
            continue;
        }
        prefetch_keys.push_back(local_keys[i]);
        prefetch_sizes.push_back(local_sizes[i]);
        if (throttle) {
            throttle->markInFlight(local_keys[i]);
        }
        VLOG(1) << "SSD prefetch: registered task for key=" << local_keys[i]
                << ", size=" << local_sizes[i];
    }
    if (prefetch_keys.empty()) {
        return;
    }
    bool dram_pressure = false;
    auto prefetch_res = file_storage->PrefetchKeys(
        prefetch_keys, prefetch_sizes, &dram_pressure, on_key_done);
    if (!prefetch_res) {
        LOG(WARNING) << "SSD prefetch: PrefetchKeys failed, error="
                     << prefetch_res.error();
    } else {
        VLOG(1) << "SSD prefetch: PrefetchKeys completed for "
                << prefetch_keys.size() << " key(s)";
    }
    if (dram_pressure && throttle) {
        throttle->enterCooldown();
        LOG(INFO) << "SSD prefetch: DRAM saturated, backing off "
                     "(ssd_prefetch_cooldown_sec)";
    }
}

}  // namespace

std::function<void(const std::string &, bool)>
PrefetchThrottle::CompletionCallback(std::shared_ptr<PrefetchThrottle> self,
                                     SsdMetric *metric) {
    if (!self) {
        return {};
    }
    return [self, metric](const std::string &key, bool success) {
        if (success) {
            self->markCompleted(key);
            if (metric) {
                metric->prefetch_complete_total.fetch_add(
                    1, std::memory_order_relaxed);
            }
        } else {
            self->markFailed(key);
            if (metric) {
                metric->prefetch_fail_total.fetch_add(1,
                                                      std::memory_order_relaxed);
            }
        }
    };
}

SsdPrefetcher::SsdPrefetcher(
    std::shared_ptr<Client> &client,
    std::shared_ptr<FileStorage> &file_storage,
    std::shared_ptr<ClientRequester> &client_requester,
    const std::string &local_rpc_addr, int64_t &ssd_get_wait_ms,
    int64_t &ssd_get_wait_ms_config)
    : client_(client),
      file_storage_(file_storage),
      client_requester_(client_requester),
      local_rpc_addr(local_rpc_addr),
      ssd_get_wait_ms_(ssd_get_wait_ms),
      ssd_get_wait_ms_config_(ssd_get_wait_ms_config) {}

std::optional<QueryResult> TryRefreshBestMemoryReplica(
    Client *client, const std::string &key,
    const std::unordered_set<std::string> &local_endpoints) {
    auto requery = client->Query(key, QueryOptions{.read_only = true});
    if (!requery) {
        return std::nullopt;
    }
    const auto *candidate =
        SelectBestReplica(requery.value().replicas, local_endpoints);
    if (!candidate || !candidate->is_memory_replica()) {
        return std::nullopt;
    }
    return std::move(requery.value());
}

void SsdPrefetcher::initPrefetchRuntime() {
    // Bounded worker pool for SSD prefetch promotion jobs. Fixed size,
    // consistent with ClientService's task_thread_pool_(4); bounds concurrent
    // SSD reads / DRAM allocations and avoids unbounded detached threads.
    constexpr size_t kPrefetchThreadPoolSize = 4;
    prefetch_pool_ = std::make_shared<ThreadPool>(kPrefetchThreadPoolSize);

    // get()-side wait-for-prefetch max budget (poll every 1 ms, early exit).
    // Env overrides mooncake.json ssd_get_wait_ms.
    const int64_t wait_from_env = GetEnvInt64("MOONCAKE_SSD_GET_WAIT_MS", -1);
    if (wait_from_env >= 0) {
        ssd_get_wait_ms_ = wait_from_env;
    } else {
        ssd_get_wait_ms_ = ssd_get_wait_ms_config_;
    }

    LOG(INFO) << "SSD prefetch runtime: pool_size=" << kPrefetchThreadPoolSize
              << ", ssd_get_wait_ms=" << ssd_get_wait_ms_
              << " (poll 1ms, early exit on completion)";
}

void SsdPrefetcher::submitPrefetchJob(std::function<void()> job) {
    if (prefetch_pool_) {
        try {
            prefetch_pool_->enqueue(std::move(job));
            return;
        } catch (const std::exception &e) {
            // Pool stopped (shutdown in progress): drop the best-effort job.
            VLOG(1) << "SSD prefetch: pool enqueue failed (" << e.what()
                    << "), dropping job";
            return;
        }
    }
    // Pool unavailable (not initialized / shutting down): drop the best-effort
    // job. Never fall back to an unbounded detached thread -- that is exactly
    // the prefetch-storm anti-pattern this bounded-pool path exists to avoid.
    VLOG(1) << "SSD prefetch: pool unavailable, dropping job";
}

void SsdPrefetcher::triggerSsdPrefetch(const std::vector<std::string> &keys) {
    auto throttle = prefetch_throttle_;
    if (throttle && throttle->inCooldown()) {
        VLOG(1) << "SSD prefetch: skipped (memory-pressure cooldown)";
        return;
    }
    if (keys.empty()) {
        return;
    }

    // Do not reserve()/record trigger at exist time. BatchQuery(read_only) in the
    // async job filters SSD-only keys first; reserve() runs only for keys that
    // will actually RegisterPrefetchTask, avoiding false triggers on DRAM-resident
    // keys (exist only knows "exists", not replica tier).
    auto keys_copy = keys;
    auto client = client_;
    auto file_storage = file_storage_;
    auto client_requester = client_requester_;
    const std::string local_rpc_addr_copy = local_rpc_addr;
    SsdMetric *metric = client ? client->GetSsdMetricPtr() : nullptr;
    if (metric) {
        metric->prefetch_trigger_total.fetch_add(keys.size(),
                                                 std::memory_order_relaxed);
    }
    auto on_key_done = PrefetchThrottle::CompletionCallback(throttle, metric);
    submitPrefetchJob([client, file_storage, client_requester, throttle,
                       local_rpc_addr_copy, on_key_done,
                       keys_copy = std::move(keys_copy)]() {
        // Batch metadata queries in chunks, then register + promote each
        // chunk immediately (pipeline) instead of waiting for all keys.
        std::unordered_map<std::string, std::vector<std::string>> remote_keys;
        std::unordered_map<std::string, std::vector<int64_t>> remote_sizes;

        for (size_t offset = 0; offset < keys_copy.size();
             offset += kPrefetchMetadataChunkSize) {
            const size_t end = std::min(offset + kPrefetchMetadataChunkSize,
                                        keys_copy.size());
            std::vector<std::string> chunk(keys_copy.begin() + offset,
                                           keys_copy.begin() + end);
            std::vector<tl::expected<QueryResult, ErrorCode>> batch_results;
            try {
                batch_results =
                    client->BatchQuery(chunk, QueryOptions{.read_only = true});
            } catch (const std::exception &e) {
                LOG(WARNING) << "SSD prefetch: BatchQuery failed: "
                             << e.what();
                continue;
            }
            if (batch_results.size() != chunk.size()) {
                LOG(WARNING) << "SSD prefetch: BatchQuery size "
                                "mismatch, expected "
                             << chunk.size() << ", got "
                             << batch_results.size();
                continue;
            }

            std::vector<std::string> chunk_local_keys;
            std::vector<int64_t> chunk_local_sizes;
            chunk_local_keys.reserve(chunk.size());
            chunk_local_sizes.reserve(chunk.size());

            for (size_t i = 0; i < chunk.size(); ++i) {
                if (!batch_results[i]) {
                    VLOG(1) << "SSD prefetch: metadata query failed for"
                            << " key=" << chunk[i]
                            << ", error=" << batch_results[i].error();
                    continue;
                }
                auto route =
                    ClassifySsdPrefetchRoute(batch_results[i].value().replicas);
                if (!route) {
                    continue;
                }
                if (route->holder_endpoint.empty() ||
                    route->holder_endpoint == local_rpc_addr_copy) {
                    chunk_local_keys.push_back(chunk[i]);
                    chunk_local_sizes.push_back(route->local_disk_size);
                } else {
                    remote_keys[route->holder_endpoint].push_back(chunk[i]);
                    remote_sizes[route->holder_endpoint].push_back(
                        route->local_disk_size);
                }
            }

            std::vector<std::string> promote_local_keys;
            std::vector<int64_t> promote_local_sizes;
            if (throttle) {
                auto reserved = throttle->reserve(chunk_local_keys);
                std::unordered_set<std::string> reserved_set(reserved.begin(),
                                                             reserved.end());
                promote_local_keys.reserve(reserved.size());
                promote_local_sizes.reserve(reserved.size());
                for (size_t i = 0; i < chunk_local_keys.size(); ++i) {
                    if (reserved_set.find(chunk_local_keys[i]) ==
                        reserved_set.end()) {
                        continue;
                    }
                    promote_local_keys.push_back(chunk_local_keys[i]);
                    promote_local_sizes.push_back(chunk_local_sizes[i]);
                }
            } else {
                promote_local_keys = std::move(chunk_local_keys);
                promote_local_sizes = std::move(chunk_local_sizes);
            }

            RunLocalPrefetchRegisterAndPromote(
                client, file_storage.get(), throttle, on_key_done,
                promote_local_keys, promote_local_sizes);
        }

        // Remote branch: delegate each holder's keys via RPC. The holder
        // registers the promotion task with its own client_id, so Master's
        // holder check passes without changing Master logic. Best-effort.
        if (client_requester) {
            for (auto &[endpoint, group_keys] : remote_keys) {
                VLOG(1) << "SSD prefetch: delegating " << group_keys.size()
                        << " key(s) to remote holder " << endpoint;
                client_requester->prefetch_offload_object(
                    endpoint, group_keys, remote_sizes[endpoint]);
            }
        }
    });
}

void SsdPrefetcher::runLocalPrefetch(const std::vector<std::string> &keys,
                                     const std::vector<int64_t> &sizes) {
    auto throttle = prefetch_throttle_;
    if (throttle && throttle->inCooldown()) {
        VLOG(1) << "SSD prefetch: skipped (memory-pressure cooldown)";
        return;
    }

    std::unordered_set<std::string> allowed(keys.begin(), keys.end());
    if (throttle) {
        auto reserved = throttle->reserve(keys);
        allowed.clear();
        allowed.insert(reserved.begin(), reserved.end());
        if (allowed.empty()) {
            return;
        }
    }

    (void)sizes;  // hint only; local object map is authoritative
    std::vector<std::string> keys_copy;
    keys_copy.reserve(keys.size());
    for (const auto &key : keys) {
        if (allowed.find(key) == allowed.end()) {
            continue;
        }
        keys_copy.push_back(key);
    }
    if (keys_copy.empty()) {
        return;
    }

    auto client = client_;
    auto file_storage = file_storage_;
    SsdMetric *metric = client ? client->GetSsdMetricPtr() : nullptr;
    if (metric) {
        metric->prefetch_trigger_total.fetch_add(keys_copy.size(),
                                                 std::memory_order_relaxed);
    }
    auto on_key_done = PrefetchThrottle::CompletionCallback(throttle, metric);
    submitPrefetchJob([client, file_storage, throttle, on_key_done,
                       keys_copy = std::move(keys_copy)]() {
        std::vector<std::string> local_keys;
        std::vector<int64_t> local_sizes;
        local_keys.reserve(keys_copy.size());
        local_sizes.reserve(keys_copy.size());
        for (size_t i = 0; i < keys_copy.size(); ++i) {
            std::optional<int64_t> local_size;
            if (file_storage) {
                local_size = file_storage->LookupLocalObjectSize(keys_copy[i]);
            }
            if (!local_size || *local_size <= 0) {
                VLOG(1) << "SSD prefetch: skip remote key=" << keys_copy[i]
                        << " (not in local object map)";
                continue;
            }
            local_keys.push_back(keys_copy[i]);
            local_sizes.push_back(*local_size);
        }
        RunLocalPrefetchRegisterAndPromote(
            client, file_storage.get(), throttle, on_key_done, local_keys,
            local_sizes);
    });
}

bool SsdPrefetcher::waitForPromotion(const std::string &key, int64_t budget_ms,
                                     std::vector<Replica::Descriptor> *out) {
    if (budget_ms <= 0 || !client_ || out == nullptr) {
        return false;
    }
    const int64_t deadline = PrefetchThrottle::NowMs() + budget_ms;
    constexpr int64_t kPollMs = 1;
    bool saw = false;
    while (PrefetchThrottle::NowMs() < deadline) {
        auto qr = client_->Query(key, QueryOptions{.read_only = true});
        if (qr) {
            *out = qr->replicas;
            saw = true;
            const bool has_memory = std::any_of(
                out->begin(), out->end(), [](const Replica::Descriptor &replica) {
                    return replica.is_memory_replica();
                });
            if (has_memory) {
                return true;
            }
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(kPollMs));
    }
    if (!saw) {
        return false;
    }
    return std::any_of(out->begin(), out->end(),
                       [](const Replica::Descriptor &replica) {
                           return replica.is_memory_replica();
                       });
}

}  // namespace mooncake
