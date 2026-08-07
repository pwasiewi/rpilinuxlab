# Some laboratory scripts to run in Gentoo linux

## xlab — unified QEMU kernel lab

`./xlab` is a single data-driven script that supersedes the per-directory
`make.*` Makefiles (whose recipes were ~95% identical): it cross-compiles a
kernel, pairs it with a static busybox initrd — or, for the `gentoo` target,
with a real arm64 Gentoo stage3 on an ext4 virtio disk — and boots it in
qemu. Downloads are cached in shared `dl/` (legacy `make.*/dl` tarballs are
reused via symlinks), sources unpack once into shared `src/`, and each
target builds in `build/<target>/`.

> **Storage note (2026-08-07):** `build/` and `dl/` live on the data HDD at
> `/mnt/db5/rpilinuxlab/{build,dl}` — ~15 GB of regenerable/re-downloadable
> artifacts (next to genstage/android/openwrt), keeping them out of the
> home-SSD backups. The scripts find them through `XP_BUILD_DIR`/`XP_DL_DIR`
> in `/etc/xp.conf` (exported by `xp`; xstage/xlab source the file themselves
> when run directly). Unset, they fall back to `build/` and `dl/` in the repo
> root — no in-repo symlinks needed either way. Builds are CPU-bound (qemu
> emulation), so the HDD costs nothing measurable.

```
./xlab targets                # aarch64 (RPi3) | armhfp (RPi2) | arm | x86_64 | gentoo
                              #   (xp profiles: rpi3/zero2w -> aarch64,
                              #    rpi400 -> gentoo, amd64 -> x86_64)
./xlab status                 # toolchain / kernel / rootfs per target
                              #   (xp <profile> status)
./xlab aarch64 run            # builds kernel+busybox+initrd if missing, boots raspi3b
                              #   (xp rpi3 run)
./xlab gentoo kernel          # rpi kernel, arm64 defconfig + virtio built-in
                              #   (xp rpi400 kernel)
./xlab gentoo stage3          # latest arm64 stage3 + sha256 verify
                              #   (xp rpi400 xlab gentoo stage3)
sudo ./xlab gentoo image      # 8G ext4 image: stage3, modules, serial autologin
                              #   (sudo xp rpi400 xlab gentoo image -- NOT
                              #    'xp rpi400 image': that builds the board
                              #    sd.img via xstage)
./xlab gentoo run             # -M virt, serial on stdio, ssh -> localhost:2222
                              #   (xp rpi400 run)
sudo ./xlab gentoo mount      # image on build/gentoo/mnt (manual tweaks)
                              #   (sudo xp rpi400 xlab gentoo mount)
sudo ./xlab gentoo chroot     # qemu-user chroot via xarm, binpkgs bound inside
                              #   (sudo xp rpi400 xlab gentoo chroot)
```

xarm cooperation — cross-compile on the host, install into the image:
```
sudo xarm emerge -av app-editors/nano                            # binpkg in sysroot
sudo ./xlab gentoo chroot "emerge -av --usepkg app-editors/nano" # offline install
#   (sudo xp rpi400 xlab gentoo chroot "emerge -av --usepkg app-editors/nano")
# or into the RUNNING VM: 'sudo xarm binhost' on the host, then in the guest
# 'emerge --getbinpkg --usepkg nano' (binrepos.conf -> 10.0.2.2:8686 preinstalled)
```

The gentoo image is a lab config (root autologin, empty password) — keep it
on qemu user-mode networking. Cross toolchains come from crossdev;
`./xlab <target> kernel` (`xp <profile> kernel`) prints the exact `crossdev` command when one is
missing, and for aarch64 the whole setup is `sudo xarm setup` (below).

## xarm — aarch64 cross-compile manager

`./xarm` is a snapshot of the canonical copy in `~/Claude/bin/xarm`
(mirrored to `/usr/local/bin/xarm`): crossdev toolchain + sysroot
cross-emerge + QEMU user-mode chroot fallback + package-by-package build
loop + binhost + distcc offload, targeting the Raspberry Pi 400/4
(cortex-a72).

```
sudo xarm setup               # crossdev toolchain, sysroot, profile, binfmt
sudo xarm emerge -av nano     # cross-emerge into the sysroot (builds binpkgs)
sudo xarm 1by1 -e @world      # per-package loop: cross first, qemu chroot fallback
sudo xarm binhost             # serve binpkgs over HTTP for the Pi / xlab VM
xarm status
```

