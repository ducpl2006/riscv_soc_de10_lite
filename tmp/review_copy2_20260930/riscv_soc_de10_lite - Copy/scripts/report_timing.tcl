# Xuat 20 duong setup/hold sau fit tai ba corner cua MAX 10.
# Chay tu thu muc quartus: quartus_sta -t ../scripts/report_timing.tcl
# Yeu cau full compilation thanh cong; khong thay doi QSF/SDC.
project_open riscv_soc
create_timing_netlist
read_sdc
foreach corner {{slow 85 1200} {slow 0 1200} {fast 0 1200}} {
    lassign $corner model temperature voltage
    set_operating_conditions -model $model -temperature $temperature -voltage $voltage
    update_timing_netlist
    set tag "${model}_${voltage}mV_${temperature}C"
    foreach analysis {setup hold} {
        set result [report_timing -$analysis -npaths 20 -nworst 1 -detail full_path \
            -file "output_files/riscv_soc_${tag}_${analysis}_top20.rpt"]
        puts "$tag $analysis : paths=[lindex $result 0], slack=[lindex $result 1] ns"
    }
}
delete_timing_netlist
project_close
