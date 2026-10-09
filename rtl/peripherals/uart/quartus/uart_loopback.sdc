# Clock chính của bo mạch: 50 MHz.
create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]

# KEY[0] là nguồn reset bất đồng bộ; chỉ quá trình nhả reset được đồng bộ.
set_false_path -from [get_ports {KEY[0]}]

# Đường UART bất đồng bộ chỉ được phân tích timing từ tầng đồng bộ thứ hai.
set_false_path \
    -from [get_ports {GPIO_UART_RX}] \
    -to [get_registers -nowarn {*|u_uart_rx_sync|sync_ff1}]
