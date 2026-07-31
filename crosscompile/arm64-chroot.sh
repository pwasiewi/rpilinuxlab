#!/bin/bash
# arm64-chroot.sh — QEMU user-mode chroot into the aarch64 stage3 on /mnt/db1.
# Same mount/trap pattern as `xarm chroot`, but targets the standalone stage3
# instead of the crossdev sysroot. Host /var/db/repos and distfiles are shared.
#
# Usage:
#   sudo ./arm64-chroot.sh              # interactive shell
#   sudo ./arm64-chroot.sh "emerge -1v app-misc/foo"

set -euo pipefail

CHROOT="${ARM64_CHROOT:-/mnt/db1/rpilinuxlab/arm64-chroot}"
QEMU_BIN="/usr/bin/qemu-aarch64"

die()  { echo "❌  $*" >&2; exit 1; }
info() { echo ">>>  $*"; }
warn() { echo "⚠️   $*" >&2; }

[[ $EUID -eq 0 ]] || die "Root required."
[[ -d ${CHROOT} ]] || die "No chroot at ${CHROOT}"
[[ -x ${QEMU_BIN} ]] || die "No ${QEMU_BIN}"

# binfmt: register qemu-aarch64 handler ad-hoc if missing (lost on reboot; fine for a lab)
if [[ ! -f /proc/sys/fs/binfmt_misc/qemu-aarch64 ]]; then
    echo ':qemu-aarch64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:'"${QEMU_BIN}"':OC' \
        > /proc/sys/fs/binfmt_misc/register || die "binfmt registration failed"
    info "binfmt qemu-aarch64 registered (ad-hoc)"
fi

# OC flags → the kernel resolves the interpreter inside the chroot: static qemu must be there
install -m755 "${QEMU_BIN}" "${CHROOT}/usr/bin/" || die "Cannot copy ${QEMU_BIN}"
cp -L /etc/resolv.conf "${CHROOT}/etc/resolv.conf" || die "resolv.conf copy failed"

MOUNTED=()
cleanup() {
    local m
    for (( m=${#MOUNTED[@]}-1; m>=0; m-- )); do
        umount -R "${MOUNTED[m]}" 2>/dev/null || warn "umount ${MOUNTED[m]} failed"
    done
    MOUNTED=()
}
do_mount() {
    local tgt="${CHROOT}$2"
    mkdir -p "${tgt}"
    case "$1" in
        proc)  mountpoint -q "${tgt}" || mount -t proc proc "${tgt}" ;;
        rbind) mountpoint -q "${tgt}" || { mount --rbind "$3" "${tgt}"; mount --make-rslave "${tgt}"; } ;;
        bind)  mountpoint -q "${tgt}" || mount --bind "$3" "${tgt}" ;;
    esac
    MOUNTED+=("${tgt}")
}

# Host quirk (gen2db): the gentoo tree is NOT under /var/db/repos (only overlays
# are) and DISTDIR is /var/tmp/distfiles — resolve real paths via portageq so the
# chroot's default repos.conf (/var/db/repos/gentoo) finds the tree.
GENTOO_REPO=$(portageq get_repo_path / gentoo)
HOST_DISTDIR=$(portageq distdir)

trap cleanup EXIT INT TERM
do_mount proc  /proc
do_mount rbind /dev /dev
do_mount rbind /sys /sys
do_mount bind  /tmp /tmp
do_mount bind  /var/db/repos/gentoo "${GENTOO_REPO}"
do_mount bind  /var/cache/distfiles "${HOST_DISTDIR}"

rc=0
if [[ $# -eq 0 ]]; then
    info "Entering aarch64 stage3 chroot — exit to leave"
    chroot "${CHROOT}" /bin/bash --login || rc=$?
else
    chroot "${CHROOT}" /bin/bash -lc "$*" || rc=$?
fi
cleanup
trap - EXIT INT TERM
exit "${rc}"
