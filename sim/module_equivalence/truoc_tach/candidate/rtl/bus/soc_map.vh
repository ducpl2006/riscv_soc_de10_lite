`ifndef SOC_MAP_VH
`define SOC_MAP_VH
// Bản đồ địa chỉ RTL dùng chung và các làn phản hồi được đóng gói. Làn n sở hữu bit n trong
// các tín hiệu req/ready/err và các bit [n*32 +: 32] trong rdata. Duy trì tính ổn định của ABI cho làn hiện có.
`define SOC_SLAVE_COUNT 7
`define SOC_SLAVE_ROM   0
`define SOC_SLAVE_RAM   1
`define SOC_SLAVE_GPIO  2
`define SOC_SLAVE_UART  3
`define SOC_SLAVE_I2C   4
`define SOC_SLAVE_QNN   5
`define SOC_SLAVE_TIMER 6

`define SOC_ROM_BASE    32'h0000_0000
`define SOC_RAM_BASE    32'h1000_0000
`define SOC_GPIO_BASE   32'h2000_0000
`define SOC_UART_BASE   32'h2000_1000
`define SOC_I2C_BASE    32'h2000_2000
`define SOC_QNN_BASE    32'h2000_3000
`define SOC_TIMER_BASE  32'h2000_4000

// Mỗi thiết bị phụ MMIO sở hữu 4 KiB; thiết bị phụ sẽ từ chối các độ lệch 12-bit không được triển khai.
`define SOC_MMIO_MASK   32'hFFFF_F000
`define SOC_QNN_MASK    32'hFFFF_F000

`endif
