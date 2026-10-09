#include <stdint.h>

#include "soc.h"
#include "gpio.h"
#include "uart.h"
#include "i2c.h"
#include "mpu6050.h"

// Số vòng main loop giữa 2 lần đọc/in accel. UART 115200 không kham nổi tốc độ
// poll tối đa -> phải giãn ra.
#define ACCEL_PERIOD    200000

#define RX_BUF_SIZE     64

// =====================================================
// BOOT TESTS
// =====================================================
static void gpio_boot_test(void)
{
    gpio_set_ledr(0x155);
    gpio_set_hex(0x123456);
}

// Ghi 2 byte tới slave 0x50 rồi in kết quả.
// I2C chạy trước UART print (UART chậm) để dễ quan sát khi mô phỏng.
static void i2c_boot_test(void)
{
    uint8_t  wr[2] = { 0xA5, 0x3C };
    uint32_t ver   = i2c_version();

    i2c_init(0x50, 4);
    i2c_write(wr, 2);

    // Soi nhanh ACK từ slave ra LEDR[0].
    gpio_set_ledr(i2c_ack_ok() ? 0x001 : 0x200);

    uart_print("I2C VERSION: ");
    uart_print_hex32(ver);
    uart_print(" WR STATUS=");
    uart_print_hex32(i2c_status());
    uart_print("\r\n");
}

// mpu6050_init() im lặng -> log kết quả ở tầng ứng dụng.
static uint32_t mpu_boot_init(void)
{
    uint32_t ok = mpu6050_init();

    uart_print("MPU6050 WHO_AM_I: ");
    uart_print_hex32(mpu6050_whoami());
    uart_print(ok ? " -> OK\r\n" : " -> FAIL (mong 0x68)\r\n");

    return ok;
}

// =====================================================
// APP
// =====================================================
static void clear_buf(volatile char *buf)
{
    for (uint32_t i = 0; i < RX_BUF_SIZE; i++)
        buf[i] = 0;
}

static void print_accel(void)
{
    mpu6050_accel_t a;

    mpu6050_read_accel(&a);

    uart_print("ACCEL X=");
    uart_print_int(a.x);
    uart_print(" Y=");
    uart_print_int(a.y);
    uart_print(" Z=");
    uart_print_int(a.z);
    uart_print("\r\n");
}

int main(void)
{
    volatile char rx_buf[RX_BUF_SIZE];

    uint32_t idx = 0;
    uint32_t enter_count = 0;
    uint32_t sw_value = 0;

    // giá trị SW đã in lần trước (chỉ in khi thay đổi -> tránh nghẽn UART)
    uint32_t prev_sw = 0xFFFFFFFF;

    uint32_t mpu_ok     = 0;
    uint32_t accel_tick = 0;

    clear_buf(rx_buf);

    gpio_boot_test();
    i2c_boot_test();

    uart_print("CODE KHONG BUG\r\n");
    // Banner (in thẳng, không dùng ANSI -> hợp Arduino Serial Monitor)
    uart_print("RV32IM UART + GPIO TEST\r\n");
    uart_print("TYPE TEXT THEN PRESS ENTER\r\n");

    // Đổi lại prescale/address mà i2c_boot_test() đã set cho slave 0x50.
    mpu_ok = mpu_boot_init();

    while (1)
    {
        // =================================================
        // GPIO realtime
        // =================================================
        sw_value = gpio_get_sw();

        gpio_set_ledr(sw_value);            // LEDR mirror SW[9:0]
        gpio_set_hex(enter_count);          // HEX đếm số lần ENTER

        // Chỉ in ra PC khi giá trị SW thay đổi
        if (sw_value != prev_sw)
        {
            uart_print("GPIO SW: ");
            uart_print_hex32(sw_value);
            uart_print("\r\n");
            prev_sw = sw_value;
        }

        // =================================================
        // MPU-6050 realtime (giãn chu kỳ -> không nghẽn UART)
        // =================================================
        if (mpu_ok)
        {
            accel_tick++;

            if (accel_tick >= ACCEL_PERIOD)
            {
                accel_tick = 0;
                print_accel();
            }
        }

        // =================================================
        // UART receive
        // =================================================
        if (uart_rx_ready())
        {
            char c = uart_recv();

            // ENTER: end line
            if (c == '\n' || c == '\r')
            {
                rx_buf[idx] = 0;
                enter_count++;

                uart_print("RX FROM PC: ");
                uart_print_buffer(rx_buf, idx);
                uart_print("\r\n");

                uart_print("CPU ECHO:   ");
                uart_print_buffer(rx_buf, idx);
                uart_print("\r\n");

                uart_print("ENTER COUNT: ");
                uart_print_dec(enter_count);
                uart_print("\r\n");

                idx = 0;
                clear_buf(rx_buf);
            }

            // BACKSPACE
            else if (c == 8 || c == 127)
            {
                if (idx > 0)
                {
                    idx--;
                    rx_buf[idx] = 0;
                }
            }

            // NORMAL CHARACTER
            else
            {
                if (idx < RX_BUF_SIZE - 1)
                {
                    rx_buf[idx] = c;
                    idx++;
                }
                else
                {
                    uart_print("ERROR: BUFFER FULL\r\n");

                    idx = 0;
                    clear_buf(rx_buf);
                }
            }
        }
    }

    return 0;
}
