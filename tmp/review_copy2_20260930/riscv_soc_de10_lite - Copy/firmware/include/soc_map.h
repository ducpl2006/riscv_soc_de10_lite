#ifndef SOC_MAP_H
#define SOC_MAP_H

#include <stdint.h>

/*
 * Đặc tả phần mềm của memory map rv32_soc.
 * Mọi truy cập MMIO đều volatile để compiler không xóa hay đổi thứ tự.
 */
#define MMIO32(address) (*(volatile uint32_t *)(uintptr_t)(address))

#define GPIO_BASE       0x20000000u
#define GPIO_LED        MMIO32(GPIO_BASE + 0x00u)
#define GPIO_SWITCH     MMIO32(GPIO_BASE + 0x04u)
#define GPIO_LED_WIDTH  8u /* LEDR[8]=QNN busy, LEDR[9]=trap; không thuộc GPIO. */
#define GPIO_LED_MASK   ((1u << GPIO_LED_WIDTH) - 1u)
#define SOC_MMIO_PAGE_BYTES 4096u /* Offset chưa định nghĩa trong page trả fault. */

#define UART_BASE       0x20001000u
#define UART_DATA       MMIO32(UART_BASE + 0x00u)
#define UART_STATUS     MMIO32(UART_BASE + 0x04u)
#define UART_TX_READY   (1u << 0) /* Có chỗ nhận byte vào FIFO/bộ phát. */
#define UART_TX_BUSY    (1u << 1) /* Còn byte chờ hoặc chưa phát hết stop bit. */
#define UART_RX_DATA    MMIO32(UART_BASE + 0x08u) /* RO, đọc thành công pop một byte. */
#define UART_ERRORS     MMIO32(UART_BASE + 0x0Cu) /* RW, ghi 1 xóa bit lỗi [7:5]. */
#define UART_RX_VALID   (1u << 2) /* Kiểm tra trước khi đọc RX_DATA; đọc rỗng fault. */
#define UART_RX_EMPTY   (1u << 3)
#define UART_RX_FULL    (1u << 4)
#define UART_RX_OVERRUN (1u << 5) /* Byte mới bị bỏ do RX FIFO đầy. */
#define UART_RX_FRAMING_ERROR (1u << 6) /* Stop bit thấp; frame bị loại. */
#define UART_RX_FALSE_START   (1u << 7) /* Line cao tại giữa start bit. */
#define UART_RX_ERROR_MASK (UART_RX_OVERRUN | UART_RX_FRAMING_ERROR | UART_RX_FALSE_START)

#define I2C_BASE        0x20002000u
#define I2C_DATA        MMIO32(I2C_BASE + 0x00u)
#define I2C_COMMAND     MMIO32(I2C_BASE + 0x04u)
#define I2C_STATUS      MMIO32(I2C_BASE + 0x08u)
#define I2C_CMD_START   (1u << 0)
#define I2C_CMD_STOP    (1u << 1)
#define I2C_CMD_READ    (1u << 2)
#define I2C_CMD_NACK    (1u << 3)
#define I2C_CMD_CLEAR   (1u << 4)
#define I2C_CMD_RECOVER (1u << 5) /* Hủy lệnh cũ, tối đa 9 xung và STOP. */
#define I2C_CMD_CLEAR_ERRORS (1u << 6) /* Xóa ACK/timeout/recovery_error. */
#define I2C_CMD_EXECUTE (1u << 7)
#define I2C_BUSY        (1u << 0)
#define I2C_DONE        (1u << 1)
#define I2C_ACK_ERROR   (1u << 2)
#define I2C_TIMEOUT     (1u << 3) /* Chờ SCL/SDA vượt TIMEOUT_CYCLES. */
#define I2C_RECOVERY_ERROR (1u << 4) /* Phục hồi không nhả được bus. */
#define I2C_ERROR_MASK  (I2C_ACK_ERROR | I2C_TIMEOUT | I2C_RECOVERY_ERROR)

#define QNN_BASE        0x20003000u
#define QNN_CONTROL     MMIO32(QNN_BASE + 0x000u)
#define QNN_STATUS      MMIO32(QNN_BASE + 0x004u)
#define QNN_RESULT      MMIO32(QNN_BASE + 0x008u)
#define QNN_CYCLES      MMIO32(QNN_BASE + 0x00Cu)
#define QNN_CONFIG      MMIO32(QNN_BASE + 0x010u)
#define QNN_FEATURE(n)  MMIO32(QNN_BASE + 0x100u + 4u * (uint32_t)(n))
#define QNN_START       (1u << 0)
#define QNN_CLEAR_DONE  (1u << 1)
#define QNN_BUSY        (1u << 0)
#define QNN_DONE        (1u << 1)

#define TIMER_BASE      0x20004000u
#define TIMER_TIME_LO   MMIO32(TIMER_BASE + 0x00u)
#define TIMER_TIME_HI   MMIO32(TIMER_BASE + 0x04u)

#endif
