#!/bin/sh
# Run make on the SM-A035F kernel inside the a03-kbuild container, as Samsung's README_Kernel.txt describes.
# Usage: [KOUT=/k/out-x] kmake.sh <make targets...>   (output goes to $KOUT, default /k/out, in the a03-kernel volume)
exec docker run --rm -e KOUT="${KOUT:-/k/out}" -v a03-kernel:/k -v a03-toolchain:/tc:ro a03-kbuild sh -c '
export PATH=/tc/clang-r383902/bin:$PATH
export BSP_BUILD_FAMILY=qogirl6 BSP_BUILD_ANDROID_OS=y
export DTC_OVERLAY_TEST_EXT=$PWD/tools/mkdtimg/ufdt_apply_overlay DTC_OVERLAY_VTS_EXT=$PWD/tools/mkdtimg/ufdt_verify_overlay_host
mkdir -p $KOUT
make -C /k/src O=$KOUT BSP_BUILD_DT_OVERLAY=y ARCH=arm64 CC=clang LD=ld.lld CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE=aarch64-linux-gnu- "$@"
' kmake "$@"
