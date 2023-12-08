# Some laboratory scripts to run in Gentoo linux
For example you can emulate with crossdev and qemu arm linux and raspberry kernels with busybox as init:
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

# AndroidModLab
### Własne kompilacje androida i jego kernela 
Aby zainstalować skompilowany kernel i system najpierw trzeba umieć zrootować telefon i zainstalować TWRP- uwaga ryzykowna operacja - uzywać metod i plików sprawdzonych najlepiej na forum xda <https://forum.xda-developers.com> lub android polska ma odnośniki do xda i komentarze <https://forum.android.com.pl/>.

Dodano katalogi z przepisami na kompilacje androida i kerneli.
 - https://github.com/pwasiewi/rpilinuxlab/tree/master/androidoreo
 - https://github.com/pwasiewi/rpilinuxlab/tree/master/androidnougat
 - https://github.com/pwasiewi/rpilinuxlab/tree/master/androidkernel

### Inne tutoriale
 - https://forum.xda-developers.com/android/general/guide-how-to-build-custom-roms-kernel-t3814251
 - https://thealaskalinuxuser.wordpress.com/2018/08/03/video-tutorial-for-android-building-advanced-topics/


# Raspberry Pi Lab 
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

Przygotowanie środowiska programistycznego do procesorów ARM po system Gentoo
"na piechotę":

Ścieżki w plikach .config przeznaczone są dla tego opisu poniżej. Dla przepisu
w "Makefile" trzeba je poprawić.

1. Instalacja pakietu CROSSDEV

----------------------------------------------------------------------------
```
emerge -av crossdev
```
----------------------------------------------------------------------------

2. Generacja narzędzi dla platformy ARM
```
crossdev --target arm-softfloat-linux-gnueabi --stable  --gcc 7.3.0-r1 --libc 2.25-r11 --kernel 4.16.9 -oO /usr/portage
```
----------------------------------------------------------------------------

3. Skrypt "armmake" wywołuje "make" z ustawieniem parametrów do kross-kompilacji
   narzędziami z p. 2

----------------------------------------------------------------------------
```
#!/bin/bash
export ARCH=arm
export CROSS_COMPILE=arm-softfloat-linux-gnueabi-
make $@
```
----------------------------------------------------------------------------

4. Ściągamy i rozpakowujemy źródła kernela i busybox do podkatalogu src

----------------------------------------------------------------------------
```
mkdir -p src bin.kernel bin.busybox out.initrd emulacja
wget http://www.kernel.org/pub/linux/kernel/v4.0/linux-4.16.7.tar.xz
wget http://busybox.net/downloads/busybox-1.28.3.tar.bz2
tar xjf linux-4.16.7.tar.xz -C src
tar xjf busybox-1.28.3.tar.bz2 -C src
```
----------------------------------------------------------------------------

5. Konfigurujemy kernel

----------------------------------------------------------------------------
```
cd src/linux-4.16.7
../../armmake O=../../bin.kernel menuconfig
cd ../..
```
----------------------------------------------------------------------------

6. Kompilujemy kernel

----------------------------------------------------------------------------
```
cd bin.kernel
../armmake all
cd ..
```
----------------------------------------------------------------------------

6. Konfigurujemy busybox

----------------------------------------------------------------------------
```
cd src/busybox-1.28.3
../../armmake O=../../bin.busybox menuconfig
cd ../..
```
----------------------------------------------------------------------------

7. Kompilujemy busybox

----------------------------------------------------------------------------
```
cd bin.busybox
../armmake
../armmake install
cd ..
```
----------------------------------------------------------------------------

8. Dopieszczamy INITRD

9. Generujemy obraz INITRD

----------------------------------------------------------------------------
```
cd out.initrd
find . | cpio --quiet -H newc -o --owner=0.0 > ../emulacja/initrd
cd ..
```
----------------------------------------------------------------------------

10. Linkujemy obraz jądra

----------------------------------------------------------------------------
```
ln -s ../bin.kernel/arch/arm/boot/zImage emulacja/vmlinuz
```
----------------------------------------------------------------------------

11. Odpalamy emulator

----------------------------------------------------------------------------
```
qemu-system-arm -M versatilepb -m 256 -kernel emulacja/vmlinuz -initrd emulacja/initrd -append "init=/init" -serial=stdio
```
----------------------------------------------------------------------------

12. Najlepiej jednak skorzystać z załączonych Makefile'ów dla x86_64, armsoft i raspberry2 armvh7
```
make emulate
```
i to by było na tyle!

# Inne crossdev generowane crosscompilatory
## https://wiki.gentoo.org/wiki/Embedded_systems/ARM_hardware_list

The BeagleBone Black was needed:
```
    crossdev -v -S -t armv7-none-linux-gnueabi --env
    'EXTRA_ECONF="--with-arch=armv7-a
    --with-fpu=vfpv3-d16
    --with-float-abi=hard
    libc_cv_forced_unwind=yes
    libc_cv_ctors_header=yes
    libc_cv_c_cleanup=yes"'
```
For musl rpi3 (do not work!):
```
    crossdev --target armv7a-hardfloat-linux-musleabi  --stable  --gcc 7.3.0-r3  --kernel 4.16.12 -oO /usr/portage --env 'EXTRA_ECONF="--with-arch=armv7-a --with-fpu=neon-vfpv4 --with-float-abi=hard"'
```

