# CLAUDE.md — rpilinuxlab

Guidance for Claude Code when working in this repository. Everything here is
derivable from the repo itself — do not add host-side facts, key material, or
anything from personal payload trees to this file.

## What this repo is

A Gentoo build lab: `xp` (profile dispatcher) drives `genstage/xstage`
(catalyst stages + live-image pipeline), `xlab` (QEMU kernel lab) and `xarm`
(aarch64 cross-compile). Profiles live in `profiles/*.conf`; live-image
overlay layers in `genstage/live/`. Start with `README.md` (xp section first,
then the verified walkthrough).

## Hard rules

- **`squash` and `usb` are operator-reserved verbs.** Never run them; stop at
  the step before and tell the operator what remains.
- **Never edit `~/Claude/secure/`, `secure-host/`, or `konfig/`** — hand-owned
  payload trees referenced by profiles via absolute overlay paths. No
  `rsync --delete` anywhere near them.
- **No private keys in the image or the repo.** The rootfs ships as
  `livecd.squashfs`; `conf` seeds `/etc/portage/gnupg` with public material
  only. Secure Boot / signing keys are copied at install time, never baked in.
- Long verbs (`pkgs`, `livekernel`, stage builds) take hours — the operator
  runs them. Prepare, verify, and hand over the exact command.

## Layout gotchas

- `XP_BUILD_DIR` / `XP_DL_DIR` come from `/etc/xp.conf` (host config,
  assignments only, sourced by xp/xstage/xlab). Fallback is `<repo>/build|dl`.
  Build trees usually live on a data volume — `build/` may be a symlink, and
  plain `find` does not descend into it.
- `xp` is mirrored to `/usr/local/bin`, which shadows this repo in `$PATH`:
  after editing, refresh with `sudo /bin/cp -pf`.
- Overlay layers (`PROF_LIVE_OVERLAY_DIR`) apply left-to-right via
  `rsync --chown=root:root`; `conf` is **additive** — it never deletes files an
  earlier run laid into a rootfs. A layer carries arbitrary paths, not just
  `etc/portage/`.
- Never edit `xstage` in place while a run is live: copy aside, edit, `mv`
  over (rename = new inode; the running bash keeps the old one).
- Tool scripts in `genstage/live/tools/` are mirrors — the canonical copies
  live in `~/Claude/bin` and are synced by `genstage/live/tools-sync.sh`
  (kept outside `tools/` on purpose). Fix scripts at the canonical location
  and propagate; never let a fix live only in a mirror or a built rootfs.

## Pipeline order (live images)

`seed → unpack/build → conf → pkgs → [restrict-run] → configure →
livekernel → squash → [gate] → usb`. Out-of-tree kernel modules
(`PROF_LIVE_KMOD_PKGS` + anything needing `/usr/src/linux/Module.symvers`)
can only build after `livekernel`. Auxiliary verbs: `log`, `qlop`, `status`.

## Where the method lives

- Skill `gentoo-live-image` — resolver-error taxonomy, config layering,
  failure classes, the two-pass genkernel, toolchain-split method.
- `README.md` — per-tool usage + full verified walkthrough.
- `profiles/README.md` — profile-layer specifics.

Durable artifacts (scripts, comments, docs) are written in English.
