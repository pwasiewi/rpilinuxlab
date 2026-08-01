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

## Booting the Pi 400 (tiny → real hardware)

```
sudo ./xstage tiny rpi             # kernel8.img + firmware + DTBs into rootfs/boot
sudo ./xstage tiny image           # sd.img: MBR, FAT32 boot + ext4 rootfs + sshd
./xstage tiny run-rpi              # qemu -M raspi4b boot gate (output-only)
sudo ./xstage tiny sd /dev/sdX     # dd to a real card, then boot the Pi 400
ssh root@192.168.0.200             # over the wired LAN — works with a dark HDMI
```

- **Boot chain (BCM2711)**: the EEPROM bootloader (no `bootcode.bin` on the card)
  loads `start4.elf`+`fixup4.dat` from an **MBR FAT32 partition 1** (GPT won't
  boot), which reads `config.txt` ([`rpi/config.txt`](rpi/config.txt):
  `arm_64bit=1`, `kernel=kernel8.img`, `enable_uart=1`), auto-picks the board's
  DTB (`bcm2711-rpi-400.dtb` on the Pi 400) and starts the ARM cores on
  `kernel8.img` with [`rpi/cmdline.txt.in`](rpi/cmdline.txt.in) as the command
  line. No U-Boot needed — though mainline U-Boot's `rpi_arm64_defconfig`
  officially covers the Pi 400 if chain-loading is ever wanted
  ([docs](https://docs.u-boot.org/en/latest/board/broadcom/raspberrypi.html)).
- **The payload is a Gentoo package**: `tiny rpi` cross-emerges
  `sys-kernel/raspberrypi-image` (pulls `sys-boot/raspberrypi-firmware`) into
  the rootfs — prebuilt `kernel8.img`, GPU blobs, every Pi DTB, `overlays/` and
  the matching `/lib/modules`, all portage-tracked in the sysroot VDB. Keyword
  and license accepts are installed from [`tiny.portage/`](tiny.portage/) as
  `…/xstage-tiny` files (the blobs are `raspberrypi-videocore-bin` licensed).
- **One image, both worlds**: `tiny image` renders
  `root=PARTUUID=<mbr-disk-id>-02` into `cmdline.txt`. The MBR disk id survives
  `dd`, so the same `sd.img` finds its root as `mmcblk1` in qemu and `mmcblk0`
  on the Pi without editing anything. Image size stays a power of 2 (default
  2048 MiB) because qemu's SD emulation rejects other sizes; on a bigger card,
  grow partition 2 afterwards (`parted resizepart 2 100%` + `resize2fs`).
- **Headless debug console**: `tiny image` reuses the Zero 2 W ssh machinery —
  it cross-emerges `sys-apps/kmod`, `sys-apps/iproute2` and `net-misc/openssh`
  into the rootfs and writes a Pi 400 `/etc/tiny-board.sh`: eth0 gets a fixed
  LAN address (`XSTAGE_PI400_IP`, default `192.168.0.200/24`, gateway
  `XSTAGE_PI400_GW` = `192.168.0.1`) and sshd starts with root login (password
  `XSTAGE_ZERO_PASS`, default `tiny`, plus the invoker's `id_ed25519.pub`; host
  keys are generated on the board at first boot). The board is reachable over
  the cable even when HDMI shows nothing — first stop for display debugging:
  `ssh root@192.168.0.200 'dmesg | grep -iE "hdmi|vc4|drm|fb"'`. bcmgenet is
  built into the Pi kernel, so no module dance is needed; under `tiny run`
  (`-M virt`) the same hook detects the virtio NIC and falls back to qemu's
  user-net defaults, so sshd is testable with `ssh -p 2223 root@127.0.0.1`.
  `rpi/config.txt` also sets `hdmi_force_hotplug=1` so the firmware emits HDMI
  even when display detection fails at power-on.
- **qemu raspi4b caveats** (verified here): qemu doesn't emulate the VideoCore
  firmware, so the kernel is always passed with `-kernel` and the SD image only
  provides the root device; the PL011 console enumerates as **ttyAMA1** (DTB
  alias `serial1` = uart0); and the guest receives **no input at all** — serial
  RX and USB are both dead ([qemu #2969](https://gitlab.com/qemu-project/qemu/-/issues/2969);
  the 4B's USB controller sits on unemulated PCIe). `run-rpi` is therefore a
  boot *gate*: it proves kernel + PARTUUID root + `/init` reach the bash banner
  (3.1 s guest time). Interactive tiny work stays on `tiny run` (`-M virt`);
  interactive Pi work happens on the real Pi 400 (HDMI + built-in keyboard,
  or serial0 on GPIO 14/15).

## Booting the Pi Zero 2 W with a Waveshare 2.13" V4 e-Paper HAT

```
sudo ./xstage tiny rpi             # same payload as above (all DTBs included)
sudo ./xstage tiny image_zero      # sd.img: panel driver + sshd + usb0 net
./xstage tiny run-rpi              # qemu -M raspi3b boot gate (output-only)
sudo ./xstage tiny sd /dev/mmcblk0 # dd to the card, then boot the Zero 2 W
ssh root@10.0.0.2                  # over the USB cable (host = 10.0.0.1/24)
```

`image_zero` is the Pi 400 image builder with three board-specific twists:

- **Different boot chain, same files.** The Zero 2 W's BCM2710A1 (an RP3A0
  package around the BCM2837 die) has no boot EEPROM: its ROM loads
  `bootcode.bin`, then `start.elf` + `fixup.dat` — *not* the `start4.*` pair the
  Pi 4/400 uses. `sys-kernel/raspberrypi-image` ships both sets, so only
  `config.txt` changes: [`rpi/config-zero2w.txt`](rpi/config-zero2w.txt) is
  written onto the FAT partition instead of the Pi 400 one. It adds
  `dtparam=spi=on` (the HAT) and `dtoverlay=disable-bt`, which hands the PL011
  back to GPIO 14/15 so `serial0` is `ttyAMA0` at a fixed baud rate rather than
  the mini-UART, whose clock follows the core clock. The firmware auto-selects
  `bcm2710-rpi-zero-2-w.dtb`.
- **The panel driver is part of the rootfs.**
  [`rpi/eink213v4.c`](rpi/eink213v4.c) is a ~400-line C program that talks to
  the SSD1680 over `/dev/spidev0.0` and drives RST/DC/PWR/BUSY through the
  **gpiochip v2 UAPI** — no Python, no libgpiod, no BCM2835 library, which is
  what makes it fit a rootfs that has no package manager. `image_zero`
  cross-compiles it to `/usr/bin/eink213` (24 KB) and cross-emerges
  `sys-apps/kmod`, because the Pi kernel ships SPI as xz-compressed modules and
  nothing here runs udev — `/init` therefore does `modprobe spi-bcm2835 spidev`
  itself before writing the boot banner to the panel.
  Text is drawn with the kernel's own VGA 8x16 console font, extracted from
  `../src/linux-stable_20231123/lib/fonts/font_8x16.c` by
  [`rpi/mkfont.sh`](rpi/mkfont.sh) into a generated `rpi/font8x16.h`
  (31 columns x 7 rows in landscape, `-2` doubles the size).
  `eink213 -o out.pbm` renders a frame **to a file instead of the panel**, so
  the layout can be checked on the host with no hardware attached — that is how
  the rotation maths (landscape 250x122 → the panel's native portrait RAM) was
  verified here.
- **A test workflow, not just a boot**: `image_zero` also installs
  `sys-apps/iproute2` + `net-misc/openssh` (USE `-pam`: there is no login stack
  here, so sshd reads `/etc/shadow` directly) and generates
  `/etc/tiny-board.sh`, the board hook `/init` runs. It loads `g_ether` —
  `dwc2` is built into the Pi kernel and switched to peripheral mode by
  `dtoverlay=dwc2` — then configures **usb0 = 10.0.0.2/24** with the machine at
  the other end of the cable as the gateway (10.0.0.1), starts sshd and shows
  the ssh address on the panel. Fixed locally-administered MACs
  (`dev_addr`/`host_addr`) keep the host-side interface name stable across
  boots. Root logs in by password (`XSTAGE_ZERO_PASS`, default `tiny`) and by
  key (the invoking user's `id_ed25519.pub`, or `XSTAGE_ZERO_KEY`); **ssh host
  keys are generated on the board at first boot**, so the image itself carries
  no secrets — which is also why `run-rpi` boots with `-snapshot`, keeping
  guest writes out of `sd.img`.
  On the host side: give the `enx…` interface `10.0.0.1/24` and plug the cable
  into the Zero's **USB** port, not PWR IN.
- **Stock HAT wiring.** The BCM pin numbers (RST 17, DC 25, CS 8/CE0,
  BUSY 24, PWR 18), the 250x122 geometry and the SSD1680 command sequence
  match Waveshare's `epd2in13_V4` reference driver, so any 2.13" V4 HAT works
  as shipped. If the image comes out upside down for a given HAT orientation,
  `eink213 -r` flips it.

The qemu gate uses **`-M raspi3b`** (BCM2837 — literally the Zero 2 W's die;
qemu models no Zero 2 W) and is subject to the same input limitation as
`raspi4b`: verified here with both `-nographic` and `-serial stdio`, keystrokes
never reach the guest, so it proves boot only (SD → `mmcblk0p2` by PARTUUID →
`/init` → sshd → bash banner). SPI and the USB gadget are not emulated, so the
panel and `usb0` need the real board.

**sshd is testable without hardware**, though: the board hook falls back to
`eth0` with qemu's user-net defaults (10.0.2.15/24 via 10.0.2.2), and
`tiny run` (`-M virt`) attaches a virtio NIC forwarded to
`127.0.0.1:2223`. So after `tiny image_zero`:

```
sudo ./xstage tiny pack            # repack the initrd with the new rootfs
./xstage tiny run                  # terminal A
ssh -p 2223 root@127.0.0.1         # terminal B — key or password login
```

Verified here end to end: key auth, password auth and PTY allocation
(`/dev/pts/0`, which is why `/init` mounts `devpts` — without it every login
dies with "PTY allocation request failed"). Note `tiny run` needs `-m 2048`
now: an initramfs is unpacked into tmpfs, and a rootfs carrying the Pi module
tree plus openssh panics a 1 GB guest with "Unable to mount root fs".

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
| `../build/tinyroot/{sd.img,ptuuid,board}` | SD image, its MBR disk id, and which board it was built for |
| `rpi/font8x16.h` | generated by `rpi/mkfont.sh` from the kernel tree (not committed) |

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
- **own Pi kernel**: the raspberrypi/linux tree is already unpacked at
  `../src/linux-stable_20231123/` with `bcm2711_defconfig` and
  `bcm2711-rpi-400.dts` — an xlab-style `kmake` build would replace the
  prebuilt `raspberrypi-image` kernel (firmware blobs still come from the
  ebuild).
- **U-Boot chain-load**: cross-build mainline `rpi_arm64_defconfig`
  (officially supports the Pi 400), `config.txt: kernel=u-boot.bin`.
- **networked tiny**: add `sys-firmware/raspberrypi-wifi-ucode` +
  `linux-firmware[savedconfig]` for the Pi 400's brcmfmac43455 WiFi (the
  Zero 2 W's brcmfmac43436 comes from the same package) — the e-Paper banner
  would then have an IP address to show.
- **e-Paper on hardware**: `eink213` is verified by construction (offline PBM
  render + a clean cross build) but has never driven a physical panel; the
  first run on the Zero 2 W should be `eink213 -t` (test pattern), then `-r` if
  the orientation is wrong. A partial-refresh mode (SSD1680 command `0x22`
  with `0xff`/LUT reload) would make a status ticker practical.
