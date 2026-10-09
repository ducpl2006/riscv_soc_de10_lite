#include "gpio.h"
#include "soc.h"

#define GPIO_LEDR   REG32(GPIO_BASE + 0x00)
#define GPIO_HEX    REG32(GPIO_BASE + 0x04)
#define GPIO_SW     REG32(GPIO_BASE + 0x0C)

#define GPIO_LEDR_MASK  0x000003FFu
#define GPIO_HEX_MASK   0x00FFFFFFu
#define GPIO_SW_MASK    0x000003FFu

void gpio_set_ledr(uint32_t value)
{
    GPIO_LEDR = value & GPIO_LEDR_MASK;
}

void gpio_set_hex(uint32_t value)
{
    GPIO_HEX = value & GPIO_HEX_MASK;
}

uint32_t gpio_get_sw(void)
{
    return GPIO_SW & GPIO_SW_MASK;
}