Full lab results and rationale: **[crosscompile/README.md](crosscompile/README.md)**
— 2026-07 census: **190/190 packages cross-compile natively** (incl.
gcc/glibc/perl), 0 chroot fallbacks, 69 min for @world; chroot is ~19×
slower and warm ccache cuts another ~27%. Details of the setup steps,
gotchas and speed levers live in [`crosscompile/`](crosscompile/)
(`manual-setup.md`, `xarm-setup.md`, `optimizations.md`).

## genstage — Gentoo stage bootstrapping + tiny rootfs (xstage)

[`genstage/xstage`](genstage/xstage) rebuilds Gentoo's own release artifacts
and the Buildroot idea, side by side: the **amd64** track drives catalyst
through the official `stage1 -> stage3` bootstrap (seed stage3 + tree
snapshot + releng spec files; `stage2`/`bootstrap.sh` kept as an explicit
educational step), and the **tiny** track cross-emerges a minimal rootfs
**into a directory** via the xarm sysroot (`--root=`, no portage on the
target — updates = regenerate on the host; base userland = real Gentoo
packages by default, `XSTAGE_TINY_BASE=busybox` for the static-busybox
variant), packs it as squashfs + cpio initrd and boots it with xlab's arm64
kernel. Heavy data on
`/mnt/db5/genstage` (`XSTAGE_DIR`).

```
sudo genstage/xstage amd64 setup && genstage/xstage amd64 seed
sudo genstage/xstage amd64 all       # snapshot -> spec -> stage1 -> stage3
sudo genstage/xstage amd64 verify    # chroot smoke test of the built stage3
sudo genstage/xstage tiny build && sudo genstage/xstage tiny pack
genstage/xstage tiny run             # qemu -M virt -> bash shell
sudo genstage/xstage tiny rpi        # + kernel8.img/firmware/DTBs (all Pis)
sudo genstage/xstage tiny image      # sd.img for the Pi 400: FAT32 + ext4
sudo genstage/xstage tiny image_zero # ...or for a Pi Zero 2 W: eink213 driver
                                     # for the Waveshare 2.13" V4, plus sshd
                                     # on a USB-gadget link (ssh root@10.0.0.2)
genstage/xstage tiny run-rpi         # qemu raspi4b/raspi3b gate (output-only)
sudo genstage/xstage tiny sd /dev/sdX  # dd to a card -> boot the real board
```

Background, stage semantics and the Buildroot mapping:
**[genstage/readme.md](genstage/readme.md)**.

## xp — one profile switch for the whole lab

[`xp`](xp) coordinates the three scripts above through board profiles in
[`profiles/`](profiles/): a profile fixes the tuple, CPU tuning, board
(config.txt/DTB/qemu machine), network address and installation method, and
`xp` routes tool-agnostic verbs to the right script with the right env
(`XPROFILE=<name>` also works per-tab, and directly on `xarm`/`xstage`/`xlab`).
Precedence: explicit env var > profile > script default. Machine-local root
pointer for the `/usr/local/bin` copy: `/etc/xp.conf` (`XP_LAB_DIR=...`).

```
xp profiles                      # rpi400, rpi3, zero2w, amd64
export XPROFILE=rpi3             # per-tab active profile
sudo xp setup                    # xarm toolchain + xstage catalyst dirs
sudo xp build                    # rootfs: stage3 unpack (arm64) / tiny build
sudo xp rpi && sudo xp image     # Pi payload + board sd.img (192.168.0.201)
xp gate                          # qemu boot gate (raspi3b for the Pi 3)
sudo xp sd /dev/sdX              # dd to the card
sudo xp rpi400 enter             # aarch64 shell in the Pi 400 rootfs (qemu-user)
sudo xp rpi400 stage1            # catalyst under qemu; distccd auto-starts
sudo xp rpi400 log               # watch it (also: log emerge, qlop)
```

Variant profiles: copy a conf, set `PROF_BUILD_SUBDIR` (own build tree,
shared sysroot + binpkgs) and optionally `PROF_PKGS` (`xp <p> pkgs`). All ARM
profiles share one sysroot: the managed make.conf block uses
`-march=armv8-a -mtune=<cpu>` (`xarm tune` switches it), so binaries run on
every ARMv8 board. Details: **[profiles/README.md](profiles/README.md)**.

## Verified walkthrough — every command, in order (2026-07-31)

The exact sequence below was run end-to-end on Gentoo (gcc 15.3, QEMU 10.2)
and every step passed; all gcc-15 / QEMU-10 / portage-signature fixes are
already inside `xlab`, so no manual patching is needed.

### 0. One-time prerequisites

