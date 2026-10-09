#include "include/soc_platform.h"
#include "include/soc_map.h"

/* CPU iteration cap also terminates waits if the timer itself stops advancing. */
#define POLL_LIMIT 2000000u
#define IO_TIMEOUT_CYCLES (SOC_CLOCK_HZ / 10u)

uint32_t soc_time_low(void) { return TIMER_TIME_LO; }

static int wait_mask(uint32_t address, uint32_t mask, uint32_t expected)
{
    uint32_t start = soc_time_low(), polls;
    for (polls = 0; polls < POLL_LIMIT; ++polls) {
        if ((MMIO32(address) & mask) == expected) return 1;
        if ((uint32_t)(soc_time_low() - start) >= IO_TIMEOUT_CYCLES) return 0;
    }
    return 0;
}

int soc_wait_cycles(uint32_t cycles)
{
    uint32_t start = soc_time_low(), polls;
    /* 50M polls permit a normal 10-second interval at 50 MHz; still finite. */
    for (polls = 0; polls < 50000000u; ++polls)
        if ((uint32_t)(soc_time_low() - start) >= cycles) return 1;
    return 0;
}

int soc_uart_putc(char byte)
{
    if (!wait_mask(UART_BASE+4u, UART_TX_READY, UART_TX_READY)) return 0;
    UART_DATA = (uint8_t)byte;
    return 1;
}
int soc_uart_text(const char *text)
{
    while (*text) if (!soc_uart_putc(*text++)) return 0;
    return 1;
}
int soc_uart_u32(uint32_t value)
{
    char digits[10];
    uint32_t count = 0;
    do { digits[count++] = (char)('0' + value % 10u); value /= 10u; } while (value);
    while (count) if (!soc_uart_putc(digits[--count])) return 0;
    return 1;
}
int soc_uart_drain(void) { return wait_mask(UART_BASE+4u, UART_TX_BUSY, 0); }

int soc_qnn_run(const int8_t features[80], uint32_t *soc_deci_percent)
{
    uint32_t i, status;
    if (!wait_mask(QNN_BASE+4u, QNN_BUSY, 0)) return 0;
    QNN_CONTROL = QNN_CLEAR_DONE;
    for (i = 0; i < 80; ++i) QNN_FEATURE(i) = (uint8_t)features[i];
    QNN_CONTROL = QNN_START;
    if (!wait_mask(QNN_BASE+4u, QNN_BUSY|QNN_DONE, QNN_DONE)) return 0;
    status = QNN_RESULT;
    if (status > 1000u) return 0;
    *soc_deci_percent = status;
    return 1;
}

static int i2c_idle(void) { return wait_mask(I2C_BASE+8u, I2C_BUSY, 0); }
static void i2c_recover(void)
{
    /* One recovery attempt only; failure is returned to caller, never retried forever. */
    I2C_COMMAND = I2C_CMD_RECOVER | I2C_CMD_CLEAR_ERRORS;
    (void)i2c_idle();
}
static int i2c_execute(uint32_t command)
{
    I2C_COMMAND = command | I2C_CMD_EXECUTE | I2C_CMD_CLEAR_ERRORS;
    if (!i2c_idle() || (I2C_STATUS & I2C_ERROR_MASK)) {
        i2c_recover();
        return 0;
    }
    return 1;
}
static int i2c_send(uint8_t value, uint32_t command)
{
    if (!i2c_idle()) { i2c_recover(); return 0; }
    I2C_DATA = value;
    return i2c_execute(command);
}
int soc_sensor_read(void *context, uint8_t address, uint8_t reg, uint8_t bytes, uint32_t *value)
{
    uint32_t result=0, i;
    (void)context;
    if ((bytes != 2 && bytes != 3) || address > 0x7f || !value) return 0;
    if (!i2c_send((uint8_t)(address<<1), I2C_CMD_START) || !i2c_send(reg, 0) ||
        !i2c_send((uint8_t)((address<<1)|1), I2C_CMD_START)) return 0;
    for (i=0; i<bytes; ++i) {
        if (!i2c_execute(I2C_CMD_READ | (i+1 == bytes ? I2C_CMD_NACK|I2C_CMD_STOP : 0))) return 0;
        result = (result<<8) | (I2C_DATA & 0xffu);
    }
    *value = result;
    return 1;
}
int soc_sensor_write16(void *context, uint8_t address, uint8_t reg, uint16_t value)
{
    (void)context;
    if (address > 0x7f) return 0;
    return i2c_send((uint8_t)(address<<1), I2C_CMD_START) && i2c_send(reg,0) &&
           i2c_send((uint8_t)(value>>8),0) && i2c_send((uint8_t)value,I2C_CMD_STOP);
}
