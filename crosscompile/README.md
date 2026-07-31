# Cross-compiling Gentoo x86_64 → aarch64 — lab results

Experiments run 2026-07-30 on the gen2db host (AMD Ryzen AI, 64 GB RAM, Gentoo
~amd64, Portage 3.0.81.2, gcc-15) using `~/Claude/bin/xarm` (mirrored to
`/usr/local/bin/xarm`; a snapshot ships in this repo as `../xarm`).
Lab artifacts live in `crosscompile/` (this directory);
heavy artifacts (stage3 chroot) on `/mnt/db1/rpilinuxlab/`.

Goal: working cross-compilation both **natively** (crossdev + cross-emerge into a
sysroot) and in a **QEMU user-mode chroot** (aarch64 stage3), **without touching the
host's `/etc/portage`** beyond crossdev's own additive files — plus a plan for a
durable x86_64 + arm64 coexistence layout.

## Layout

```
~/Claude/rpilinuxlab/
└── crosscompile/
    ├── README.md               ← this file
    ├── manual-setup.md         # copy-paste command sequence — full setup WITHOUT xarm
    ├── xarm-setup.md           # the same via xarm (6 commands) + step↔gotcha mapping
    ├── optimizations.md        # compile-speed levers: ccache (done), distcc (planned), ranked
    ├── arm64-chroot.sh         # chroot helper for the stage3 on /mnt/db1
    ├── census-driver.sh        # overnight pipeline: update → ccache bench → 1by1 census
    ├── tests/                  # C test programs + built binaries
    └── logs/                   # experiment logs

/usr/aarch64-unknown-linux-gnu/          # crossdev sysroot (fixed path)
/mnt/db1/rpilinuxlab/arm64-chroot/       # standalone aarch64 stage3
```

## Initial host state (before experiments)

- `sys-devel/crossdev` and `app-emulation/qemu` (USE=static-user,
  QEMU_USER_TARGETS=aarch64) already installed; `/usr/bin/qemu-aarch64` **static** ✓
- **No** aarch64 binfmt handler (only stale `arm`/`armeb` from the armv7a era)
- **No** sysroot, **no** crossdev overlay registered, `xarm setup` never run
- Host make.conf: no LTO (the classic crossdev breaker) — safe to build cross-gcc

## Experiment log

### 1. `xarm setup` — crossdev toolchain ✓ (~20 min, unattended)

`sudo xarm setup` ran end-to-end with **zero manual intervention**
(log: `logs/01-xarm-setup.log`):

