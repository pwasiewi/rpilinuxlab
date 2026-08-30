#!/bin/bash
# Mirrors the public install toolchain from ~/Claude/bin (also published in
# the gentools repo) into live/tools/ — the overlay layer the amd64 live
# profiles ship in /usr/local/bin. Canonical copies stay in bin/ (they are
# host tools too); re-run after editing any of them.
# Personal-only scripts belong in the secure*/live-overlay payloads, never
# here: this tree is committed to the (shareable) lab repo.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)/tools/usr/local/bin
SRC="${HOME}/Claude/bin"

SCRIPTS=(
    # install chain: partition, format, unpack squashfs, boot + Secure Boot
    build-usb build-nvme build-initrd-uuid-next montuj luks chroot-mount
    efi-keys efi-boot
    # portage day-2: emerge wrapper + config editors with their aliases,
    # world-file hygiene (clean-world, also the 'xp <prof> clean-world' verb)
    e ve vec vep ves veu vex vic vie vip vis viu vix clean-world
    # NOT nfy: it bakes in the personal LAN ntfy URL and only nvidiahard
    # ships ntfy-bin — it rides secure-host/live-overlay/usr/local/bin instead

    # make.conf tuning on new hardware
    nativeflags cflagsdiff
    # AIDE lifecycle (baseline refresh, check, report) — was in tools/ but
    # missing from this list, so it never refreshed (found 2026-08-14)
    aidectl
    # pwr overlay maintenance (index/check/bump) — images ship ::pwr, so the
    # tool that keeps it current ships too (added 2026-08-17)
    pwrup
)

mkdir -p "${HERE}"
for s in "${SCRIPTS[@]}"; do
    command cp -f "${SRC}/${s}" "${HERE}/${s}"
    chmod 0755 "${HERE}/${s}"
done
echo "live/tools refreshed: ${#SCRIPTS[@]} scripts, $(du -sh "${HERE}" | cut -f1)"
