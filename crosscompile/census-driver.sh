#!/bin/bash
# census-driver.sh — sequential overnight lab pipeline (2026-07-30):
#   A. stage3 update      (emerge -uvDN @world under qemu; ccache active)
#   B. ccache benchmark   (nano in stage3: cold ARM cache vs warm)
#   C. 1by1 census        (sysroot -e @world + dev-lang/perl: cross first,
#                          fallback = stage3 chroot with native gcc)
#   D. summary            (mode counts + per-mode time totals from done.log)
# Run: sudo bash census-driver.sh   (logs land next to the numbered lab logs)
set -uo pipefail

LOGS=/home/pwas/Claude/rpilinuxlab/crosscompile/logs
STAGE3=/mnt/db1/rpilinuxlab/arm64-chroot
XARM=/usr/local/bin/xarm

phase() { echo ">>> [$(date '+%F %T')] $*"; }

phase "A: stage3 update"
XARM_CHROOT_ROOT=$STAGE3 $XARM chroot "emerge -uvDN --keep-going=y @world" \
    > "$LOGS/22-stage3-update.log" 2>&1
phase "A done rc=$?"

phase "B: ccache benchmark (nano cold/warm)"
{
    echo "--- run 1: cold ARM ccache (baseline without ccache was 8m04s) ---"
    time XARM_CHROOT_ROOT=$STAGE3 $XARM chroot \
        "FEATURES=-buildpkg emerge --oneshot --nodeps app-editors/nano"
    echo "--- run 2: warm ARM ccache ---"
    time XARM_CHROOT_ROOT=$STAGE3 $XARM chroot \
        "FEATURES=-buildpkg emerge --oneshot --nodeps app-editors/nano"
    echo "--- ccache stats (inside stage3) ---"
    XARM_CHROOT_ROOT=$STAGE3 $XARM chroot "ccache -s"
} > "$LOGS/23-ccache-bench.log" 2>&1
phase "B done rc=$?"

phase "C: 1by1 census (-e @world + dev-lang/perl)"
XARM_STAGE3=$STAGE3 $XARM 1by1 --fresh -e @world dev-lang/perl \
    > "$LOGS/24-census-1by1.log" 2>&1
phase "C done rc=$?"

phase "D: summary"
{
    echo "=== 1by1 census summary $(date '+%F %T') ==="
    awk -F'\t' '{n[$2]++; sub(/s$/,"",$3); t[$2]+=$3}
        END {for (m in n) printf "%-8s %4d pkgs  %6.1f min\n", m, n[m], t[m]/60}' \
        /var/tmp/xarm/done.log
    echo "--- via chroot ---";  cat /var/tmp/xarm/via-chroot.log
    echo "--- failed both ---"; cat /var/tmp/xarm/failed.log
    echo "--- slowest 15 ---"
    sort -t$'\t' -k3 -rn /var/tmp/xarm/done.log | head -15
    echo "--- host ARM ccache (cross) ---"
    CCACHE_DIR=/var/cache/ccache-xarm ccache -s | head -8
} > "$LOGS/25-census-summary.log" 2>&1
phase "all done"
