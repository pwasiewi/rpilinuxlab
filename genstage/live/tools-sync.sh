#!/bin/bash
# Mirrors the public install toolchain from ~/Claude/bin (also published in
# the gentools repo) into two overlay layers that profiles ship in
# /usr/local/bin:
#   live/tools        — architecture-neutral scripts, every profile with a
#                       Portage tree or a Plasma session (amd64 AND the Pi)
#   live/tools-amd64  — the x86/UEFI install chain and desktop tools the Pi
#                       images cannot use (no UEFI, no Steam, no VirtualBox,
#                       x86-only -march names); amd64 profiles list both
# Canonical copies stay in bin/ (they are host tools too); re-run after
# editing any of them.
# Personal-only scripts belong in the secure*/live-overlay payloads, never
# here: this tree is committed to the (shareable) lab repo.
set -euo pipefail
LIVE=$(cd "$(dirname "$0")" && pwd)
HERE="${LIVE}/tools/usr/local/bin"
HERE_AMD64="${LIVE}/tools-amd64/usr/local/bin"
# under sudo HOME is /root — resolve the invoking user's tree
SRC="$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)/Claude/bin"

# --- live/tools: works on any Gentoo box -----------------------------------
SCRIPTS=(
    # generic install helpers: LUKS management, chroot bind mounts
    luks chroot-mount
    # portage day-2: emerge wrapper + config editors with their aliases,
    # world-file hygiene (clean-world, also the 'xp <prof> clean-world' verb).
    # 'e k' calls genkernel, dead on the Pi images; the rest is plain emerge.
    e ve vec vep ves veu vex vic vie vip vis viu vix clean-world
    # NOT nfy: it bakes in the personal LAN ntfy URL and only nvidiahard
    # ships ntfy-bin — it rides secure-host/live-overlay/usr/local/bin instead

    # make.conf tuning on new hardware (-march=native works on aarch64 gcc too)
    nativeflags
    # AIDE lifecycle (baseline refresh, check, report) — was in tools/ but
    # missing from this list, so it never refreshed (found 2026-08-14)
    aidectl
    # pwr overlay maintenance (index/check/bump) — images ship ::pwr, so the
    # tool that keeps it current ships too (added 2026-08-17)
    pwrup
    # EasyEffects <-> CamillaDSP switch (user-level, PipeWire); the profiles that
    # ship both DSPs need it, nothing personal inside (added 2026-10-12)
    dspctl
    # software dimming below the Plasma slider minimum (ICC vcgt into KWin's
    # DRM gamma LUT — KWin has no wlr-gamma-control); needs only python3 +
    # kscreen-doctor from plasma-meta, no config (added 2026-10-12)
    dimicc
)

# --- live/tools-amd64: x86/UEFI chain + desktop tools absent on the Pi ------
SCRIPTS_AMD64=(
    # install chain: partition, format, unpack squashfs, boot + Secure Boot
    build-usb build-nvme build-initrd-uuid-next montuj
    efi-keys efi-boot
    # gcc -march comparison; knows x86 names only (atom, silvermont, x86-64)
    cflagsdiff
    # Steam/Proton from the CLI (launch options, Proton pins, GE-Proton,
    # game benchmarks, presets) — the nvidiahard profile lists its helper
    # packages; nothing personal baked in, presets.conf is the user's
    # (added 2026-09-04)
    steamctl
    # VirtualBox VMs from the CLI (lifecycle, disks/NICs/shares/snapshots,
    # *.vm image specs → VM / Packer HCL / Vagrantfile); example specs ride
    # along in tools-amd64/usr/local/share/vboxctl/specs (added 2026-09-05)
    vboxctl
)
SPECS_SRC="${HOME}/Claude/vbox/specs"
SPECS_DST="${LIVE}/tools-amd64/usr/local/share/vboxctl/specs"

# sync_layer DEST NAME... — copy each NAME from SRC, then flag anything in
# DEST that is no longer listed: files dropped from a list are never pruned,
# a stale mirror would otherwise ride along into every image
sync_layer() {
    local dest=$1; shift
    local s f
    mkdir -p "${dest}"
    for s in "$@"; do
        command cp -f "${SRC}/${s}" "${dest}/${s}"
        chmod 0755 "${dest}/${s}"
    done
    for f in "${dest}"/*; do
        [[ -f ${f} ]] || continue
        case " $* " in *" $(basename "${f}") "*) ;; *) echo "WARNING: ${f} is not in the list — stale mirror, remove it or add it" >&2 ;; esac
    done
}
sync_layer "${HERE}" "${SCRIPTS[@]}"
sync_layer "${HERE_AMD64}" "${SCRIPTS_AMD64[@]}"

if [[ -d ${SPECS_SRC} ]]; then
    mkdir -p "${SPECS_DST}"
    shopt -s nullglob   # an empty specs dir must not feed a literal '*.vm' to cp
    for f in "${SPECS_SRC}"/*.vm; do command cp -f "$f" "${SPECS_DST}/"; chmod 0644 "${SPECS_DST}/$(basename "$f")"; done
    shopt -u nullglob
fi
echo "live/tools refreshed: ${#SCRIPTS[@]} scripts, $(du -sh "${HERE}" | cut -f1); live/tools-amd64: ${#SCRIPTS_AMD64[@]} scripts, $(du -sh "${HERE_AMD64}" | cut -f1)"
