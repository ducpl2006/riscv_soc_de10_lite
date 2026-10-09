# Clock onboard DE10-Lite: 50 MHz, chu kỳ 20 ns.
create_clock -name clk_50 -period 20.000 [get_ports {MAX10_CLK1_50}]

# Để TimeQuest tính setup/hold với uncertainty theo model thiết bị thay vì giả
# định bằng 0. Lệnh này tương thích Quartus Prime 20.1 và chỉ tác động phân tích.
derive_clock_uncertainty

# KEY là input bất đồng bộ đi vào chuỗi đồng bộ reset; bỏ timing đến FF đầu.
set_false_path -from [get_ports {KEY[0]}]

# SW/I2C là input bất đồng bộ đã qua hai FF; chỉ bỏ timing từ pad tới FF đầu.
set_false_path -from [get_ports {SW[*]}]   -to [get_registers {*switch_meta_q[*]}]
set_false_path -from [get_ports {GPIO[*]}] -to [get_registers {*i2c_meta_q[*]}]
set_false_path -from [get_ports {UART_RX}] -to [get_registers {*u_rx|rx_meta_q}]

# LED/UART/I2C không có clock giao tiếp ngoài để khai báo output delay. Timing
# nội bộ tới register nguồn vẫn được phân tích; chỉ bỏ đường từ nguồn tới pad.
set_false_path -to [get_ports {LEDR[*]}]
set_false_path -to [get_ports {UART_TX}]
set_false_path -to [get_ports {GPIO[*]}]
