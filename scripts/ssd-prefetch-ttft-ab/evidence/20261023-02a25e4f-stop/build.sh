#!/usr/bin/env bash
set +e
export PATH=/usr/local/python3.12.13/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
wt=/home/d00883276/prefetch_916/src/Mooncake-02a25e4f
out=/home/d00883276/prefetch_916/920_pre_pr/gate/twotier-208/verify-20261023-02a25e4f
export TMPDIR="$out/tmp"
mkdir -p "$TMPDIR"
if [ -f /usr/local/Ascend/ascend-toolkit/set_env.sh ]; then . /usr/local/Ascend/ascend-toolkit/set_env.sh; fi
if [ -f /usr/local/Ascend/cann/set_env.sh ]; then . /usr/local/Ascend/cann/set_env.sh; fi
set +e
export PATH=/usr/local/python3.12.13/bin:$PATH
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy
{
  printf 'DATE=%s\n' "$(date -Is)"
  printf 'CONTAINER=mc-ab-208\nHEAD=%s\nBUILD_JOBS=32\n' "$(git -C "$wt" rev-parse HEAD)"
} > "$out/build.log"
cmake -S "$wt" -B "$wt/build" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_UNIT_TESTS=ON \
  -DUSE_ASCEND_DIRECT=ON -DBUILD_SHARED_LIBS=ON \
  -DUSE_CUDA=OFF -DUSE_ASCEND=OFF -DWITH_EP=OFF \
  -DPython3_ROOT_DIR=/usr/local/python3.12.13 \
  -DPython3_EXECUTABLE=/usr/local/python3.12.13/bin/python3.12 \
  -DFETCHCONTENT_SOURCE_DIR_GOOGLETEST=/home/d00883276/prefetch_916/920_pre_pr/vendor/googletest-1.17.0 \
  -DFETCHCONTENT_SOURCE_DIR_YALANTINGLIBS=/home/d00883276/prefetch_916/920_pre_pr/vendor/yalantinglibs \
  -DWITH_STORE_RUST=OFF >> "$out/build.log" 2>&1
rc=$?
printf 'CMAKE_RC=%s\n' "$rc" | tee -a "$out/build.log"
if [ "$rc" -ne 0 ]; then
  printf 'PHASE=STOP_CMAKE_FAILED\n' > "$out/state.txt"
  exit "$rc"
fi
printf 'PHASE=BUILD\n' > "$out/state.txt"
cmake --build "$wt/build" --parallel 32 >> "$out/build.log" 2>&1
rc=$?
printf 'BUILD_RC=%s\n' "$rc" | tee -a "$out/build.log"
if [ "$rc" -ne 0 ]; then
  printf 'PHASE=STOP_BUILD_FAILED\n' > "$out/state.txt"
  exit "$rc"
fi
git -C "$wt" status --short > "$out/source-status-after-build.txt"
find "$wt/build" -type f \( -name 'ascend_transport.so' -o -name 'libtransfer_engine.so' -o -name 'libmooncake_store.so' -o -name '_store*.so' -o -name 'mooncake_master' \) -exec sha256sum {} + > "$out/build-artifact-sha256.txt"
printf 'PHASE=BUILD_PASS\n' > "$out/state.txt"
