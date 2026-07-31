# Interesting minimal OS
### It was forked from site https://github.com/kugwa/myos
### Thus, all kudos go there

Requirements: `nasm`, multilib `gcc` (`-m32`), and for the ISO route
`grub-mkrescue` + `xorriso` (Gentoo: `dev-libs/libisoburn` — there is no
separate xorriso package; upstream is the libburnia project, not the dead
Distrotech GitHub mirror). Verified 2026-07 with
gcc 15 / binutils 2.46 / QEMU 10.2 — see the Makefile comments for the
flags a modern PIE/SSE-by-default compiler makes necessary
(`-fno-pie`, `-mgeneral-regs-only`, ...).

Quick run (no ISO needed — QEMU boots multiboot ELFs directly):
```
make
qemu-system-i386 -kernel build/myos.elf
```

Full GRUB ISO:
```
make
cp build/myos.elf iso/root/boot/
cd iso
./mkiso
qemu-system-i386 -cdrom myos.iso
```
