#ifndef SOC_H
#define SOC_H

#include <stdint.h>

// Bản đồ địa chỉ MMIO của SoC (CPU -> AXI -> APB)
#define GPIO_BASE   0x10000000
#define UART_BASE   0x20000000
#define VGA_BASE    0x30000000
#define I2C_BASE    0x40000000

// Tần số clock hệ thống, dùng để tính prescale cho I2C/UART
#define F_SYS_HZ    50000000u

#define REG32(addr) (*(volatile uint32_t *)(addr))

#endif // SOC_H
