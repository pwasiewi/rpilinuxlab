# Manual setup: x86_64 → aarch64 cross-compile environment (Gentoo)

The exact command sequence behind the 2026-07-30 lab, for configuring everything
**by hand** — no `xarm`. Two independent environments: A) crossdev sysroot
(fast, native-speed cross-emerge), B) QEMU stage3 chroot (slow, but "native"
for packages that run their own freshly built binaries). Run everything as root.

Verified on: Portage 3.0.81.2, gcc-15, crossdev-20260623, systemd host.
Target: Raspberry Pi 400/4 (Cortex-A72, arm64, profile `default/linux/arm64/23.0`).

---

## 0. Prerequisites (one-time)

```bash
# qemu with a STATIC user-mode aarch64 binary:
#   /etc/portage/package.use:  app-emulation/qemu static-user
#   make.conf:                 QEMU_USER_TARGETS="aarch64"
emerge -av sys-devel/crossdev app-emulation/qemu
file /usr/bin/qemu-aarch64        # MUST say "statically linked"

# host make.conf must NOT have LTO flags (breaks the cross-gcc build)
grep -E 'FLAGS' /etc/portage/make.conf
```

---

## A. crossdev sysroot (layer 1 — native-speed cross-emerge)

### A1. Overlay for the cross-* toolchain ebuilds

```bash
# either (eselect-repo, what this host uses — adds [crossdev] to
# /etc/portage/repos.conf/eselect-repo.conf):
eselect repository create crossdev

# or fully additive (a separate new file, zero shared-file edits):
mkdir -p /var/db/repos/crossdev/{profiles,metadata}
echo 'crossdev' > /var/db/repos/crossdev/profiles/repo_name
echo 'masters = gentoo' > /var/db/repos/crossdev/metadata/layout.conf
chown -R portage:portage /var/db/repos/crossdev
cat > /etc/portage/repos.conf/crossdev.conf <<'EOF'
[crossdev]
location = /var/db/repos/crossdev
priority = 10
masters = gentoo
auto-sync = no
EOF
```

### A2. Build the toolchain (~20 min)

```bash
crossdev --stable --target aarch64-unknown-linux-gnu
# on failure: /var/log/portage/cross-aarch64-unknown-linux-gnu-*.log
# side effect: additive files /etc/portage/{package.use,package.accept_keywords,
#   package.env,env,profile/package.use.mask}/cross-aarch64-unknown-linux-gnu
```

### A3. usr-merge the sysroot — REQUIRED before any emerge

crossdev creates split-usr directories; 23.0 profiles are merged-usr and every
setup phase dies with `ERROR: 23.0 merged-usr profile, but disk is split-usr`
once baselayout is in.

```bash
cd /usr/aarch64-unknown-linux-gnu
cp -a bin/.  usr/bin/  && rm -rf bin  && ln -s usr/bin  bin
cp -a sbin/. usr/bin/  && rm -rf sbin && ln -s usr/bin  sbin
cp -a lib/.  usr/lib/  && rm -rf lib  && ln -s usr/lib  lib
cp -a lib64/. usr/lib64/ && rm -rf lib64 && ln -s usr/lib64 lib64
cp -a usr/sbin/. usr/bin/ && rm -rf usr/sbin && ln -s bin usr/sbin
```

### A4. Pin the gentoo repo path in the sysroot config

Needed on any host whose tree is not at `/var/db/repos/gentoo` (this one:
`/home/tmp/.portage`); without it, emerge inside the sysroot chroot refuses to run.

```bash
GREPO=$(portageq get_repo_path / gentoo)
mkdir -p /usr/aarch64-unknown-linux-gnu/etc/portage/repos.conf
cat > /usr/aarch64-unknown-linux-gnu/etc/portage/repos.conf/gentoo.conf <<EOF
[DEFAULT]
main-repo = gentoo

[gentoo]
location = ${GREPO}
EOF
```

### A5. Target profile

```bash
PORTAGE_CONFIGROOT=/usr/aarch64-unknown-linux-gnu eselect profile set default/linux/arm64/23.0
```

### A6. Sysroot make.conf (append to what crossdev generated)

