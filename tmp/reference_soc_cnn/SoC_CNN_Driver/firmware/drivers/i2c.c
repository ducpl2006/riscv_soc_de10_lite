#include "i2c.h"
#include "soc.h"

#define I2C_VERSION_REG  REG32(I2C_BASE + 0x00)
#define I2C_CTRL         REG32(I2C_BASE + 0x04)
#define I2C_STATUS_REG   REG32(I2C_BASE + 0x08)
#define I2C_PRESCALE     REG32(I2C_BASE + 0x10)
#define I2C_ADDRESS      REG32(I2C_BASE + 0x14)
#define I2C_DATACMD      REG32(I2C_BASE + 0x18)
#define I2C_RXDATA       REG32(I2C_BASE + 0x1C)

// CTRL bits
#define I2C_EN           (1 << 0)

// DATA_CMD flags
#define I2C_CMD_READ     (1 << 8)     // 0 = write, 1 = read
#define I2C_F_START      (1 << 9)
#define I2C_F_STOP       (1 << 10)
#define I2C_F_NACK       (1 << 11)

// Chờ engine rảnh + FIFO lệnh đã rỗng (transaction hoàn tất).
static void i2c_wait_ready(void)
{
    uint32_t mask = I2C_ST_IDLE | I2C_ST_TX_EMPTY;
    while ((I2C_STATUS_REG & mask) != mask);
}

uint32_t i2c_version(void)
{
    return I2C_VERSION_REG;
}

uint32_t i2c_status(void)
{
    return I2C_STATUS_REG;
}

uint32_t i2c_ack_ok(void)
{
    return (I2C_STATUS_REG & I2C_ST_RXACK) ? 0u : 1u;
}

void i2c_init(uint8_t addr, uint16_t prescale)
{
    I2C_PRESCALE = prescale;
    I2C_ADDRESS  = addr;        // [9:0], dùng 7-bit thấp
    I2C_CTRL     = I2C_EN;
}

void i2c_write(const uint8_t *data, uint32_t n)
{
    for (uint32_t i = 0; i < n; i++)
    {
        uint32_t cmd = data[i];
        if (i == 0)     cmd |= I2C_F_START;
        if (i == n - 1) cmd |= I2C_F_STOP;
        I2C_DATACMD = cmd;
    }
    i2c_wait_ready();
}

void i2c_read(uint8_t *dst, uint32_t n)
{
    for (uint32_t i = 0; i < n; i++)
    {
        uint32_t cmd = I2C_CMD_READ;
        if (i == 0)     cmd |= I2C_F_START;
        if (i == n - 1) cmd |= (I2C_F_STOP | I2C_F_NACK);
        I2C_DATACMD = cmd;
    }
    i2c_wait_ready();
    for (uint32_t i = 0; i < n; i++)
        dst[i] = (uint8_t)(I2C_RXDATA & 0xFF);
}

void i2c_write_reg(uint8_t reg, uint8_t val)
{
    uint8_t wr[2] = { reg, val };
    i2c_write(wr, 2);
}

// START + addr+W + reg  ->  rSTART + addr+R  ->  n byte  ->  NACK + STOP
// i2c_write() không dùng được ở đây vì nó luôn chèn STOP sau byte cuối,
// làm mất repeated START mà register read của sensor yêu cầu.
void i2c_read_reg(uint8_t reg, uint8_t *dst, uint32_t n)
{
    I2C_DATACMD = (uint32_t)reg | I2C_F_START;      // pointer write, KHÔNG stop

    for (uint32_t i = 0; i < n; i++)
    {
        uint32_t cmd = I2C_CMD_READ;
        if (i == 0)     cmd |= I2C_F_START;         // repeated START (HW tự gửi addr+R)
        if (i == n - 1) cmd |= (I2C_F_STOP | I2C_F_NACK);
        I2C_DATACMD = cmd;
    }

    i2c_wait_ready();

    for (uint32_t i = 0; i < n; i++)
        dst[i] = (uint8_t)(I2C_RXDATA & 0xFF);
}