- crossdev overlay created via eselect-repo → registered in
  `/etc/portage/repos.conf/eselect-repo.conf` as `[crossdev]` at
  `/var/db/repos/crossdev` (ebuild forwarding dir actually materialized under
  `/home/tmp/.repos/crossdev` per this host's eselect-repo config)
- toolchain built in order: binutils 2.46 → gcc-stage1 → linux-headers →
  glibc 2.43 → gcc-stage2 (final gcc 15.3, same major as host — distcc-safe)
- profile `default/linux/arm64/23.0` set via
  `PORTAGE_CONFIGROOT=${SYSROOT} eselect profile set`
- sysroot make.conf tuned for cortex-a72, `PKGDIR="${ROOT}var/cache/binpkgs"`,
  `FEATURES="buildpkg -pid-sandbox -ipc-sandbox -network-sandbox"`
- binfmt `qemu-aarch64` registered (systemd-binfmt path)

**Host footprint in `/etc/portage` (all additive, all named `cross-aarch64-unknown-linux-gnu`,
removable with `crossdev --clean`):**

```
/etc/portage/repos.conf/eselect-repo.conf          # + [crossdev] section
/etc/portage/package.use/cross-aarch64-unknown-linux-gnu
/etc/portage/package.accept_keywords/cross-aarch64-unknown-linux-gnu
/etc/portage/package.env/cross-aarch64-unknown-linux-gnu
/etc/portage/env/cross-aarch64-unknown-linux-gnu
/etc/portage/profile/package.use.mask/cross-aarch64-unknown-linux-gnu
```

Nothing pre-existing was modified. The sysroot has **no repos.conf of its own** —
with `PORTAGE_CONFIGROOT=${SYSROOT}` Portage falls through to the host's repo
config, so the gentoo tree (on this host: `/home/tmp/.portage`) is found
automatically; `${SYSROOT}/etc/portage/make.profile` is a relative symlink into it.

### 2. C test programs under qemu-user ✓

`tests/` (log: `logs/05-c-tests.log`):

| Test | Build | Run | Result |
|---|---|---|---|
| hello static | `${T}-gcc -static` | `./hello-static` (transparent binfmt exec) | `hello from aarch64 (Linux)` ✓ |
| hello dynamic | `${T}-gcc -mcpu=cortex-a72` | `qemu-aarch64 -L ${SYSROOT} ./hello-dyn` | ✓ |
| 8 threads × 100k atomics, static+dyn | `-pthread` | both ways | `counter=800000 OK` ✓ — qemu-user thread emulation sound |
| hello dynamic, transparent exec | — | `./hello-dyn` without `-L` | **fails**: `Could not open '/lib/ld-linux-aarch64.so.1'` — expected; binfmt has no `-L`, host has no aarch64 ld.so. Static binaries run transparently, dynamic ones need `qemu-aarch64 -L` or a chroot |

### 3. cross-emerge real packages into the sysroot — ✓ with one big gotcha

| Package | Wall time | Result |
|---|---|---|
| `sys-libs/zlib` | **7.6 s** | ✓ aarch64 `libz.so` + binpkg |
| `app-editors/nano` (+ncurses, libintl) | **3 m 07 s** | ✓ all three, binpkgs produced |
| `dev-lang/perl`, attempt 1 | died at dep #10 | ✗ split-usr (gotcha #1) |
| `dev-lang/perl`, attempts 2–3 (post-usr-merge, 110-pkg chain) | 55 pkgs OK, then ✗ | gcc-16 skew → gcc-15 build bug (gotchas #2, #3) |
| `dev-lang/perl`, final (42-pkg chain, `-openmp`) | **14 m 37 s** | ✓ **including perl 5.44 itself** — Gentoo's ebuild carries perl-cross support; `perl -v` runs in the qemu chroot: `perl cross OK: linux v5.44.0` |
| `xarm 1by1 sys-apps/less` | seconds | ✓ loop machinery works: 2 cross, 0 chroot, 0 failed; resume via `/var/tmp/xarm/done.log` |

**End state: 115 aarch64 packages merged, 115 binpkgs, sysroot 580 MB**
(after clearing `${SYSROOT}/tmp/portage` — the failed gcc build trees alone
held ~3 GB). Perl — the canonical "runs freshly built binaries" cross failure —
built in **layer 1** without ever needing the chroot fallback.

Speed reference: the same-scale package (`sys-apps/which`) built **inside the QEMU
chroot** takes 2 m 22 s — cross-emerge is ~20× faster (qemu-user tax), which is the
whole point of layer 1.

**Gotcha (reproduced, then fixed): crossdev sysroot is split-usr, 23.0 profiles are
merged-usr.** crossdev creates real `bin/ sbin/ lib/ lib64/` directories. Simple leaf
packages merge fine, but as soon as baselayout entered the dep chain the 23.0
`profile.bashrc` check hard-fails every subsequent setup phase:

```
ERROR: virtual/libiconv-0-r2 failed (setup phase):
  ERROR: 23.0 merged-usr profile, but disk is split-usr
```

Side-effect seen before the fix: `nano` landed in `${SYSROOT}/bin/nano` (its ebuild
uses `--bindir=/bin`) — binpkgs built from a split-usr sysroot would ship split-usr
paths to a merged-usr Pi.

**Fix applied** (log: `logs/09-sysroot-usrmerge.log`) — usr-merge the sysroot,
mirroring the host's 23.0 layout, with nothing mounted under it:

```bash
cd /usr/aarch64-unknown-linux-gnu
cp -a bin/.  usr/bin/  && rm -rf bin  && ln -s usr/bin  bin
cp -a sbin/. usr/bin/  && rm -rf sbin && ln -s usr/bin  sbin
cp -a lib/.  usr/lib/  && rm -rf lib  && ln -s usr/lib  lib
cp -a lib64/. usr/lib64/ && rm -rf lib64 && ln -s usr/lib64 lib64
cp -a usr/sbin/. usr/bin/ && rm -rf usr/sbin && ln -s bin usr/sbin
```

→ **applied to `xarm setup`** (idempotent step 2b) right after crossdev finishes.
Old `/bin`-path entries in already-merged packages' CONTENTS keep resolving
through the new symlinks.

**Gotcha #2 (reproduced, then fixed): target gcc version skew.** After the
usr-merge fix the perl chain ran 55+ packages deep, then the resolver pulled
`sys-devel/gcc-16.1.1_p20260718` *into the sysroot* (gcc provides the target's
runtime libs) and it failed in libatomic's configure:

```
aarch64-unknown-linux-gnu-cc: error: unrecognized command-line option '-fno-link-libatomic'
configure: error: C compiler cannot create executables
```

`-fno-link-libatomic` exists only in gcc-16 — but the external compiler doing the
build is the **gcc-15 cross toolchain**. Root cause of the version skew: crossdev's
generated sysroot make.conf defaults to `ACCEPT_KEYWORDS="${ARCH} ~${ARCH}"`
(unstable!), so the target wanted a newer gcc than the cross compiler. Two fixes:

- this sysroot (already has ~arm64 packages): mask in the **sysroot's** config —
  `${SYSROOT}/etc/portage/package.mask/gcc-skew` with `>=sys-devel/gcc-16` →
  resolver picks gcc-15.3.1, same major as the cross toolchain
- `xarm setup` (fresh setups): appends `ACCEPT_KEYWORDS="${ARCH}"` (stable only)
  to the sysroot make.conf — also the right thing for binhost compatibility with
  a stable-keyword Pi

Rule of thumb: **target gcc major == cross-toolchain gcc major** (same rule
distcc already imposes).

**Gotcha #3 (hit, then sidestepped): cross-emerging `sys-devel/gcc` itself is a
no-go.** Even version-matched gcc-15.3.1 dies mid-build with missing *generated*
headers (`fatal error: treestruct.def: No such file`, `defaults.h` — the
build-tree race/layout issue of the gcc ebuild under cross-emerge). Nothing
actually needed the gcc *compiler* in the sysroot — it was pulled in only as the
provider of **libgomp** by `USE=openmp` packages (libb2, portage-utils). Sidesteps:

- applied: global `USE="${USE} -openmp"` in the **sysroot** make.conf → gcc drops
  out of the graph entirely (re-enable once the target has a native gcc, e.g.
  built on the Pi or in the chroot overnight)
- alternative (for a full `@system` sysroot): `${SYSROOT}/etc/portage/profile/
  package.provided` with `sys-devel/gcc-15.3.0` + copy the target runtime libs
  the cross toolchain already ships (`/usr/lib/gcc/aarch64-unknown-linux-gnu/15/
  {libgcc_s.so*,libstdc++.so*,libgomp.so*,libatomic.so*}` → `${SYSROOT}/usr/lib64/`)
- last resort: build gcc in the QEMU chroot (native-style build under emulation —
  hours; that is what `1by1`'s fallback would do)

### 4. QEMU stage3 chroot ✓

- Downloaded `stage3-arm64-openrc-20260726T221557Z.tar.xz` (354 MB, sha256 OK)
  from distfiles.gentoo.org → unpacked to `/mnt/db1/rpilinuxlab/arm64-chroot`
  (1.8 GB) with `tar xpf --xattrs-include='*.*' --numeric-owner`.
- Chroot's own `/etc/portage/make.conf` (inside the chroot — host untouched)
  appended: `MAKEOPTS="-j8"`, `FEATURES="-pid-sandbox -ipc-sandbox
  -network-sandbox -news"`, `ACCEPT_LICENSE="*"` (sandbox namespaces do not work
  under qemu-user).
- Entry helper: `arm64-chroot.sh` (same trap-umount pattern as
  `xarm chroot`; copies static qemu-aarch64 inside because Gentoo's binfmt uses
  OC flags; ad-hoc binfmt registration if systemd-binfmt hasn't run).
- **Smoke test ✓** (`logs/02-chroot-smoke.log`): `uname -m` = aarch64, native
  aarch64 gcc 15.3.0, Python 3.14.6, 32 emulated CPUs. Cosmetic:
  `setlocale LC_ALL pl_PL.utf8` warning (host locale absent in stage3) — benign.
- **Emerge under emulation ✓** (`logs/03-chroot-emerge-which.log`):
  `emerge -1v sys-apps/which` = **2 m 22 s** wall, ~all of it user time (qemu
  translation). Same-scale cross-emerge: seconds. Emulation is the fallback, not
  the main road.

**Host quirk found (affects `xarm chroot` too):** this host's gentoo tree is
*not* at `/var/db/repos/gentoo` — `/var/db/repos/` holds only overlays, the main
tree lives at `/home/tmp/.portage` (and DISTDIR at `/var/tmp/distfiles`).
`xarm chroot` bind-mounts `/var/db/repos`, so inside the chroot the default
`repos.conf` pointed at a nonexistent tree → emerge refused to run
("Section 'gentoo' … nonexistent directory"). `arm64-chroot.sh` resolves the real
paths via `portageq get_repo_path / gentoo` / `portageq distdir` and binds them at
the locations the chroot expects. **The same fix should go into `xarm chroot`.**

### 5. `xarm chroot` into the sysroot — fails while pure-cross, works once seeded

Fresh after `xarm setup`:

```
chroot: failed to run command '/bin/bash': No such file or directory
```

A freshly crossdev-ed sysroot has glibc + a couple of cross-merged packages but no
aarch64 bash/coreutils, so the chroot layer (and therefore the `1by1` chroot
fallback) is **not functional until the sysroot is seeded** — either by
cross-emerging enough of `@system` (bash arrived ~55 packages into perl's dep
chain here), or by unpacking a stage3 over the sysroot (`tar --skip-old-files` to
not clobber crossdev's `etc/portage`), or by pointing the chroot layer at the
standalone stage3 (`arm64-chroot.sh`). Until then `1by1`'s "fall back to chroot"
arm always reports failure.

After bash was cross-merged, the (patched — see below) `xarm chroot` works
(`logs/14-xarm-chroot-sysroot.log`): aarch64 bash under emulation, host overlays
visible, arm64/23.0 profile symlink resolves through the mirrored repo bind.

### 5b. Fixes folded back into `bin/xarm` (2026-07-30)

All four findings above are now handled by the script itself
(mirrored to `/usr/local/bin/xarm`):

- **setup 2b:** idempotent sysroot usr-merge right after crossdev, before any
  emerge (refuses if anything is mounted under the sysroot)
- **setup 2c:** writes `${SYSROOT}/etc/portage/repos.conf/gentoo.conf` pinning the
  gentoo repo to its real host path (`portageq get_repo_path / gentoo`)
- **setup make.conf block:** appends `ACCEPT_KEYWORDS="${ARCH}"` (stable-only) —
  prevents the gcc-16-style version skew and matches a stable-keyword Pi
- **chroot:** resolves the gentoo tree and DISTDIR via portageq and bind-mounts
  the tree at its host path inside the chroot (profile symlink + repos.conf both
  resolve), instead of assuming `/var/db/repos/gentoo` + `/var/cache/distfiles`
- **binfmt_register:** upgrades an earlier ad-hoc registration to the persistent
  `/etc/binfmt.d/qemu.conf` + systemd-binfmt path instead of early-returning on
  "already registered" (that ordering quirk is exactly how this host ended up
  volatile: the stage3 helper had registered ad-hoc before `xarm setup` ran);
  make.conf block also gained `USE="${USE} -openmp"` (gotcha #3). Applied here
  2026-07-30 — binfmt on this host is now persistent

### 6. `xarm binhost` — delivery path for the Pi ✓

Served `${SYSROOT}/var/cache/binpkgs` on :8686; index lists `Packages`,
`Packages.gz` + category dirs; `HEAD /app-editors/nano-9.1.tbz2` → HTTP 200.
The Pi-side config is printed by the command itself (binrepos.conf snippet).

### 7. Benchmark: same package, cross-emerge vs QEMU chroot (2026-07-30)

Controlled A/B on `app-editors/nano-9.0`: identical ebuild tree (bind-mounted),
shared distfiles, `MAKEOPTS=-j32` and `FEATURES=-buildpkg` forced on both sides.
Full emerge wall time (unpack → configure → compile → install), timed with `time`:

| Mode | Wall | User CPU | Ratio (wall) |
|---|---|---|---|
| cross-emerge (host aarch64-gcc) | **25.6 s** | 24.8 s | 1× |
| QEMU stage3 chroot | **8 m 04 s** | 11 m 42 s | **≈19×** |

- CPU cost ratio is even worse (~28× user time); wall lands at 19× only because
  the compile phase still parallelizes across 32 emulated threads.
- The dominant chunk of chroot time is the **serial `./configure` phase** — every
  conftest compile+run goes through qemu one at a time (configure started ~1 min
  in and was still running at the 6-minute mark).
  Autotools packages are therefore the worst case; cmake/meson should fare
  relatively better.
- Floor check: bare `emerge` of trivial `app-misc/which` under emulation was
  already 2 m 22 s (log 03) — Portage's own Python startup under qemu is a fixed
  ~1–2 min tax per package, which is why `1by1`'s cross-first ordering matters.
- **Keyword skew gotcha found on the way:** the sysroot accepts `~arm64`
  (`ACCEPT_KEYWORDS="arm64 ~arm64"` in its make.conf) while the stage3 chroot is
  stable-only — the first cross run silently built nano-**9.1** vs the chroot's
  **9.0**. Same skew would make a stable Pi reject/rebuild binhost packages;
  align `ACCEPT_KEYWORDS` across sysroot, chroot and the Pi before serving.

### 8. ARM ccache + full `-e @world` census pipeline (2026-07-30/31 — DONE)

Goal: (a) speed up chroot compilation with ccache, (b) census how many of the
sysroot's `-e @world` closure cross-compile vs need the stage3 chroot.

**ccache — strict per-architecture split** (never mix with the host's x86
`/var/cache/ccache`):

| Where | Cache dir | Used by |
|---|---|---|
| host | `/var/cache/ccache-xarm` (10G) | cross-emerge layer 1 (host-native ccache) |
| stage3 | `/var/cache/ccache` *inside* the chroot | emulated builds (aarch64 ccache) |

ccache got into the stage3 **as a cross-built binpkg** (`emerge --usepkgonly`
from the sysroot's PKGDIR bind-mounted in) — avoids compiling cmake+ccache under
qemu. Logs 20/21.

**xarm extensions** (mirrored to /usr/local/bin): `XARM_CHROOT_ROOT` (point
`chroot` at any root, e.g. the stage3); `1by1 --fresh` (rotates logs), done.log
now `atom<TAB>mode<TAB>seconds`; `XARM_STAGE3` — 1by1's fallback chroots into
the stage3 (native gcc-15.3; the sysroot has no target gcc so real compile
fallbacks were impossible before), version pin dropped there (keyword lag);
1by1's pretend parser now keeps only target-ROOT lines (`to ${SYSROOT}/`) —
with `-e` the cross pretend also lists ~800 host-side BDEPEND rebuilds that
must not be touched.

**Stable-keyword flip attempted and reverted:** aligning the sysroot to
stable-only produced downgrades + slot conflicts against the ~arch-built
sysroot; the line stays commented in the sysroot make.conf as a future
migration. Stage3 remains stable — hence the version-pin drop in the fallback.

**Census:** target packages from `-e @world` + `dev-lang/perl` added
explicitly (it is not in the target @world closure — was built --oneshot).
Driver: `census-driver.sh` (phases: stage3 update → ccache
cold/warm nano bench → census → summary), logs 22–25.

**RESULTS (2026-07-31 01:26, log 25):**

- **190 / 190 packages cross-compiled — 0 needed the chroot, 0 failed.**
  Total 69.1 min wall for the whole `-e @world` rebuild.
- Slowest: gcc 475 s, perl 304 s, glibc 171 s, ncurses 156 s, python 133 s.
- **The "gcc is not cross-emergeable" hard limit FELL**: gcc-15.3.1_p20260717
  cross-emerged in 8 min (the earlier failures were 15.3.0 + the gcc-16 skew).
  Verified functional: inside `xarm chroot` the target `gcc-15` (aarch64 ELF)
  compiles and the binary runs correctly under qemu. The sysroot now owns a
  native compiler ⇒ `USE="-openmp"` can be lifted when needed, and the sysroot
  chroot is finally self-hosting for compile fallbacks.
- Phase timings: stage3 update (8 pkgs) 1 h 24 min under qemu; ccache bench
  9m06s cold / **6m35s warm** (vs 8m04s no-ccache — see
  `optimizations.md`); census 1 h 10 min.
- Host ARM ccache after the run: 39 K cacheable calls, 9% hits already
  (within-run duplicates); the cache is now seeded for future reruns.
- Consequence for the pipeline: the qemu chroot is demoted from "required for
  perl/gcc-class packages" to insurance for packages that run their own
  freshly built binaries in ways cross-emerge cannot satisfy — in this
  190-package closure there were none.

### 9. distcc from the chroot — host cross-gcc as compile backend (2026-07-31)

Goal: quantify the last unimplemented lever from `optimizations.md`
§2 — the emulated chroot offloading compile jobs to the host's `distccd`
running the crossdev toolchain natively. Setup automated as **`xarm distcc
start|stop|status|chroot-setup`**; details + gotchas in log 26, benchmarks in
log 27.

Pipeline proven end-to-end: chroot's masqueraded plain `gcc` travels as
`aarch64-unknown-linux-gnu-gcc`, the host executes the cross compiler (COMPILE_OK
195 ms vs seconds emulated), objects and final binaries are aarch64 ELF and run
under qemu (nano 9.0, zstd 1.5.7 verified).

**Results (nano baselines: 8m04s plain / 6m35s warm ccache):**

- nano + distcc: **8m21s** (120 jobs offloaded) — no gain; conftests are
  compile+link → never distributed → serial configure still dominates, and
  small TUs pay more round-trip than they save.
- nano + ccache(warm) + distcc: **7m02s**, 0 remote jobs — hits stay local,
  distcc idles; ≈ ccache-alone within noise.
- zstd plain **2m59s** → distcc **48s (3.7×**, 14 jobs) — Makefile package,
  thin configure: the compile phase collapses toward cross speed.
- Broken combo found: `CCACHE_PREFIX=distcc` + `DISTCC_FALLBACK=0` kills
  configure ("C compiler cannot create executables"); use plain
  `FEATURES="ccache distcc"` chaining. Also: enabling distcc re-colds the ARM
  ccache once (the wrapper becomes the hashed "compiler").

Verdict: worth keeping as automation, irrelevant for the pipeline's critical
path — the census left the chroot as pure insurance, and within that insurance
distcc only accelerates zstd-shaped (compile-heavy) packages. For a physical Pi
the same `chroot-setup` logic applies via `xarm distcc-wrapper`, but binhost
remains the delivery method of choice.

## /etc/portage coexistence plan (x86_64 host + arm64 target)

**Conclusion from the experiments: full coexistence needs no modification of any
pre-existing host file.** Portage's `PORTAGE_CONFIGROOT` separation is the whole
mechanism — three independent config universes:

| Universe | Config root | Touched by |
|---|---|---|
| x86_64 host | `/etc/portage` | normal `emerge` only |
| arm64 sysroot | `/usr/aarch64-unknown-linux-gnu/etc/portage` | `emerge-aarch64-unknown-linux-gnu` (= `xarm emerge`) |
| arm64 stage3 chroot | `/mnt/db1/rpilinuxlab/arm64-chroot/etc/portage` | emerge run inside the chroot |

### What lands in the host `/etc/portage` (additive-only, inventory)

Already present after `xarm setup` (all removable via `crossdev --clean --target
aarch64-unknown-linux-gnu`):

- `repos.conf/eselect-repo.conf` — `[crossdev]` section (the one shared-file edit;
  to make it a pure file-add instead, pre-create `repos.conf/crossdev.conf` the way
  `xarm setup`'s manual branch does)
- `package.use/cross-aarch64-unknown-linux-gnu`
- `package.accept_keywords/cross-aarch64-unknown-linux-gnu`
- `package.env/cross-aarch64-unknown-linux-gnu` + `env/cross-aarch64-unknown-linux-gnu`
- `profile/package.use.mask/cross-aarch64-unknown-linux-gnu`

Planned additions, each again a separate new file, only when the need appears:

1. **Rust cross-std** (only if arm packages pulling Rust show up):
   `/etc/portage/env/dev-lang/rust` with
   `RUST_CROSS_TARGETS=("AArch64:aarch64-unknown-linux-gnu:aarch64-unknown-linux-gnu")`
   then `emerge -1 dev-lang/rust` (rust-bin cannot do this).
2. **distcc GCC USE parity** (only if distcc to the Pi is used): extend
   `package.use/cross-aarch64-unknown-linux-gnu` with the same gcc USE as the Pi's
   (e.g. `graphite`); keep gcc major versions identical on both sides.
3. **Persistent binfmt** (system config, not /etc/portage):
   `ln -s /usr/share/qemu/binfmt.d/qemu.conf /etc/binfmt.d/qemu.conf` — otherwise
   the aarch64 handler is re-registered ad hoc and lost on reboot.

### Rules that keep the host safe

- Never plain `emerge` for arm — only the `emerge-${CHOST}` wrapper / `xarm emerge`;
  the wrapper sets `ROOT`, `SYSROOT`, `PORTAGE_CONFIGROOT` and cannot touch `/`.
- All arm package tuning (USE, keywords, masks) goes into
  `${SYSROOT}/etc/portage/package.*` — never the host's.
- The stale `arm`/`armeb` binfmt handlers from the armv7a era still exist; they
  only claim 32-bit ARM ELFs, harmless for aarch64. Deregister with
  `echo -1 > /proc/sys/fs/binfmt_misc/arm` if 32-bit work ever resumes.
- Full rollback: `sudo xarm clean` (= `crossdev --clean` + optional sysroot
  removal), delete `/mnt/db1/rpilinuxlab/arm64-chroot`, remove the binfmt.d
  symlink. Host is back to pre-experiment state.

## Verdict

Both requested modes work on this host, with the host `/etc/portage` untouched
except crossdev's clearly-named additive files:

1. **Native cross (crossdev + cross-emerge)** — primary road. Measured **19×
   faster** than emulation (nano A/B, experiment 7); the full 190-package
   `-e @world` census (experiment 8) built **100% cross, including gcc, glibc,
   perl and python** — 69 min total. Needs the three one-time sysroot fixes now
   baked into `xarm setup` (usr-merge, pinned repos.conf, stable keywords).
   ~~Hard limit: target `sys-devel/gcc` cannot be cross-emerged~~ — held only
   for gcc-15.3.0; gcc-15.3.1_p20260717 cross-emerges and works (experiment 8).
2. **QEMU chroot** — two flavors, both working: the standalone stage3 on
   `/mnt/db1` (`arm64-chroot.sh`; self-contained, good for
   config experiments and packages that must run their own binaries) and
   `xarm chroot` into the sysroot (functional once bash is cross-merged;
   this is `1by1`'s fallback arm). Measured cost: **19× wall / 28× CPU** vs
   cross (experiment 7), plus a fixed ~1–2 min Portage-under-qemu tax per package.

Next steps when a Pi 400 actually appears: `xarm 1by1 @system`, overnight; gcc
via chroot or natively on the Pi; deliver everything else with `xarm binhost`.

## Log index (`logs/`)

| Log | Contents |
|---|---|
| 01-xarm-setup.log | full crossdev toolchain build |
| 02-chroot-smoke.log | stage3 chroot first entry |
| 03-chroot-emerge-which.log | emerge under emulation, timed (2 m 22 s) |
| 04-xarm-status-after-setup.log | toolchain status snapshot |
| 05-c-tests.log | C smoke tests (static/dynamic/threads) |
| 06/07-cross-emerge-{zlib,nano}.log | layer-1 cross-emerge timings |
| 08-cross-emerge-perl.log | gotcha #1: split-usr profile death |
| 09-sysroot-usrmerge.log | the usr-merge conversion |
| 10/12-cross-emerge-perl-{retry,resume}.log | gotcha #2/#3: gcc-16 skew, gcc-15 build bug |
| 13-cross-emerge-perl-final.log | gcc-15 failure signature |
| 14-xarm-chroot-sysroot.log | patched `xarm chroot` into seeded sysroot |
| 15-cross-emerge-perl-final2.log | ✓ 42-pkg chain incl. perl 5.44 |
| 16-1by1-less.log | `xarm 1by1` loop demo |
| 17-bench-cross-nano.log | benchmark: cross-emerge nano-9.1, 25.0 s |
| 18-bench-chroot-nano.log | benchmark: qemu chroot nano-9.0, 8 m 04 s |
| 19-bench-cross-nano90.log | benchmark: cross-emerge nano-9.0 (version-matched), 25.6 s |
| 20-cross-ccache.log | cross-emerge ccache + deps (binpkgs for the stage3) |
| 21-stage3-ccache-install.log | ccache binpkg install inside the stage3 |
| 22-stage3-update.log | census phase A: stage3 `emerge -uvDN @world` |
| 23-ccache-bench.log | census phase B: nano cold vs warm ARM ccache |
| 24-census-1by1.log | census phase C: `1by1 --fresh -e @world` + perl |
| 25-census-summary.log | census phase D: mode counts, timings, ccache stats |
| 26-distcc-setup.log | distcc host daemon + stage3 client setup, gotchas, smoke test |
| 27-distcc-bench.log | distcc benchmarks: nano ±ccache, zstd plain vs distcc, binary verification |