```bash
cat >> /usr/aarch64-unknown-linux-gnu/etc/portage/make.conf <<EOF

# Raspberry Pi 400/4 (cortex-a72)
COMMON_FLAGS="-mcpu=cortex-a72 -mtune=cortex-a72 -O2 -pipe"
CFLAGS="\${COMMON_FLAGS}"
CXXFLAGS="\${COMMON_FLAGS}"
FCFLAGS="\${COMMON_FLAGS}"
FFLAGS="\${COMMON_FLAGS}"
MAKEOPTS="-j$(nproc) -l$(nproc)"
# binpkgs for the Pi, ROOT-relative (otherwise they land in the host's PKGDIR)
PKGDIR="\${ROOT}var/cache/binpkgs"
FEATURES="buildpkg -news"
# namespace sandboxes do not work under qemu-user chroot
FEATURES="\${FEATURES} -pid-sandbox -ipc-sandbox -network-sandbox"
ACCEPT_LICENSE="*"
# STABLE only — crossdev defaults to "arch ~arch"; ~arch pulled gcc-16 under a
# gcc-15 cross toolchain (libatomic configure: -fno-link-libatomic → death)
ACCEPT_KEYWORDS="\${ARCH}"
# openmp needs target libgomp = sys-devel/gcc in ROOT, and gcc itself is NOT
# cross-emergeable (dies on generated headers even version-matched) — keep off
# until the target has a native gcc
USE="\${USE} -openmp"
EOF
mkdir -p /usr/aarch64-unknown-linux-gnu/var/cache/{binpkgs,distfiles}
```

If the sysroot already accepted ~arch packages, mask instead of downgrading:

```bash
echo '>=sys-devel/gcc-16' > /usr/aarch64-unknown-linux-gnu/etc/portage/package.mask/gcc-skew
```

### A7. binfmt registration (to run/chroot aarch64 binaries)

```bash
# persistent (systemd):
ln -s /usr/share/qemu/binfmt.d/qemu.conf /etc/binfmt.d/qemu.conf
systemctl restart systemd-binfmt
# or ad-hoc (lost on reboot):
echo ':qemu-aarch64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/bin/qemu-aarch64:OC' \
    > /proc/sys/fs/binfmt_misc/register
cat /proc/sys/fs/binfmt_misc/qemu-aarch64      # → enabled
```

### A8. Use it

```bash
# smoke test
aarch64-unknown-linux-gnu-gcc -static -o /tmp/t tests/hello.c && /tmp/t
#   → "hello from aarch64 (Linux)" (static runs transparently via binfmt;
#      dynamic needs: qemu-aarch64 -L /usr/aarch64-unknown-linux-gnu ./binary)

# cross-emerge (NEVER plain emerge — the wrapper sets ROOT/SYSROOT/CONFIGROOT)
emerge-aarch64-unknown-linux-gnu --oneshot -v sys-libs/zlib     # 7.6 s here
emerge-aarch64-unknown-linux-gnu --oneshot -v app-editors/nano  # 3 m here
emerge-aarch64-unknown-linux-gnu --oneshot -v dev-lang/perl     # works! (perl-cross)

# serve binpkgs to the Pi
python3 -m http.server --directory /usr/aarch64-unknown-linux-gnu/var/cache/binpkgs 8686
```

Target package tuning (USE/keywords/masks) goes into
`/usr/aarch64-unknown-linux-gnu/etc/portage/package.*` — never the host's.

---

## B. QEMU stage3 chroot (layer 2 — emulated, ~10–20× slower)

```bash
mkdir -p /mnt/db1/rpilinuxlab && cd /mnt/db1/rpilinuxlab
LATEST=$(curl -s https://distfiles.gentoo.org/releases/arm64/autobuilds/latest-stage3-arm64-openrc.txt \
         | awk '/stage3-arm64-openrc/ {print $1; exit}')
curl -O "https://distfiles.gentoo.org/releases/arm64/autobuilds/${LATEST}" \
     -O "https://distfiles.gentoo.org/releases/arm64/autobuilds/${LATEST}.sha256"
sha256sum -c "$(basename "$LATEST").sha256"
mkdir arm64-chroot
tar xpf stage3-arm64-openrc-*.tar.xz --xattrs-include='*.*' --numeric-owner -C arm64-chroot

# chroot's own /etc/portage — host untouched
cat >> arm64-chroot/etc/portage/make.conf <<'EOF'
MAKEOPTS="-j8"
FEATURES="-pid-sandbox -ipc-sandbox -network-sandbox -news"
ACCEPT_LICENSE="*"
EOF
```

Enter with `./arm64-chroot.sh` (this directory) — it registers binfmt if needed,
copies the static qemu inside (Gentoo's binfmt uses OC flags → the interpreter is
resolved *inside* the chroot), bind-mounts the host's real gentoo tree + DISTDIR
(resolved via portageq), and umounts on exit via trap. Manual equivalent = the
mount block inside that script.

```bash
sudo ./arm64-chroot.sh                      # interactive aarch64 shell
sudo ./arm64-chroot.sh "emerge -1v foo"     # one-shot (sys-apps/which: 2 m 22 s)
```

---

## Teardown

```bash
crossdev --clean --target aarch64-unknown-linux-gnu   # toolchain + /etc/portage cross-* files
rm -rf /usr/aarch64-unknown-linux-gnu                 # sysroot (umount everything first!)
rm -rf /mnt/db1/rpilinuxlab/arm64-chroot              # stage3 (umount first!)
rm /etc/binfmt.d/qemu.conf && systemctl restart systemd-binfmt
```
