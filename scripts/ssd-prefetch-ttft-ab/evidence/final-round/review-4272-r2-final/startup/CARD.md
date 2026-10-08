# 95b24456 启动失败是 GlobalConfig 布局被 #4325 撑开

同一套镜像、同一份 `ascend_transport.so`（包内文件时间 Sep 28）下，`98d9002f` 能起 A 臂，`95b24456` 起不来。根因 commit 在上游区间 `7364f79d..a6d66e3b` 里。

## 结论

根因 commit：`9acd3da37987b7cf139826682d2633b0db5bd465`

标题：`[TransferEngine] Make the RDMA worker idle spin window configurable (#4325)`

它在 `GlobalConfig` 中部插入了 `uint64_t rdma_worker_idle_spin_us`。`ascend_agent_mode` 和 `ascend_store_te_init` 都在这个字段后面，偏移各增加 8 字节。镜像里的 `ascend_transport.so` 仍按旧布局读这两个 bool。读出来的值是 `agent_mode=true`、`store_te_init=false`。`allocateLocalSegmentID` 因此走 standalone real client 分支，`ContextManager` 没初始化，本地 segment 分配失败。

这是上游 ABI 破坏。lease 修复不在这条路径上。`USE_TENT` 在两边的 CMake 缓存里都是 `OFF`。`DummyClient::setup_dummy` 和 `real_client_main` 的写入点在诊断日志里没有出现。

没有环境变量能把旧插件的字段偏移改回来。规避办法是装上同一次构建产出的 `ascend_transport.so`。装上之后，同一套 `95b24456` 库只起 A 臂，`VERDICT=START_OK`，传输侧读到 `agent_mode=0 store_te_init=1`。

## 诊断日志

诊断构建只加了 LOG，没有改行为，没有推送。`StoreTeInitGuard` 在 store 库里把本进程的 `globalConfig` 设对了，析构前值仍是对的。旧插件在这之前已经按错偏移读完：

```
DIAG4272 guard set store_te_init cfg=0xfffdf44c1e50 agent_mode=0 store_te_init=1
utils.cpp:146] te is created for store=false
ascend_direct_transport.cpp:194] te is created for store=false, launched as standalone real client
DIAG4272 guard dtor cfg=0xfffdf44c1e50 agent_mode=0 store_te_init=1
```

`ascend_direct_transport.cpp:194` 是未打补丁的行号。包里的 `ascend_transport.so` 是 Sep 28 的文件，`nm` 显示 `globalConfig()` 为未定义符号。这次 `95b24456` 构建自己的 `ascend_transport.so` 含有诊断字符串，安装时漏掉了它。

换成这次构建的插件之后：

```
DIAG4272 read cfg=0xfffde1fb1e50 agent_mode=0 store_te_init=1
utils.cpp:146] te is created for store=true
ascend_direct_transport.cpp:204] init local segment, te is created for store=true
VERDICT=START_OK
```

行号从 194 变成 204，说明跑的是打过诊断 LOG 的新插件。地址后缀 `1e50` 与 `libtransfer_engine.so` 里 `globalConfig()::config` 的 BSS 偏移一致，store 和插件看的是同一个对象。

## 复现

部署脚本原先只覆盖 `libmooncake_store.so`、`libtransfer_engine.so`、`engine.so`、`store.so`，不覆盖 `ascend_transport.so`。

失败：只换 `95b24456` 的 store / transfer engine，留下镜像里的 `ascend_transport.so`，按 settle700 的方式只起 A 臂。

通过：把同一次 `USE_ASCEND_DIRECT=ON`、`BUILD_SHARED_LIBS=ON` 构建产出的 `ascend_transport.so` 一并装上，再起 A 臂。

`98d9002f` 不含 `rdma_worker_idle_spin_us`，所以同一份旧插件能读对字段，A 臂可以起来。
