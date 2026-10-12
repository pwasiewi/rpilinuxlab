#!/bin/bash
# Mirrors the public install toolchain from ~/Claude/bin (also published in
# the gentools repo) into live/tools/ — the overlay layer the amd64 live
# profiles ship in /usr/local/bin. Canonical copies stay in bin/ (they are
# host tools too); re-run after editing any of them.
# Personal-only scripts belong in the secure*/live-overlay payloads, never
# here: this tree is committed to the (shareable) lab repo.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)/tools/usr/local/bin
# under sudo HOME is /root — resolve the invoking user's tree
SRC="$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)/Claude/bin"

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
    # Steam/Proton from the CLI (launch options, Proton pins, GE-Proton,
    # game benchmarks, presets) — the nvidiahard profile lists its helper
    # packages; nothing personal baked in, presets.conf is the user's
    # (added 2026-09-04)
    steamctl
    # VirtualBox VMs from the CLI (lifecycle, disks/NICs/shares/snapshots,
    # *.vm image specs → VM / Packer HCL / Vagrantfile); example specs ride
    # along in tools/usr/local/share/vboxctl/specs (added 2026-09-05)
    vboxctl
    # EasyEffects <-> CamillaDSP switch (user-level, PipeWire); the profiles that
    # ship both DSPs need it, nothing personal inside (added 2026-10-12)
    dspctl
    # software dimming below the Plasma slider minimum (ICC vcgt into KWin's
    # DRM gamma LUT — KWin has no wlr-gamma-control); needs only python3 +
    # kscreen-doctor from plasma-meta, no config (added 2026-10-12)
    dimicc
)
SPECS_SRC="${HOME}/Claude/vbox/specs"
SPECS_DST=$(dirname "${HERE}")/share/vboxctl/specs

mkdir -p "${HERE}"
for s in "${SCRIPTS[@]}"; do
    command cp -f "${SRC}/${s}" "${HERE}/${s}"
    chmod 0755 "${HERE}/${s}"
done
# files dropped from SCRIPTS are never pruned — say so instead of letting a
# stale mirror ride along into every image
for f in "${HERE}"/*; do
    [[ -f ${f} ]] || continue
    case " ${SCRIPTS[*]} " in *" $(basename "${f}") "*) ;; *) echo "WARNING: ${f} is not in SCRIPTS — stale mirror, remove it or add it to the list" >&2 ;; esac
done
if [[ -d ${SPECS_SRC} ]]; then
    mkdir -p "${SPECS_DST}"
    shopt -s nullglob   # an empty specs dir must not feed a literal '*.vm' to cp
    for f in "${SPECS_SRC}"/*.vm; do command cp -f "$f" "${SPECS_DST}/"; chmod 0644 "${SPECS_DST}/$(basename "$f")"; done
    shopt -u nullglob
fi
echo "live/tools refreshed: ${#SCRIPTS[@]} scripts, $(du -sh "${HERE}" | cut -f1)"
