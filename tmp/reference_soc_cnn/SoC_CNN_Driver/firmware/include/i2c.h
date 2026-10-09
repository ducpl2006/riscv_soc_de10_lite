#ifndef I2C_H
#define I2C_H

#include <stdint.h>

// STATUS bits (dùng cho i2c_status() / i2c_ack_ok()).
#define I2C_ST_BUSY      (1 << 0)
#define I2C_ST_RXACK     (1 << 2)
#define I2C_ST_TX_EMPTY  (1 << 5)
#define I2C_ST_IDLE      (1 << 7)

// Tính prescale từ tốc độ SCL mong muốn: SCL = f_sys / (4*(prescale+1)).
#define I2C_PRESCALE_FOR(f_sys, f_scl)  ((uint16_t)((f_sys) / (4u * (f_scl)) - 1u))

// Đọc thanh ghi VERSION của IP.
uint32_t i2c_version(void);

// Đọc thanh ghi STATUS thô.
uint32_t i2c_status(void);

// 1 nếu slave đã ACK ở transaction gần nhất (bit RXACK = 0).
uint32_t i2c_ack_ok(void);

// addr: địa chỉ slave 7-bit; prescale: xem I2C_PRESCALE_FOR.
// Gọi lại để chuyển sang slave khác.
void i2c_init(uint8_t addr, uint16_t prescale);

// Ghi n byte tới slave (START ... STOP). Địa chỉ + R/W do HW tự chèn.
void i2c_write(const uint8_t *data, uint32_t n);

// Đọc n byte từ slave (NACK + STOP ở byte cuối).
void i2c_read(uint8_t *dst, uint32_t n);

// Ghi 1 byte vào thanh ghi của slave.
void i2c_write_reg(uint8_t reg, uint8_t val);

// Đọc n byte liên tiếp bắt đầu từ `reg`, dùng repeated START.
void i2c_read_reg(uint8_t reg, uint8_t *dst, uint32_t n);

#endif // I2C_H
