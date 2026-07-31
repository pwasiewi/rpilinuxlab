#!/bin/bash
# distcc-from-chroot benchmark series (optimizations.md §2, log 27).
# Compares qemu-chroot builds with compile offload to the host cross gcc:
#   1. nano  FEATURES="-ccache distcc"        vs baseline 8m04s plain / 6m35s warm ccache
#   2. nano  FEATURES="ccache distcc" +CCACHE_PREFIX  (combined mode)
#   3. zstd  plain chroot baseline (no ccache, no distcc)
#   4. zstd  FEATURES="-ccache distcc"        (compile-heavy showcase, thin configure)
# DISTCC_FALLBACK=0 so a broken offload fails loudly instead of silently
# compiling under emulation and corrupting the timing.
set -uo pipefail
C=/mnt/db1/rpilinuxlab/arm64-chroot
DLOG=/var/tmp/xarm/distccd.log
run() {
    local name="$1" cmd="$2" t0 dt j0 j1
    j0=$(grep -c COMPILE_OK "$DLOG" 2>/dev/null || echo 0)
    echo "=== RUN $name: $cmd"
    t0=$SECONDS
    XARM_CHROOT_ROOT=$C xarm chroot "$cmd"
    dt=$((SECONDS-t0))
    j1=$(grep -c COMPILE_OK "$DLOG" 2>/dev/null || echo 0)
    echo "=== RESULT $name: ${dt}s wall, $((j1-j0)) distcc jobs"
}
run nano-distcc      "DISTCC_FALLBACK=0 FEATURES='-ccache distcc' emerge --oneshot --nodeps app-editors/nano"
run nano-ccache-distcc "DISTCC_FALLBACK=0 FEATURES='ccache distcc' CCACHE_PREFIX=distcc emerge --oneshot --nodeps app-editors/nano"
run zstd-plain       "FEATURES='-ccache -distcc' emerge --oneshot --nodeps app-arch/zstd"
run zstd-distcc      "DISTCC_FALLBACK=0 FEATURES='-ccache distcc' emerge --oneshot --nodeps app-arch/zstd"
echo "=== verify binaries are aarch64 and run:"
file $C/usr/bin/nano $C/usr/bin/zstd
XARM_CHROOT_ROOT=$C xarm chroot "nano --version | head -1; zstd --version"
