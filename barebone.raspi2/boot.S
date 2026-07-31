// To keep this in the first portion of the binary.
.section ".text.boot"
 
// Make _start global.
.globl _start
 
// Entry point for the kernel.
// r15 -> should begin execution at 0x8000.
// r0 -> 0x00000000
// r1 -> 0x00000C42
// r2 -> 0x00000100 - start of ATAGS
// preserve these registers as argument for kernel_main
_start:
	// The Pi 2 (and qemu -M raspi2b) starts all 4 cores here —
	// park everything but core 0, or four cores run kernel_main
	// at once and garble the UART.
	mrc p15, #0, r1, c0, c0, #5
	and r1, r1, #3
	cmp r1, #0
	bne halt

	// Setup the stack.
	mov sp, #0x8000
 
	// Clear out bss.
	ldr r4, =__bss_start
	ldr r9, =__bss_end
	mov r5, #0
	mov r6, #0
	mov r7, #0
	mov r8, #0
	b       2f
 
1:
	// store multiple at r4.
	stmia r4!, {r5-r8}
 
	// If we are still below bss_end, loop.
2:
	cmp r4, r9
	blo 1b
 
	// Call kernel_main
	ldr r3, =kernel_main
	blx r3
 
	// halt
halt:
	wfe
	b halt
