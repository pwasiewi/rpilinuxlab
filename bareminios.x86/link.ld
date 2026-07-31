OUTPUT_FORMAT(elf32-i386)
ENTRY(start)
SECTIONS
{
    . = 0x100000;
    /* multiboot header first — must be in the first 8 KiB of the file */
    .text : { KEEP(*(.multiboot)) *(.text) *(.text.*) }
    .rodata : { *(.rodata) *(.rodata.*) }
    .data : { *(.data) }
    .bss  : { *(COMMON) *(.bss)  }
    /* modern gcc emits these; they are useless in a freestanding kernel and
       orphan .note sections can land in front of the multiboot header */
    /DISCARD/ : { *(.eh_frame) *(.note*) *(.comment) }
}
