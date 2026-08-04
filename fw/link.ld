MEMORY {
    ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 8K
    SRAM (rw) : ORIGIN = 0x00010000, LENGTH = 256
}

SECTIONS {
    .text : {
        *(.text)
        *(.rodata*)
    } > ROM

    .data : {
        *(.data*)
        *(.bss*)
    } > SRAM
}
