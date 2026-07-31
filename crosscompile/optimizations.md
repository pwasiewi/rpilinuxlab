# Compile-speed optimizations for the aarch64 lab

How to make ARM package builds faster on this host (gen2db: 32 threads, 64 GB
RAM). Two build paths exist and every optimization targets one of them:

- **cross-emerge** (layer 1, host-native aarch64-gcc) — already the fast path
- **QEMU user chroot** (stage3 on /mnt/db1) — the slow path, ~19× wall / ~28×
  CPU vs cross (README experiment 7)

## Measured baselines (app-editors/nano, MAKEOPTS=-j32)

| Scenario | Wall | Log |
|---|---|---|
| cross-emerge | **25.6 s** | 19 |
| chroot, no ccache | 8 m 04 s | 18 |
| chroot, ccache **cold** | 9 m 06 s (+13% miss overhead) | 23 |
| chroot, ccache **warm** | **6 m 35 s** (−27% vs no-ccache) | 23 |

Anatomy of the 8-minute chroot build: ~1–2 min Portage-under-qemu startup
(fixed per package), ~5–6 min **serial `./configure`** (every conftest is
compiled *and executed* under emulation, one at a time), ~2–3 min parallel
compile. This anatomy decides which optimizations can work at all:

> **ccache and distcc both accelerate only the compile phase.** Nothing except
> leaving emulation (cross-emerge / binpkg) fixes the configure phase or the
> Portage startup tax. That is why autotools packages show the worst ratios and
> why the warm-ccache win on nano is "only" 27% — the compile phase it erased
> was just 2.5 of the 8 minutes. cmake/meson packages and compile-heavy C++
> benefit far more.

## 1. ccache — IMPLEMENTED (2026-07-30)

**Iron rule: one cache per architecture.** The host's `/var/cache/ccache` holds
x86_64 objects and is never used for ARM work — a shared cache would at best
give zero hits (different compilers hash differently) and at worst mix
architectures.

| Build path | Cache | ccache binary | Config |
|---|---|---|---|
| cross-emerge | `/var/cache/ccache-xarm` (host, 10G) | host-native | sysroot `make.conf`: `FEATURES="… ccache"`, `CCACHE_DIR` |
| chroot | `/var/cache/ccache` *inside* the stage3 (10G) | aarch64, runs under qemu | stage3 `make.conf`: same two lines |

Notes:

