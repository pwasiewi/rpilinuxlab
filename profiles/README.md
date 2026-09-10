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

`/etc/xp.conf` also takes the data-volume roots — `XSTAGE_DIR`,
`XANDROID_DIR`, `XOWRT_DIR` (defaults under `/mnt/db5/`) — sourced by
xstage/xandroid/xowrt directly, so the overrides survive `sudo`. Same
precedence: explicit env > conf > built-in default. Keep the file
assignments-only (it is sourced as root).

Relocation caveat: files already generated under the old `XSTAGE_DIR` keep
absolute paths — `conf/catalyst*.conf` (`storedir`, `port_logdir`) and
`specs*/*.spec` (`portage_confdir`). After copying the tree, fix them in
place (here from `/mnt/db5` to `/mnt/NEW`):

```
sudo sed -i 's|/mnt/db5|/mnt/NEW|g' /mnt/NEW/genstage/conf/*.conf \
    /mnt/NEW/genstage/specs/*.spec /mnt/NEW/genstage/specs-arm64/*.spec
grep -rn /mnt/db5 /mnt/NEW/genstage/conf /mnt/NEW/genstage/specs*   # expect nothing
```

(or simply rerun `xstage <track> setup` + `spec`, which regenerates them
from the new `XSTAGE_DIR`). xandroid/xowrt keep no absolute paths in
generated files — only the env/conf variable matters there.

## Profiles

| profile | board | CPU | method | network |
|---|---|---|---|---|
| rpi400 | Pi 400 (BCM2711) | cortex-a72 | stage3 unpack (`arm64`) | eth0 192.168.0.200 |
| rpi3   | Pi 3 (BCM2710)   | cortex-a53 | stage3 unpack (`arm64`) | eth0 192.168.0.201 |
| zero2w | Pi Zero 2 W + e-Paper | cortex-a53 | tiny rootfs (cross-emerge) | usb0 10.0.0.2 |
| zero   | Pi Zero 2 W + e-Paper | cortex-a53 | stage3 unpack (`arm64`) | usb0 10.0.0.2, WiFi prepared |
| amd64  | native host | — | catalyst native | — |

## Per-profile build trees

Every board profile owns its rootfs/image tree under `../build/` via
`PROF_BUILD_SUBDIR` (rpi400 → `arm64sd-rpi400-systemd`, rpi400openrc →
`arm64sd-rpi400`, rpi3 → `arm64sd-rpi3`; zero2w stays on the tiny track's
`tinyroot`), so profiles never clobber each other's rootfs or `sd.img`. Two
profiles for one board is exactly what that buys: rpi400 and rpi400openrc
describe the same hardware with different init systems, and each keeps its own
card image. Bare `xstage arm64` (no profile) uses plain
`arm64sd` as a scratch tree. `xstage clean all` removes `arm64sd*` — all
variants at once; `xp <profile> xstage arm64 clean` removes just one.

## Wireless on the `zero` profile

The Zero 2 W has no ethernet, so `zero` ships two radios' worth of support and
enables neither — credentials are typed on the running board, never baked into
an image.

| interface | hardware | driver | firmware | bands |
|---|---|---|---|---|
| `wlan0`  | onboard, SDIO | `brcmfmac` | `sys-firmware/raspberrypi-wifi-ucode` | 2.4 GHz |
| `wlanac` | COMFAST CF-922AC on USB | `mt76x2u` | `mediatek/mt7662{,_rom_patch}.bin` | 2.4 + 5 GHz |

The CF-922AC is a MediaTek MT7612U. Its driver is in-tree and
`sys-kernel/raspberrypi-image` already ships it, so three things are left for
the profile to do, and all three live in the `zero` overlay layer:

- **Firmware.** `sys-kernel/linux-firmware` installs 2.0 GB by default — more
  than the whole image. `etc/portage/savedconfig/sys-kernel/linux-firmware`
  cuts it to the ~108 KB of mt7662 blobs (plus their two compat symlinks, which
  is what `modinfo` actually asks for). That file is reached through
  `PROF_BOARD_PORTAGE_CONFDIR`; `xarm setup`/`xarm tune` copy `savedconfig/`
  into the sysroot **verbatim**, unlike every other fragment class, because
  `savedconfig.eclass` finds its file by exact `CATEGORY/PF|P|PN` name only.
- **ZeroCD.** The stick powers up as a USB CD-ROM (`0e8d:2870`) holding a
  Windows installer and does not time out into WiFi mode on its own.
  `etc/udev/rules.d/70-cf922ac.rules` ejects it, the firmware re-enumerates as
  `0e8d:7612`, and `mt76x2u` binds off the modalias. `eject(1)` is util-linux,
  already in the stage3 — `sys-apps/usb_modeswitch` would drag tcl and libusb
  onto a 512 MB board to send the same SCSI command.
- **Naming.** The same rule pins the stick to `wlanac`, outside the kernel's
  `wlanN` namespace, so `/etc/conf.d/net` can be written before the hardware
  has ever been seen.

**One port, one role.** `dtoverlay=dwc2` defaults to `dr_mode=otg`, so the
cable decides: a plain data cable to a PC gives the g_ether gadget and `usb0`,
a micro-USB OTG adapter gives host mode and the CF-922AC. They are mutually
exclusive — with the stick plugged in there is no `usb0` and no ssh over the
gadget link, so reach the board over WiFi or the serial console, and power it
from PWR IN. `genstage/rpi/config-zero.txt` carries the explicit `dr_mode=`
alternatives.

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
`PROF_CPU`, `PROF_BOARD` (rpi400|rpi3|zero2w|zero), `PROF_QEMU_MACHINE`,
`PROF_DTB`, `PROF_IP`, `PROF_GW`, `PROF_DNS`, `PROF_IMAGE_CMD`.
Optional: `PROF_BUILD_SUBDIR`, `PROF_PKGS`.
Derived: the image root password AND the rootfs partition label both default
to `<profile>root` (rpi400 → `rpi400root`); override with
`XSTAGE_ROOT_PASS=…` / `XSTAGE_ROOT_LABEL=…` at `image` time. Bare `xstage`
(no profile) keeps the old defaults `tiny` / `tinyroot`. The label goes into
`mkfs.ext4 -L` and the image's fstab together, so it changes only on the next
`image` run (ext4 labels max 16 chars ⇒ profile names ≤ 12).
Shared globals (override in env if needed): `LAB_MIRROR`, `LAB_FLAVOR`,
`LAB_JOBS`, `LAB_DISTCC_PORT`, `LAB_BINHOST_PORT`, `LAB_SSH_FWD_XSTAGE`.
