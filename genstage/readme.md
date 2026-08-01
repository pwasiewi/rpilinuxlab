# genstage — Gentoo stage bootstrapping + Buildroot-style tiny rootfs

Two experiments driven by one script, [`xstage`](xstage):

1. **amd64 track** — build Gentoo's own `stage1 → stage3` tarballs with
   **catalyst**, the tool Release Engineering uses for the official releases.
   You end up with a stage3 you bootstrapped yourself from a seed.
2. **tiny track** — the Gentoo analog of **Buildroot**: a minimal aarch64
   rootfs emerged **into a directory** (`emerge --root=`), with **no
   portage on the target**. Updates happen on the host; the rootfs is
   regenerated from scratch, never updated in place. The userland is real
   Gentoo base packages by default (bash, coreutils, util-linux & friends);
   `XSTAGE_TINY_BASE=busybox` builds the truly tiny static-busybox variant.

```
sudo ./xstage amd64 setup          # catalyst conf + releng + gentoo.git on /mnt/db5
./xstage amd64 seed                # latest official amd64 stage3 = the seed
sudo ./xstage amd64 all            # snapshot -> spec -> stage1 -> stage3 (hours)
sudo ./xstage amd64 verify         # chroot smoke test of the built stage3

sudo ./xstage tiny build           # Gentoo-base rootfs into build/tinyroot/rootfs
sudo ./xstage tiny pack            # rootfs.squashfs + cpio initrd
./xstage tiny run                  # qemu -M virt boots it to a bash shell
```

## What stage1/2/3 actually mean

