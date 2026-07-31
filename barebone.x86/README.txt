# http://wiki.osdev.org/Bare_Bones
# Verified 2026-07 with native multilib gcc 15 / binutils 2.46 / QEMU 10.2.
# A modern (PIE/SSP/SSE-by-default) compiler needs the freestanding opt-outs:
#   -fno-pie                        fixed-address kernel, no GOT
#   -fno-stack-protector            no __stack_chk_fail
#   -fno-asynchronous-unwind-tables no .eh_frame
#   -fcf-protection=none            no .note.gnu.property section
#   -mgeneral-regs-only             no SSE/MMX/x87 (gcc auto-vectorizes -O2
#                                   code into SSE, which #UDs before the
#                                   kernel enables it in CR0/CR4)

# Variant A — native multilib gcc (any amd64 Gentoo, no crossdev needed):
gcc -m32 -c boot.s -o boot.o
gcc -m32 -c kernel.c -o kernel.o -std=gnu99 -ffreestanding -fno-pie \
    -fno-stack-protector -fno-asynchronous-unwind-tables \
    -fcf-protection=none -mgeneral-regs-only -O2 -Wall -Wextra
gcc -m32 -T linker.ld -o myos.bin -ffreestanding -O2 -nostdlib -no-pie \
    -Wl,--build-id=none boot.o kernel.o -lgcc

# Variant B — dedicated bare-metal cross toolchain (the osdev-canonical way;
# the old i686-none-linux-gnueabi target was ARM-style naming and is gone):
#   crossdev --stable --target i686-elf --stage1
# then use i686-elf-gcc / i686-elf-as with the same flags (i686-elf-gcc
# defaults to no PIE/SSP, so only -mgeneral-regs-only really matters).

# Boot directly (QEMU loads multiboot ELFs itself):
qemu-system-i386 -kernel myos.bin

# Or a GRUB ISO — only needed for real hardware / testing GRUB itself;
# grub-mkrescue needs xorriso (Gentoo: emerge dev-libs/libisoburn):
mkdir -p isodir/boot/grub
cp myos.bin isodir/boot/myos.bin
cp grub.cfg isodir/boot/grub/grub.cfg
grub-mkrescue -o myos.iso isodir
qemu-system-i386 -cdrom myos.iso
