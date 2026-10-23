#!/usr/bin/env bash
set +e
wt=/home/d00883276/prefetch_916/src/Mooncake-02a25e4f
out=/home/d00883276/prefetch_916/920_pre_pr/gate/twotier-208/verify-20261023-02a25e4f
build="$out/build-030"
export PATH=/usr/local/python3.12.13/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export TMPDIR="$out/030-tmp"
mkdir -p "$TMPDIR"
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy
{
  printf 'DATE=%s\nCONTAINER=mc-verify-030-20261023\nHEAD=%s\nBUILD_JOBS=32\n' "$(date -Is)" "$(git -C "$wt" rev-parse HEAD)"
  ldd --version | head -1
  /usr/bin/g++-12 --version | head -1
  python --version
} > "$out/030-build.log"
printf 'PHASE=CMAKE\n' > "$out/030-state.txt"
cmake -S "$wt" -B "$build" -G Ninja \
  -DCMAKE_C_COMPILER=/usr/bin/gcc-12 -DCMAKE_CXX_COMPILER=/usr/bin/g++-12 \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_UNIT_TESTS=ON \
  -DUSE_ASCEND_DIRECT=ON -DBUILD_SHARED_LIBS=ON \
  -DUSE_CUDA=OFF -DUSE_ASCEND=OFF -DWITH_EP=OFF \
  -DPython3_ROOT_DIR=/usr/local/python3.12.13 \
  -DPython3_EXECUTABLE=/usr/local/python3.12.13/bin/python3.12 \
  -DFETCHCONTENT_SOURCE_DIR_GOOGLETEST=/home/d00883276/prefetch_916/920_pre_pr/vendor/googletest-1.17.0 \
  -DFETCHCONTENT_SOURCE_DIR_YALANTINGLIBS=/home/d00883276/prefetch_916/920_pre_pr/vendor/yalantinglibs \
  -DWITH_STORE_RUST=OFF >> "$out/030-build.log" 2>&1
rc=$?
printf 'CMAKE_RC=%s\n' "$rc" | tee -a "$out/030-build.log"
if [ "$rc" -ne 0 ]; then
  cp -n "$out/030-build.log" "$out/030-build-failed-cmake-first.log"
  printf 'PHASE=STOP_CMAKE_FAILED\n' > "$out/030-state.txt"
  exit "$rc"
fi
printf 'PHASE=BUILD\n' > "$out/030-state.txt"
cmake --build "$build" --parallel 32 >> "$out/030-build.log" 2>&1
rc=$?
printf 'BUILD_RC=%s\n' "$rc" | tee -a "$out/030-build.log"
git -C "$wt" status --short > "$out/030-source-status-after-build.txt"
if [ "$rc" -ne 0 ]; then
  cp -n "$out/030-build.log" "$out/030-build-failed-compile-first.log"
  printf 'PHASE=STOP_BUILD_FAILED\n' > "$out/030-state.txt"
  exit "$rc"
fi
find "$build" -type f \( -name 'ascend_transport.so' -o -name 'libtransfer_engine.so' -o -name 'libmooncake_store.so' -o -name '_store*.so' -o -name 'engine*.so' -o -name 'mooncake_master' \) -exec sha256sum {} + > "$out/030-build-artifact-sha256.txt"
printf 'PHASE=BUILD_PASS\n' > "$out/030-state.txt"