```bash
# qemu with the system emulators (QEMU_SOFTMMU_TARGETS: arm aarch64 x86_64)
# and USE=static-user for the qemu-user chroot
sudo emerge -av app-emulation/qemu

# aarch64: toolchain + sysroot + binfmt in one shot (RPi3 / RPi 400 / gentoo VM)
sudo xarm setup

# the two remaining cross targets
sudo crossdev -S --target armv7a-hardfloat-linux-gnueabi   # RPi2, 32-bit hardfloat
sudo crossdev -S --target arm-softfloat-linux-gnueabi      # ARM926 versatile

git clone https://github.com/pwasiewi/rpilinuxlab && cd rpilinuxlab
./xlab status              # every row should say tc:ok
                           #   (xp <profile> status)
```

### 1. Bare-metal RPi2 kernel (no Linux, ~50 lines)

```bash
cd barebone.raspi2
armv7a-hardfloat-linux-gnueabi-gcc -mcpu=cortex-a7 -fpic -ffreestanding -c boot.S -o boot.o
armv7a-hardfloat-linux-gnueabi-gcc -mcpu=cortex-a7 -fpic -ffreestanding -std=gnu99 -c kernel.c -o kernel.o -O2 -Wall -Wextra
armv7a-hardfloat-linux-gnueabi-gcc -T linker.ld -o myos.elf -ffreestanding -O2 -nostdlib boot.o kernel.o
armv7a-hardfloat-linux-gnueabi-objcopy myos.elf -O binary myos.bin
qemu-system-arm -M raspi2b -kernel myos.elf -serial stdio     # prints "Hello, kernel World!", echoes keys
cd ..
```

### 2. Linux + busybox initrd, all four targets

Each `run` fetches, builds and boots whatever is missing
(kernel → static busybox → cpio initrd → qemu). Quit qemu with `Ctrl-A X`.

```bash
./xlab x86_64  run         # mainline 6.6.147, KVM + -cpu host, boots in <1 s
                           #   (xp amd64 run)
./xlab armhfp  run         # rpi 6.1 kernel, -M raspi2b, console ttyAMA0
                           #   (no xp profile -- RPi2 is xlab-only)
./xlab aarch64 run         # rpi 6.1 kernel, -M raspi3b, console ttyAMA1 (PL011 quirk)
                           #   (xp rpi3 run)
./xlab arm     run         # mainline 6.6.147, -M versatileab, armv5tejl
                           #   (no xp profile)
```

Headless/scripted variant (how the boots were verified — pipe commands in,
grab the serial log):

```bash
(sleep 25; printf 'uname -a\n'; sleep 5) | timeout 60 \
    qemu-system-arm -M raspi2b -cpu cortex-a7 -serial stdio -display none \
    -kernel build/armhfp/emu/vmlinuz -initrd build/armhfp/emu/initrd \
    -dtb build/armhfp/emu/dtb -append "console=ttyAMA0 init=/init"
```

### 3. Real Gentoo arm64 VM (stage3 on a virtio disk)

```bash
./xlab gentoo kernel       # arm64 defconfig + virtio/PL011/ext4 built-in, Image + modules
                           #   (xp rpi400 kernel)
./xlab gentoo stage3       # latest arm64 openrc stage3, sha256-verified
                           #   (xp rpi400 xlab gentoo stage3)
sudo ./xlab gentoo image   # 8G ext4: stage3 + modules + autologin + gentoo tree copy
                           #   (sudo xp rpi400 xlab gentoo image)
./xlab gentoo run          # -M virt: root autologins on serial; leave with: poweroff
                           #   (xp rpi400 run)
```

### 4. Cross-built binpkgs → offline install into the image

```bash
sudo xarm emerge -av media-libs/libjpeg-turbo                    # binpkg lands in the sysroot
sudo ./xlab gentoo chroot "emerge -1vK media-libs/libjpeg-turbo" # installs it, no network
#   (sudo xp rpi400 xlab gentoo chroot "emerge -1vK media-libs/libjpeg-turbo")
```

### 5. Binhost → install into the RUNNING VM

```bash
xarm binhost                                   # terminal A: serves sysroot binpkgs on :8686
curl -s http://127.0.0.1:8686/Packages | head  # sanity: index answers
./xlab gentoo run                              # terminal B (xp rpi400 run),
                                               # then INSIDE the guest:
  emerge -1vKg media-libs/libjpeg-turbo        #   fetches from 10.0.2.2:8686, installs
  poweroff
```

### 6. Health checks / troubleshooting (used during verification)

