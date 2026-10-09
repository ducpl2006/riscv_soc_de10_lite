#ifndef UART_H
#define UART_H

#include <stdint.h>

// Gửi 1 ký tự (blocking tới khi TX sẵn sàng).
void uart_send(char c);

// Gửi chuỗi kết thúc bằng '\0'.
void uart_print(const char *s);

// Gửi len ký tự từ buffer (buffer có thể là volatile).
void uart_print_buffer(volatile char *buf, uint32_t len);

// In số dạng "0xXXXXXXXX".
void uart_print_hex32(uint32_t v);

// In số không dấu dạng thập phân.
void uart_print_dec(uint32_t v);

// In số có dấu dạng thập phân.
void uart_print_int(int32_t v);

// 1 = có byte trong FIFO thu, 0 = rỗng.
uint32_t uart_rx_ready(void);

// Đọc 1 byte từ FIFO thu. Chỉ gọi khi uart_rx_ready() trả 1.
char uart_recv(void);

#endif // UART_H