- ccache reached the stage3 as a **cross-built binpkg** (`emerge
  --usepkgonly` from the sysroot PKGDIR bind-mounted in, logs 20/21) — the
  generic recipe for getting any tool into the chroot without an emulated
  build of its dep tree (cmake, in ccache's case).
- Even under qemu the hit path is cheap: hashing is I/O-bound, and a hit
  skips the entire emulated compiler invocation.
- Cold-cache overhead is real (~13% on nano). ccache pays off on **rebuilds**:
  `emerge -e` reruns, version bumps of big packages, the 1by1 census repeated
  after config changes. First-ever builds it only slows down slightly.
- Cross-side cache warms up during any 1by1/census run; check with
  `CCACHE_DIR=/var/cache/ccache-xarm ccache -s`.

## 2. distcc — IMPLEMENTED + MEASURED (2026-07-31)

Classic Embedded-Handbook trick: the emulated chroot sends compilations to the
host's `distccd`, which runs the **cross** compiler natively. Setup is now
automated (README experiment 9, logs 26/27):

- Host daemon: `sudo xarm distcc start` — loopback-only distccd
  (`--allow 127.0.0.1/32 --listen 127.0.0.1`, port 3632, 32 jobs); the qemu
  chroot shares the host network stack so 127.0.0.1 reaches it. `stop`/`status`
  round it out.
- Stage3 client: distcc entered as a **cross-built binpkg** (the ccache recipe;
  `--nodeps` — a deps-on `--usepkg` run tried to drag glib through qemu).
  `sudo xarm distcc chroot-setup [ROOT]` then writes the masquerade wrapper
  (plain `cc`/`gcc`/`g++`/`c++` → `${CHOST}-*` names, otherwise the host runs
  its native x86 gcc), `/etc/distcc/hosts` (`127.0.0.1:3632/32,lzo`), and
  checks gcc major parity (15 == 15; mismatch = ICE/miscompile).
- Enable per run: `FEATURES="distcc"` (or `"ccache distcc"`) in the emerge
  environment; the stage3 make.conf is deliberately left untouched.

**Measured (log 27; baselines from the table above):**

| Scenario | Wall | distcc jobs |
|---|---|---|
| nano, distcc only (`-ccache`) | 8 m 21 s (vs 8 m 04 s plain) | 120 |
| nano, ccache warm + distcc | 7 m 02 s (vs 6 m 35 s ccache alone) | 0 |
| zstd, plain chroot | 2 m 59 s | 0 |
| zstd, distcc | **48 s (3.7×)** | 14 |

Both result binaries verified: aarch64 ELF, run correctly under qemu.

**Why nano gains nothing:** distcc distributes only `-c` compile jobs.
Autoconf conftests are one-step compile+link → always local → the 5–6 min
serial configure is untouched, and nano's small files pay more in per-job
overhead (preprocessing under qemu + round-trip) than the remote compile saves.
zstd (Makefile, thin configure, bigger TUs) shows the real ceiling: the
compile phase collapses toward cross speed.

**Config traps found:**

- `CCACHE_PREFIX=distcc` + `DISTCC_FALLBACK=0` **breaks configure** ("C
  compiler cannot create executables"): conftest compile+link cannot be
  distributed and fallback is forbidden. Use plain `FEATURES="ccache distcc"`
  PATH chaining instead — measured: warm hits stay local (0 remote jobs),
  misses go remote.
- Adding distcc invalidates the existing ARM ccache once: ccache now hashes
  the masquerade wrapper as "the compiler", so the first combined run re-misses
  everything (~10 min observed) before the cache re-warms.

Verdict: distcc works and is kept as automation, but it only pays off for
compile-heavy/thin-configure packages *and* the chroot is pure insurance anyway
(0/190 packages needed it in the census). Wiki's ranking stands: prefer
cross-emerge/binhost (section 3); distcc is the fallback-of-the-fallback —
now a turbocharged one for the zstd-shaped cases.

## 3. The biggest lever: don't emulate at all

Ranked above any in-chroot tuning:

1. **cross-emerge first** — `xarm 1by1` already orders cross → chroot
   fallback; the census measures how rarely the fallback is needed.
2. **Binpkg import** — anything the sysroot can cross-build enters the stage3
   as a binary package in seconds (the ccache install recipe). Works for dep
   trees too; the stage3 and sysroot share the arm64/23.0 profile.
3. **Binhost for the Pi** — `xarm binhost`; the Pi never compiles what the
   host already built.

## 4. Smaller levers (chroot)

- `PORTAGE_TMPDIR` on tmpfs: stage3 builds churn `/var/tmp/portage` on
  /mnt/db1; a host tmpfs bind (64 GB RAM allows it) removes that I/O. Moderate
  win, biggest for many-small-files packages.
- `FEATURES="-sandbox -usersandbox"` in the stage3: every sandbox interception
  is a syscall through qemu; the namespace sandboxes are already off
  (`-pid-sandbox -ipc-sandbox -network-sandbox` — mandatory under qemu-user).
  Trade-off: less build isolation in a lab chroot that exists to be rebuilt.
- `FEATURES="noman noinfo nodoc"` + `BINPKG_COMPRESS="zstd"` with a low level:
  shaves the install/packaging tail of every emerge.
- `emerge --jobs=N` for independent packages amortizes the 1–2 min Portage
  startup tax across parallel merges — useful for stage3 world updates, not
  for the strictly serial 1by1 census.
- Keep `MAKEOPTS=-j32` (host cores): qemu-user TCG threads scale with guest
  threads, so the emulated make still uses all 32 host threads.

## What was tried and rejected

- **Sharing one ARM cache between cross and chroot builds** — the two compiler
  binaries (x86 cross-gcc vs aarch64 native gcc) hash differently, so there is
  no cross-pollination; keeping the caches separate costs nothing and prevents
  any architecture mixing.
- **Stable-keyword alignment of the sysroot** (would let the stage3 consume
  every sysroot binpkg pin-exactly): reverted — downgrades + slot conflicts
  against the ~arch-built sysroot; retry only as a deliberate migration.
