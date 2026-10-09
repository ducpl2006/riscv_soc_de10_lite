#ifndef MPU6050_H
#define MPU6050_H

#include <stdint.h>

#define MPU6050_ADDR        0x68    // AD0 -> GND. Nối AD0 lên VCC thì đổi 0x69
#define MPU6050_WHOAMI_VAL  0x68

typedef struct {
    int16_t x;
    int16_t y;
    int16_t z;
} mpu6050_accel_t;

// Cấu hình bus I2C cho sensor rồi đọc WHO_AM_I và đánh thức khỏi sleep.
// Trả 1 nếu WHO_AM_I khớp (bus + sensor OK), 0 nếu không.
// Gọi lại nếu có thiết bị khác đã chiếm bus qua i2c_init().
uint32_t mpu6050_init(void);

// Giá trị WHO_AM_I đọc được ở lần mpu6050_init() gần nhất (để log/chẩn đoán).
uint8_t mpu6050_whoami(void);

// Đọc gia tốc 3 trục trong 1 transaction (X/Y/Z chắc chắn cùng một mẫu).
// Thang mặc định +-2g -> 16384 LSB/g.
void mpu6050_read_accel(mpu6050_accel_t *a);

#endif // MPU6050_H
