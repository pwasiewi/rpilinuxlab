# xarm setup: the same environment in six commands

Companion to `manual-setup.md` — identical end state, but driven by
`~/Claude/bin/xarm` (mirrored to `/usr/local/bin/xarm`; after editing the script
refresh with `sudo cp -f ~/Claude/bin/xarm /usr/local/bin/`). Use this file when
you just want the environment; use `manual-setup.md` when you want to understand
or debug what each step does.

Since the 2026-07-30 lab fixes, `xarm setup` bakes in every gotcha the manual
route documents — the mapping:

| `xarm setup` step | manual-setup.md section | gotcha it absorbs |
|---|---|---|
| 1. crossdev overlay | A1 | eselect-repo or additive repos.conf variant |
| 2. `crossdev --stable` toolchain | A2 | host LTO check is on you (setup warns on missing static qemu) |
| 2b. usr-merge sysroot | A3 | "23.0 merged-usr profile, but disk is split-usr" |
| 2c. pin gentoo repos.conf | A4 | tree not at /var/db/repos/gentoo → chroot emerge refuses |
| 3. arm64/23.0 profile | A5 | — |
| 4. make.conf block | A6 | cortex-a72 flags, ROOT-relative PKGDIR, sandboxes off for qemu, **stable keywords** (gcc-16 skew), **-openmp** (target gcc not cross-emergeable) |
| 5. shared dirs | A6 (tail) | — |
| 6. binfmt | A7 | persistent via /etc/binfmt.d; since 2026-07-30 upgrades an earlier ad-hoc registration instead of silently staying volatile |

## Bring-up (once)

```bash
emerge -av sys-devel/crossdev app-emulation/qemu   # qemu: USE=static-user, QEMU_USER_TARGETS=aarch64
sudo xarm setup            # ~20 min, unattended; idempotent — safe to re-run
xarm status                # toolchain/profile/binfmt/sysroot summary
```

## Daily use

```bash
# layer 1 — native-speed cross-emerge (measured: zlib 7.6 s, nano+deps 3 m,
# perl 5.44 incl. 42-pkg chain 14 m 37 s — perl builds in layer 1, no chroot needed)
sudo xarm emerge --oneshot -v app-editors/nano

# layer 2 — qemu chroot into the sysroot (works once bash is cross-merged;
# ~10–20× slower, for packages that must run their own freshly built binaries)
sudo xarm chroot                       # interactive aarch64 shell
sudo xarm chroot "emerge -1v foo"

# bulk: dep-ordered per-package loop, cross first, chroot fallback,
# resume via /var/tmp/xarm/done.log, failures logged and skipped
sudo xarm 1by1 @system

# deliver to the Pi (prints the Pi-side binrepos.conf snippet)
sudo xarm binhost          # serves ${SYSROOT}/var/cache/binpkgs on :8686
```

Target package tuning goes into `/usr/aarch64-unknown-linux-gnu/etc/portage/`
(`package.use`, `package.accept_keywords`, `package.mask/gcc-skew`…) — the host's
`/etc/portage` stays x86_64-only.

## What xarm does NOT cover

- **stage3 chroot on /mnt/db1** — separate, self-contained environment:
  `manual-setup.md` §B + `./arm64-chroot.sh`. Useful for config experiments and
  as a build box for things the sysroot can't do yet (e.g. target gcc).
- **target sys-devel/gcc** — not cross-emergeable at all; build it in a chroot
  (hours) or natively on the Pi. Until then keep the sysroot's `USE="-openmp"`.
- **Rust packages** — need `RUST_CROSS_TARGETS` + dev-lang/rust rebuilt from
  source on the host (see the gentoo-crosscompile skill, "Rust" section).

## Teardown

```bash
sudo xarm clean            # crossdev --clean + optional sysroot removal (confirms)
sudo rm /etc/binfmt.d/qemu.conf && sudo systemctl restart systemd-binfmt
```
