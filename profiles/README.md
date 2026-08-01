# xp profiles — one environment per board (or per experiment)

A profile is a small data file describing one lab environment: which board,
which CPU tuning, which network address, which installation method. The `xp`
dispatcher (and, standalone, `XPROFILE=<name> xarm|xstage|xlab …`) sources
`global.conf` + `<name>.conf` and exports the values as the `XARM_*` /
`XSTAGE_*` / `XLAB_*` env overrides the three scripts already understand.
Precedence: **explicit env var > profile > script built-in default**.

## Setup (once per machine)

The `/usr/local/bin/xp` copy needs to know where this repo lives:

```
echo "XP_LAB_DIR=$HOME/Claude/rpilinuxlab" | sudo tee /etc/xp.conf
```

Running `./xp` from the repo needs no conf (it finds `profiles/` next to
itself). `XP_LAB_DIR` in the environment overrides both.

## Profiles

| profile | board | CPU | method | network |
|---|---|---|---|---|
| rpi400 | Pi 400 (BCM2711) | cortex-a72 | stage3 unpack (`arm64`) | eth0 192.168.0.200 |
| rpi3   | Pi 3 (BCM2710)   | cortex-a53 | stage3 unpack (`arm64`) | eth0 192.168.0.201 |
| zero2w | Pi Zero 2 W + e-Paper | cortex-a53 | tiny rootfs (cross-emerge) | usb0 10.0.0.2 |
| amd64  | native host | — | catalyst native | — |

## Variant profiles

Copy a conf under a new name and change what differs:

```
cp rpi400.conf rpi400kde.conf     # then set:
PROF_BUILD_SUBDIR=arm64sd-kde     # own rootfs/image tree under ../build/
PROF_PKGS="kde-plasma/plasma-meta"   # installed by: xp rpi400kde pkgs
```

Variants share the crossdev sysroot and its binpkg cache, so the second
variant mostly installs prebuilt packages. `PROF_XSTAGE_TARGET` switches the
installation method itself: `arm64` = unpack a stage3 tarball, `tiny` =
cross-emerge a fresh rootfs package-by-package.

## CPU tuning — one sysroot, `-mtune` only

All ARM profiles share one sysroot/vdb/binpkg store. The managed block that
`xarm setup`/`xarm tune` writes into the sysroot `make.conf` uses
`-march=armv8-a -mtune=${PROF_CPU}`: A72 and A53 are both ARMv8.0-A, so every
binary runs on every board; `-mtune` only changes instruction scheduling for
*future* builds. Escape hatch (not implemented): per-CPU builds would need
`-mcpu` plus a per-profile `PKGDIR` split — rejected as triple build time for
a few percent of tuning.

## Variables

Required always: `PROF_NAME`, `PROF_KIND` (board|native),
`PROF_XSTAGE_TARGET`, `PROF_XLAB_TARGET`.
Required for `PROF_KIND=board`: `PROF_TUPLE`, `PROF_PORTAGE_PROFILE`,
`PROF_CPU`, `PROF_BOARD` (rpi400|rpi3|zero2w), `PROF_QEMU_MACHINE`,
`PROF_DTB`, `PROF_IP`, `PROF_GW`, `PROF_DNS`, `PROF_IMAGE_CMD`.
Optional: `PROF_BUILD_SUBDIR`, `PROF_PKGS`.
Shared globals (override in env if needed): `LAB_MIRROR`, `LAB_FLAVOR`,
`LAB_JOBS`, `LAB_DISTCC_PORT`, `LAB_BINHOST_PORT`, `LAB_SSH_FWD_XSTAGE`.
