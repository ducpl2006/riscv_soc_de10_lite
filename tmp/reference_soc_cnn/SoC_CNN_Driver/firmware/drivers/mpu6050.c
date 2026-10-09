#include "mpu6050.h"
#include "i2c.h"
#include "soc.h"

#define MPU6050_WHOAMI      0x75    // RO, trả 0x68
#define MPU6050_PWR_MGMT1   0x6B    // [6]SLEEP: boot=1, phải ghi 0 để thức
#define MPU6050_ACCEL_X0    0x3B    // 6 byte: XH,XL,YH,YL,ZH,ZL (BIG-endian)

// MPU-6050 chịu tối đa 400kHz; chạy 100kHz cho chắc.
#define MPU6050_SCL_HZ      100000u

static uint8_t g_whoami;

uint32_t mpu6050_init(void)
{
    i2c_init(MPU6050_ADDR, I2C_PRESCALE_FOR(F_SYS_HZ, MPU6050_SCL_HZ));

    g_whoami = 0;
    i2c_read_reg(MPU6050_WHOAMI, &g_whoami, 1);

    if (g_whoami != MPU6050_WHOAMI_VAL)
        return 0;

    // Thức khỏi sleep. Các thanh ghi còn lại giữ mặc định (+-2g, 16384 LSB/g).
    i2c_write_reg(MPU6050_PWR_MGMT1, 0x00);

    return 1;
}

uint8_t mpu6050_whoami(void)
{
    return g_whoami;
}

void mpu6050_read_accel(mpu6050_accel_t *a)
{
    uint8_t d[6];

    // Burst 6 byte trong 1 transaction. MPU-6050 big-endian: byte cao trước.
    i2c_read_reg(MPU6050_ACCEL_X0, d, 6);

    a->x = (int16_t)(((uint16_t)d[0] << 8) | (uint16_t)d[1]);
    a->y = (int16_t)(((uint16_t)d[2] << 8) | (uint16_t)d[3]);
    a->z = (int16_t)(((uint16_t)d[4] << 8) | (uint16_t)d[5]);
}
