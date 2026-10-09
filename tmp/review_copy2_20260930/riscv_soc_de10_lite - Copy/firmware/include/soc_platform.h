#ifndef SOC_PLATFORM_H
#define SOC_PLATFORM_H
#include <stdint.h>
#ifndef SOC_CLOCK_HZ
#define SOC_CLOCK_HZ 50000000u
#endif
/* All waits are bounded. Return 1 for success, 0 for timeout/I/O failure. */
int soc_uart_putc(char byte);
int soc_uart_text(const char *text);
int soc_uart_u32(uint32_t value);
int soc_uart_drain(void);
int soc_wait_cycles(uint32_t cycles);
uint32_t soc_time_low(void);
int soc_qnn_run(const int8_t features[80], uint32_t *soc_deci_percent);
/* INA transport: MSB-first register value; bytes=2 or 3, repeated START on read.
 * Output is updated only after all bytes succeed. Context is unused on this SoC. */
int soc_sensor_read(void *context, uint8_t address, uint8_t reg, uint8_t bytes, uint32_t *value);
int soc_sensor_write16(void *context, uint8_t address, uint8_t reg, uint16_t value);
#endif
