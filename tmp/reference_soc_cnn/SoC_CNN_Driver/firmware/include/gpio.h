#ifndef GPIO_H
#define GPIO_H

#include <stdint.h>

// Ghi giá trị ra 10 LED đỏ (LEDR[9:0]).
void gpio_set_ledr(uint32_t value);

// Ghi giá trị ra dãy LED 7 đoạn (24-bit thấp = 6 digit hex).
void gpio_set_hex(uint32_t value);

// Đọc trạng thái 10 switch (SW[9:0]).
uint32_t gpio_get_sw(void);

#endif // GPIO_H
