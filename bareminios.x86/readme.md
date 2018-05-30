# Interesting minimal OS
### It was forked from site https://github.com/kugwa/myos
### Thus, all kudos go there

```
make
cp build/myos.elf iso/root/boot/
cd iso
./mkiso
qemu-system-i386 -cdrom myos.iso
```