| Stage | What catalyst does | Portage-level equivalent |
|---|---|---|
| stage1 | In a chroot of the **seed stage3**, build the toolchain subset of `@system` (the profile's `packages.build`) into `ROOT=/tmp/stage1root` | `ROOT=… emerge` of ~gcc/glibc/binutils & friends |
| stage2 | Inside the stage1 chroot, run `scripts/bootstrap.sh` — the toolchain rebuilds itself with itself | `bootstrap.sh` (on this host: `/usr/portage/scripts/bootstrap.sh`) |
| stage3 | Full base system in the chroot | `emerge -e @system` |

- **Modern releng skips stage2**: stage3 builds directly from stage1, because
  the extra self-rebuild adds no observable difference to the result. `xstage
  amd64 all` does the same; `xstage amd64 stage2` exists as an explicit
  educational step (and `specs/stage3.spec.in` documents how to re-point
  stage3 at the stage2 for the classic three-step chain).
- The old **manual stage1 install** (unpack stage1, run `bootstrap.sh`, then
  `emerge -e @system`) was dropped from the Handbook in 2005 — unsupported,
  bug-prone, and the end result is identical to a stage3 install +
  `emerge -e @world`. It survives as documentation: read
  `/usr/portage/scripts/bootstrap.sh` to see exactly what stage2 is.
- A **seed is always required**: catalyst cannot create a stage from nothing —
  the chain is grounded in an existing stage3 (that is what "bootstrapping"
  means here: reproducing the stages from a trusted binary seed, not creating
  them ex nihilo).

References: [Catalyst](https://wiki.gentoo.org/wiki/Catalyst),
[Catalyst/Stage Creation](https://wiki.gentoo.org/wiki/Catalyst/Stage_Creation),
[Catalyst FAQ](https://wiki.gentoo.org/wiki/Project:Catalyst/FAQ),
[releng specs](https://github.com/gentoo/releng).

## amd64 track mechanics

- **Private config**: `xstage` never touches `/etc/catalyst` — every call is
  `catalyst -c /mnt/db5/genstage/conf/catalyst.conf`. The storedir lives on
  `/mnt/db5` because one run needs ~25–40 GB (seed + unpacked chroot +
  pkgcache + snapshot) and the root NVMe is small.
- **Snapshot**: catalyst 4 snapshots the ebuild tree from a **git** repo at
  `${storedir}/repos/gentoo.git` (`setup` makes a shallow bare clone of the
  `stable` branch; `snapshot` fetches and runs `catalyst -s stable`, then
  records the commit hash in `state/treeish` for the specs). Commits are
  GPG-verified against `sec-keys/openpgp-keys-gentoo-release`.
- **Specs**: rendered from [`specs/*.spec.in`](specs/) with one shared
  timestamp, so `stage3.spec` points exactly at the `stage1` of the same run.
  `rel_type: lab` keeps our outputs in `builds/lab/`, separate from the seeds
  in `builds/default/`. The `portage_confdir` comes from the releng clone
  (`releases/portage/stages`) — the same `/etc/portage` overlay releng uses.
- **pkgcache/seedcache/autoresume** are on: a failed run resumes, rebuilt
  stages reuse binpkgs. `catalyst -af` in the script clears stale autoresume
  points whenever a spec is re-run.

## tiny track mechanics (the Buildroot idea on Gentoo)

Buildroot's model: everything is compiled on the host into an output
directory; the target has **no package manager**; removing/changing packages
means regenerating the image from scratch. The Gentoo translation:

- The **xarm crossdev sysroot** (`/usr/aarch64-unknown-linux-gnu`) is the
  "host build" side — packages are built there once (binpkgs cached), exactly
  like `sudo xarm emerge <pkg>`.
- `xstage tiny build` then installs **only the runtime files** into the
  rootfs: `aarch64-unknown-linux-gnu-emerge --root=build/tinyroot/rootfs
  --root-deps=rdeps --usepkg --oneshot` — first `baselayout` (`USE=build`
  lays out the FS skeleton), then the base userland, then anything in
  `XSTAGE_TINY_PKGS`. Two bases (`XSTAGE_TINY_BASE`):
  - **`gentoo`** (default) — the real base packages: bash, coreutils,
    util-linux, grep, sed, gawk, findutils, procps, less; rdeps (glibc,
    ncurses, readline, pam, …) come along automatically. `INSTALL_MASK`
    drops man/doc/info/locale — ~136 MB rootfs, 32 MB squashfs, boots to a
    bash prompt. `/bin/sh` is symlinked to bash (`app-alternatives/sh`
    normally provides it and isn't pulled in).
  - **`busybox`** — a single **static busybox** with `USE=make-symlinks`
    (the ebuild installs all applet symlinks into ROOT) — ~5 MB rootfs,
    1.4 MB squashfs, boots in ~0.6 s.
- **No portage on the target**: nothing ever emerges it into the rootfs (the
  package list is explicit and `--oneshot` writes no world file). As
  belt-and-braces, [`tiny.portage/profile/packages`](tiny.portage/profile/packages)
  documents the classic `-*sys-apps/portage` system-set mask for setups that
  give the target its own config root.
- **Regeneration is the update mechanism**: `tiny build` wipes the rootfs and
  replays the install from the sysroot binpkgs (near-instant when nothing was
  rebuilt). This is the direct equivalent of Buildroot's "config changed →
  full rebuild" rule, minus the rebuild cost.
- `tiny pack` produces both `rootfs.squashfs` (zstd) and a newc **cpio
  initrd**; `tiny run` boots the initrd with xlab's arm64 `-M virt` kernel
  (`build/gentoo/emu/vmlinuz`) straight to a shell. The historic
  precedent for all of this lives in [`../legacy/qemu-binfmt/`](../legacy/qemu-binfmt/)
  (`armv7a-emerge`, `armv7a-1by1crossroot`).

References:
[Embedded Handbook — Cross-compiling with Portage](https://wiki.gentoo.org/wiki/Embedded_Handbook/General/Cross-compiling_with_Portage),
[RPi Minimal musl+busybox cross building](https://wiki.gentoo.org/wiki/Raspberry_Pi/Minimal_musl%2Bbusybox_cross_building).

## Storage layout

| Path | Contents |
|---|---|
| `/mnt/db5/genstage/conf/catalyst.conf` | private catalyst config (`-c`) |
| `/mnt/db5/genstage/catalyst/builds/default/` | seed stage3 tarballs |
| `/mnt/db5/genstage/catalyst/builds/lab/` | **our** stage1/2/3 outputs |
| `/mnt/db5/genstage/catalyst/snapshots/` | `gentoo-<treeish>.sqfs` tree snapshots |
| `/mnt/db5/genstage/catalyst/repos/gentoo.git` | bare shallow clone for `catalyst -s` |
| `/mnt/db5/genstage/catalyst/tmp/` | scratch chroots (`clean` target) |
| `/mnt/db5/genstage/{specs,state,logs,releng}` | rendered specs, treeish/stamp, build logs, releng clone |
| `../dl/stage3-amd64-*` | seed download cache (shared with xlab's arm64 seeds) |
| `../build/tinyroot/{rootfs,rootfs.squashfs,initrd}` | tiny track outputs |

Nothing here needs `.gitignore` changes: tiny artifacts land under the
already-ignored `/build/`, seed downloads under `/dl/`, and everything heavy
sits on `/mnt/db5` outside the repo.

## Future work

- **arm64 stages on this amd64 host**: catalyst spec key
  `interpreter: /usr/bin/qemu-aarch64` + the releng `stages-qemu` confdir —
  releng builds several arches this way (~10× slower under emulation). An
  `export` step copying the result into `../dl/` would let `xlab gentoo
  image` boot a self-built arm64 stage3.
- **UEFI boot in qemu** (separate task): boot the built artifacts through an
  OVMF/AAVMF firmware instead of `-kernel`, reusing the host's
  `efi-boot` / `build-initrd-uuid-next` patterns (`~/Claude/bin`) — squashfs
  root located by UUID, switch_root from a busybox initrd.
- **musl tiny variant**: a second crossdev toolchain
  (`aarch64-…-linux-musl`) for the truly smallest images (5–10 MB squashfs).
