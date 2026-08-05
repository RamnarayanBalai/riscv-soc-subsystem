.section .text.start, "ax"
.global _start
_start:
    /* Set up stack pointer (SRAM top is 0x000100FC) */
    li sp, 0x000100FC
    /* Call main */
    jal ra, main
    /* infinite loop if main returns */
1:  j 1b
