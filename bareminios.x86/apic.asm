    extern  screen_printf
    global  apic_default_isr
    global  apic_spurious_isr
    global  apic_tick_isr
    global  apic_sw_int

LOCAL_APIC_BASE equ 0xfee00000

section .data
    msg_default_isr:
    db      "=====default_isr====", 0x0a, 0
    msg_spurious_isr:
    db      "====spurious_isr====", 0x0a, 0
    msg_tick_isr:
    db      "======tick_isr======", 0x0a, 0

section .text
bits 32
; ISRs must preserve ALL registers of the interrupted code — screen_printf
; (cdecl) clobbers eax/ecx/edx, so wrap the calls in pushad/popad or every
; interrupt silently corrupts whatever main() was doing.
apic_default_isr:
    pushad
    push    msg_default_isr
    call    screen_printf
    add     esp, 4
    mov     dword [LOCAL_APIC_BASE + 0xb0], 0x00
    popad
    iret

apic_spurious_isr:
    pushad
    push    msg_spurious_isr
    call    screen_printf
    add     esp, 4
    popad
    iret

apic_tick_isr:
    ; push    msg_tick_isr
    ; call    screen_printf
    ; add     esp, 4
    mov     dword [LOCAL_APIC_BASE + 0xb0], 0x00
    iret

apic_sw_int:
    int     0x21
    ret

; mark objects as not needing an executable stack (binutils >= 2.39 warns)
section .note.GNU-stack noalloc noexec nowrite progbits
