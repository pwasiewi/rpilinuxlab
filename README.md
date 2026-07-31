# Some laboratory scripts to run in Gentoo linux

## xlab — unified QEMU kernel lab

`./xlab` is a single data-driven script that supersedes the per-directory
`make.*` Makefiles (whose recipes were ~95% identical): it cross-compiles a
kernel, pairs it with a static busybox initrd — or, for the `gentoo` target,
with a real arm64 Gentoo stage3 on an ext4 virtio disk — and boots it in
qemu. Downloads are cached in shared `dl/` (legacy `make.*/dl` tarballs are
reused via symlinks), sources unpack once into shared `src/`, and each
target builds in `build/<target>/`.

```
./xlab targets                # aarch64 (RPi3) | armhfp (RPi2) | arm | x86_64 | gentoo
./xlab status                 # toolchain / kernel / rootfs per target
./xlab aarch64 run            # builds kernel+busybox+initrd if missing, boots raspi3b
./xlab gentoo kernel          # rpi kernel, arm64 defconfig + virtio built-in
./xlab gentoo stage3          # latest arm64 stage3 + sha256 verify
sudo ./xlab gentoo image      # 8G ext4 image: stage3, modules, serial autologin
./xlab gentoo run             # -M virt, serial on stdio, ssh -> localhost:2222
sudo ./xlab gentoo mount      # image on build/gentoo/mnt (manual tweaks)
sudo ./xlab gentoo chroot     # qemu-user chroot via xarm, binpkgs bound inside
```

xarm cooperation — cross-compile on the host, install into the image:
```
sudo xarm emerge -av app-editors/nano                            # binpkg in sysroot
sudo ./xlab gentoo chroot "emerge -av --usepkg app-editors/nano" # offline install
# or into the RUNNING VM: 'sudo xarm binhost' on the host, then in the guest
# 'emerge --getbinpkg --usepkg nano' (binrepos.conf -> 10.0.2.2:8686 preinstalled)
```

The gentoo image is a lab config (root autologin, empty password) — keep it
on qemu user-mode networking. Cross toolchains come from crossdev;
`./xlab <target> kernel` prints the exact `crossdev` command when one is
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

Full lab results and rationale: **[crosscompile_README.md](crosscompile_README.md)**
— 2026-07 census: **190/190 packages cross-compile natively** (incl.
gcc/glibc/perl), 0 chroot fallbacks, 69 min for @world; chroot is ~19×
slower and warm ccache cuts another ~27%. Details of the setup steps,
gotchas and speed levers live in [`crosscompile/`](crosscompile/)
(`manual-setup.md`, `xarm-setup.md`, `optimizations.md`).

## Legacy per-directory Makefiles

The original labs still work standalone:
```
cd make.armhfp 
make emulate #raspberry 2b

cd make.aarch64
make emulate #raspberry 3b

cd make.arm
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

# Legacy AndroidModLab
### Własne kompilacje androida i jego kernela 
Aby zainstalować skompilowany kernel i system najpierw trzeba umieć zrootować telefon i zainstalować TWRP- uwaga ryzykowna operacja - uzywać metod i plików sprawdzonych najlepiej na forum xda <https://forum.xda-developers.com> lub android polska ma odnośniki do xda i komentarze <https://forum.android.com.pl/>.

Dodano katalogi z przepisami na kompilacje androida i kerneli.
 - https://github.com/pwasiewi/rpilinuxlab/tree/master/androidoreo
 - https://github.com/pwasiewi/rpilinuxlab/tree/master/androidnougat
 - https://github.com/pwasiewi/rpilinuxlab/tree/master/androidkernel

### Inne tutoriale
 - https://forum.xda-developers.com/android/general/guide-how-to-build-custom-roms-kernel-t3814251
 - https://thealaskalinuxuser.wordpress.com/2018/08/03/video-tutorial-for-android-building-advanced-topics/


# Legacy Raspberry Pi Lab 
## i nie tylko ;) https://wiki.gentoo.org/wiki/Embedded_systems/ARM_hardware_list
#### Odnośniki 
- https://wiki.gentoo.org/wiki/Embedded_Handbook/General/Creating_a_cross-compiler
- https://wiki.gentoo.org/wiki/User:Jens3/Installing_Gentoo_on_a_Raspberry_Pi_400
- https://github.com/pwasiewi/eulinks/tree/master/sw_raspberry

1. install Gentoo Linux e.g. from UbuntuLiveDVD https://github.com/pwasiewi/gentools
2. pull from github: git clone https://github.com/pwasiewi/rpilinuxlab
3. cd rpilinuxlab
4. mkdir dl
5. cd make... np. make.armhfp jest dla raspberrypi2/3 32bit
6. make emulate

Raspberry Pi Lab przygotowane na podstawie 
1) https://wiki.gentoo.org/wiki/Cross_build_environment
2) http://mgalgs.github.io/2015/05/16/how-to-build-a-custom-linux-kernel-for-qemu-2015-edition.html
3) środowiska Pawła Kraszewskiego z fragmentami z jego README
