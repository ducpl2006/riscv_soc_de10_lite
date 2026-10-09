#include "uart.h"
#include "soc.h"

#define UART_TX_DATA   REG32(UART_BASE + 0x00)
#define UART_RX_DATA   REG32(UART_BASE + 0x04)
#define UART_STATUS    REG32(UART_BASE + 0x08)

// STATUS bits
#define UART_TX_FULL   (1 << 0)
#define UART_RX_EMPTY  (1 << 1)
#define UART_TX_READY  (1 << 2)
#define UART_RX_IRQ    (1 << 3)

void uart_send(char c)
{
    while (!(UART_STATUS & UART_TX_READY));
    UART_TX_DATA = (uint32_t)c;
}

void uart_print(const char *s)
{
    while (*s != 0)
    {
        uart_send(*s);
        s++;
    }
}

void uart_print_buffer(volatile char *buf, uint32_t len)
{
    for (uint32_t i = 0; i < len; i++)
    {
        uart_send(buf[i]);
    }
}

void uart_print_hex32(uint32_t v)
{
    const char hex[] = "0123456789ABCDEF";

    uart_print("0x");

    for (int i = 7; i >= 0; i--)
    {
        uint32_t nibble = (v >> (i * 4)) & 0xF;
        uart_send(hex[nibble]);
    }
}

void uart_print_dec(uint32_t v)
{
    char buf[12];
    int  i = 0;

    if (v == 0) { uart_send('0'); return; }

    while (v)      { buf[i++] = (char)('0' + (v % 10)); v /= 10; }
    while (i)      { uart_send(buf[--i]); }
}

void uart_print_int(int32_t v)
{
    if (v < 0)
    {
        uart_send('-');
        v = -v;
    }

    uart_print_dec((uint32_t)v);
}

uint32_t uart_rx_ready(void)
{
    return (UART_STATUS & UART_RX_EMPTY) ? 0u : 1u;
}

char uart_recv(void)
{
    return (char)(UART_RX_DATA & 0xFF);
}
