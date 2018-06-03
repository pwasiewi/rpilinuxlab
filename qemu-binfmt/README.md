### Emulacja linuxa Gentoo arm poprzez binfmt z wykorzystaniem narzędzi gentools 
#### https://github.com/pwasiewi/gentools
#### Podstawowa konfiguracja gentoo arm
```
v r p     #zmienia na katalog z ustawieniami stage3/4 itp. lub bez mc uruchamia vim settings z tym katalogu
v r f
v r cross0
v r arm1
binfmt-run
v r arm2  #zmienia także /etc/portage hosta na swój arma (CZASAMI SIĘ PRZYDAJE)
```
#### Chrootowanie się na środowisko gentoo arm7, CTRL-D wyjście lub komenda: exit 
```
v r e     #można w qemu chroocie wykonywać komendy linuxa arm
```
#### Zmiana gcc na 7.3.0-r3 (sprawdź czy największa możliwa wersja gcc i popraw w /usr/local/bin/v)
```
v r arm3
```
#### Kompilacja xorg-server, openbox
```
v r arm4
```
#### Zmiana /etc/portage z arm na hosta z /etc/portage.host (po etapie v r arm2)
```
vcdx64
```
#### Zmiana /etc/portage z hosta na arm z /etc/portage.arm
```
vcdarm
```


### Krok po kroku emulacja linuxa Gentoo arm poprzez binfmt
#### https://wiki.gentoo.org/wiki/Embedded_Handbook/General/Compiling_with_qemu_user_chroot

#### Generujemy skrośny kompilator:
```
crossdev --target armv7a-hardfloat-linux-gnueabi  --stable  --gcc 7.3.0-r1 --libc 2.25-r11 --kernel 4.16.9 -oO /usr/portage
```

#### Do crosstoolsów w katalogu /usr/armv7a-hardfloat-linux-gnueabi rozpakowujemy podstawowe pakiety linuxa gentoo na platformę armv7a-hardfloat http://distfiles.gentoo.org/releases/arm/autobuilds/20161129/stage3-armv7a_hardfp-20161129.tar.bz2 usuwając poprzednią zawartość.

```
[ -e /etc/binfmt.d/binfmt.conf ] && rm /etc/binfmt.d/binfmt.conf
[ ! -e /etc/binfmt.d/qemu-arm-static.conf ] && echo ':arm:M::\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x28\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\x00\xff\xfe\xff\xff\xff:/usr/local/bin/qemu-wrapper:' > /etc/binfmt.d/qemu-arm-static.conf

#[ ! -e /etc/binfmt.d/qemu-aarch64-static.conf ] && echo ':aarch64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7:\xff\xff\xff\xff\xff\xff\xff\xfc\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff:/usr/local/bin/qemu-wrapper:' > /etc/binfmt.d/qemu-aarch64-static.conf

systemctl restart systemd-binfmt

cd /usr/armv7a-hardfloat-linux-gnueabi
[ ! -e usr/local/bin/qemu-wrapper ] && gcc -static /usr/local/bin/qemu-wrapper.c -O3 -s -o usr/local/bin/qemu-wrapper
cp /etc/resolv.conf etc/resolv.conf
quickpkg qemu --include-config y
ROOT=$PWD/ emerge --usepkgonly --oneshot --nodeps qemu 

for i in proc dev usr/local/portage var/tmp/packages_arm /var/tmp/packages_arm sys; do [ ! -e $i ] && mkdir -pv $i; done;
   
mountpoint -q proc && echo "proc mounted" || mount -t proc none proc
for i in dev usr/local/portage var/tmp/packages_arm sys tmp dev/pts; do mountpoint -q "$i" && echo "$i mounted" || mount --bind "/$i" "$i"; done
#mount -o bind /usr/src/raspberrypi-sources usr/src/linux
#mount -o bind /lib/modules lib/modules

if [ $# == 0 ]; then
   chroot . /bin/bash
else
   if [ -f "$1" ]; then
      chroot . "$1"
   else
      chroot . /bin/bash -c "$@"
   fi
fi

#komendy w chroot uruchomione
#emerge --sync
#eselect profile set 23


#umount lib/modules
#umount usr/src/linux
for i in dev/pts tmp sys var/tmp/packages_arm usr/local/portage dev proc; do 
   mountpoint -q "$i" && umount "$i"
done
```
