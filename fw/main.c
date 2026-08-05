#include <stdint.h>

#define UART_TX (*((volatile uint32_t*)0x10000000))
#define UART_RX (*((volatile uint32_t*)0x10000004))
#define UART_ST (*((volatile uint32_t*)0x10000008))

void uart_putc(char c) {
    while (UART_ST & 1);
    UART_TX = c;
}

void uart_puts(const char* str) {
    while (*str) {
        uart_putc(*str++);
    }
}

int main() {
    int i;
    for (i = 0; i < 10; i++) {
        uart_puts("Hello Ramnarayan\n");
    }
    
    // Echo PING
    uart_puts("PING");
    
    return 0;
}
