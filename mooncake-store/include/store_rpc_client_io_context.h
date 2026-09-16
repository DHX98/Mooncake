#pragma once

#include "environ.h"
#include "rpc_client_io_context.h"

namespace mooncake {

inline uint32_t GetStoreRpcClientIoThreads() {
    // M30n: image common Environ is 256B and has no store_rpc_client_io_threads_.
    // Do not read Environ::Get().GetStoreRpcClientIoThreads() (OOB).
    constexpr uint32_t kImageSafeStoreRpcIoThreads = 16;
    return kImageSafeStoreRpcIoThreads;
}

namespace detail {
struct StoreRpcClientIoContextPoolTag {};
}  // namespace detail

inline coro_io::io_context_pool& GetStoreRpcClientIoContextPool() {
    static auto& io_pool =
        GetRpcClientIoContextPool<detail::StoreRpcClientIoContextPoolTag>(
            GetStoreRpcClientIoThreads());
    return io_pool;
}

}  // namespace mooncake
