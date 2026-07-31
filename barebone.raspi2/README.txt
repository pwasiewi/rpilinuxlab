# http://wiki.osdev.org/Raspberry_Pi_Bare_Bones  (raspi2 variant)
# Toolchain: crossdev -S --target armv7a-hardfloat-linux-gnueabi
# The Pi 2 is a Cortex-A7 (ARMv7), so -mcpu=cortex-a7 — the old
# -mcpu=arm1176jzf-s was the Pi 1 CPU; peripherals sit at 0x3F000000
# (see kernel.c), and boot.S parks cores 1-3 (all 4 start at _start).

armv7a-hardfloat-linux-gnueabi-gcc -mcpu=cortex-a7 -fpic -ffreestanding -c boot.S -o boot.o
armv7a-hardfloat-linux-gnueabi-gcc -mcpu=cortex-a7 -fpic -ffreestanding -std=gnu99 -c kernel.c -o kernel.o -O2 -Wall -Wextra
armv7a-hardfloat-linux-gnueabi-gcc -T linker.ld -o myos.elf -ffreestanding -O2 -nostdlib boot.o kernel.o
armv7a-hardfloat-linux-gnueabi-objcopy myos.elf -O binary myos.bin

# QEMU >= 6 renamed the machine raspi2 -> raspi2b; it models the fixed 1 GiB
# of the board (no -m), and its default CPU already is cortex-a7:
qemu-system-arm -M raspi2b -kernel myos.elf -serial stdio
# (real hardware: copy myos.bin to the SD card as kernel7.img)
