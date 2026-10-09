# Chạy từ quartus/: quartus_sta -t ../scripts/report_bus_timing.tcl <report-directory>
# Báo các path thật sau fit; không suy Fmax từ riêng một giá trị slack.
project_open riscv_soc
create_timing_netlist
read_sdc
update_timing_netlist
set report_dir [lindex $quartus(args) 0]
file mkdir $report_dir
report_timing -setup -npaths 20 -detail full_path -file "$report_dir/setup_paths.rpt"
report_timing -hold -npaths 10 -detail full_path -file "$report_dir/hold_paths.rpt"
report_clock_fmax_summary -file "$report_dir/fmax.rpt"
delete_timing_netlist
project_close