```bash
./xlab status                                  # what is built per target
                                               #   (xp <profile> status)
sudo e2fsck -fp build/gentoo/emu/gentoo.img    # image integrity (must be unmounted!)
losetup -j build/gentoo/emu/gentoo.img         # MUST be empty — a leftover loop means
                                               # a live ext4 is still writing: corruption

# a previous VM still holding the image / port 2222:
ss -tlnp | grep 2222                           # find the qemu pid, then: kill <pid>

# a stale loop pinned inside sandboxed systemd services (mounts under /home
# propagate into their namespaces; xlab now mounts private to prevent this):
sudo grep -l loop0 /proc/*/mountinfo           # who holds it
sudo nsenter -t <PID> -m umount -l /dev/loop0  # release per holder (repeat; or reboot)

# worst case — image corrupted: rebuild it, everything is scripted anyway
sudo ./xlab gentoo image                       # (sudo xp rpi400 xlab gentoo image)
```

## Legacy per-directory Makefiles

The original labs (moved to `legacy/`) still work standalone:
```
cd legacy/make.armhfp 
make emulate #raspberry 2b

cd legacy/make.aarch64
make emulate #raspberry 3b

cd legacy/make.arm
make emulate #arm linux kernel
```

To create cross-compiling env install qemu then:
```
crossdev -S --target aarch64-unknown-linux-gnu -oO /usr/portage
systemctl restart systemd-binfmt

aarch64-unknown-linux-gnu-gcc -static -o test64 test.c
./test64
file ./test64
# ./test64: ELF 64-bit LSB executable, ARM aarch64, version 1 (SYSV), statically linked, for GNU/Linux 3.7.0, with debug_info, not stripped
aarch64-unknown-linux-gnu-gcc -o test64dyn test.c
qemu-aarch64 -L /usr/aarch64-unknown-linux-gnu/ ./test64dyn
file ./test64dyn
# ./test64dyn: ELF 64-bit LSB pie executable, ARM aarch64, version 1 (SYSV), dynamically linked, interpreter /lib/ld-linux-aarch64.so.1, for GNU/Linux 3.7.0, not stripped
```

# OpenWrt lab (Cudy TR3000 v1)

OpenWrt 25.12 sysupgrade images for the Cudy TR3000 v1 travel router
(MT7981/Filogic): recipe in [openwrt/](openwrt/readme.md), scripted by
`xowrt` (ImageBuilder route + optional full-source build, data on
`/mnt/db5/openwrt`). Successor-in-spirit to `legacy/make.tomato/`.

# Legacy AndroidModLab
### Homemade Android and Android-kernel builds
To install a self-compiled kernel and system you first need to know how to root the phone and install a custom recovery (TWRP back then, Lineage recovery today) — a risky operation: use only methods and files proven on the XDA forum <https://forum.xda-developers.com>; the Polish Android forum links to XDA with commentary <https://forum.android.com.pl/>.

**2026 refresh:** current recipe for the latest Android (16 "Baklava") on a modern
phone (Pixel 9a `tegu`: LineageOS 23.2 / AxionOS / CalyxOS) lives in
[`android.baklava/`](android.baklava/readme.md).

Directories with recipes for building Android and its kernels:
 - [android.baklava](android.baklava/) — 2026, LineageOS 23.2 / Android 16, Pixel 9a
 - [legacy/android.q](legacy/android.q/) — LineageOS 17.1, LG G6
 - [legacy/android.oreo](legacy/android.oreo/) — ResurrectionRemix, LG G3
 - [legacy/android.nougat](legacy/android.nougat/) — CM-14.1
 - [legacy/android.kernel](legacy/android.kernel/) — kernel-only builds

### Other tutorials
 - https://forum.xda-developers.com/android/general/guide-how-to-build-custom-roms-kernel-t3814251
 - https://thealaskalinuxuser.wordpress.com/2018/08/03/video-tutorial-for-android-building-advanced-topics/


# Legacy Raspberry Pi Lab 
## and not only ;) https://wiki.gentoo.org/wiki/Embedded_systems/ARM_hardware_list
#### Links
- https://wiki.gentoo.org/wiki/Embedded_Handbook/General/Creating_a_cross-compiler
- https://wiki.gentoo.org/wiki/User:Jens3/Installing_Gentoo_on_a_Raspberry_Pi_400
- https://github.com/pwasiewi/eulinks/tree/master/sw_raspberry

1. install Gentoo Linux e.g. from UbuntuLiveDVD https://github.com/pwasiewi/gentools
2. pull from github: git clone https://github.com/pwasiewi/rpilinuxlab
3. cd rpilinuxlab
4. mkdir dl
5. cd legacy/make... e.g. legacy/make.armhfp is for the 32-bit Raspberry Pi 2/3
6. make emulate

The Raspberry Pi Lab was prepared based on 
1) https://wiki.gentoo.org/wiki/Cross_build_environment
2) http://mgalgs.github.io/2015/05/16/how-to-build-a-custom-linux-kernel-for-qemu-2015-edition.html
3) Paweł Kraszewski's environment, with fragments of its README
