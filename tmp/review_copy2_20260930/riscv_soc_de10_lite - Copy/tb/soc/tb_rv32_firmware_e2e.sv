`timescale 1ns/1ps
`default_nettype none
`include "qnn_model_config.vh"
// Runs compiled C through real ROM, RAM, registered bus, QNN, timer and UART.
// Scoreboards observe handshakes/serial pins; no internal state is forced.
module tb_rv32_firmware_e2e #(
    parameter integer SENSOR_MODE=1,
    parameter integer FAULT_MODE=0
);
    reg clk=0; always #5 clk=~clk;
    reg rst=1;
    wire uart,halted,trap,qbusy,qdone;
    wire [7:0] leds;
    wire [4:0] cause;
    wire [31:0] pc,result;
    wire scl_low,sda_low;
    reg target_scl_low=0,target_sda_low=0;
    wire scl=!(scl_low||target_scl_low), sda=!(sda_low||target_sda_low);
    reg [1:0] meta=3,sync_pins=3;
    always @(posedge clk) begin meta<={scl,sda}; sync_pins<=meta; end
    // Testbench loads the behavioral ROM at time 1 ns, before reset release.
    // Literal filenames work consistently in both Icarus and ModelSim.
    rv32_soc #(.CLOCK_HZ(1000000),.USE_ROM_INIT_FILE(0),
        .USE_QNN_INIT_FILES(1),.QNN_L1_SHIFT(`QNN_MODEL_L1_SHIFT),
        .QNN_L2_SHIFT(`QNN_MODEL_L2_SHIFT),.QNN_OUT_SHIFT(`QNN_MODEL_OUT_SHIFT),
        .QNN_L1_WEIGHT_FILE("../../../firmware/model/l1_weights.hex"),
        .QNN_L1_BIAS_FILE("../../../firmware/model/l1_biases.hex"),
        .QNN_L2_WEIGHT_FILE("../../../firmware/model/l2_weights.hex"),
        .QNN_L2_BIAS_FILE("../../../firmware/model/l2_biases.hex"),
        .QNN_OUT_WEIGHT_FILE("../../../firmware/model/out_weights.hex"),
        .QNN_OUT_BIAS_FILE("../../../firmware/model/out_bias.hex")) dut(
        .clk_i(clk),.rst_i(rst),.switches_i(10'b0),.leds_o(leds),.uart_tx_o(uart),.uart_rx_i(1'b1),
        .i2c_scl_i(sync_pins[1]),.i2c_sda_i(sync_pins[0]),
        .i2c_scl_drive_low_o(scl_low),.i2c_sda_drive_low_o(sda_low),
        .halted_o(halted),.trap_valid_o(trap),.trap_cause_o(cause),.trap_pc_o(pc),
        .qnn_busy_o(qbusy),.qnn_done_o(qdone),.qnn_result_o(result));
    reg [7:0] expected_features[0:479],expected_uart[0:127];
    reg [31:0] expected_results[0:5],expected_length[0:0];
    reg [23:0] bus_raw[0:24],current_raw[0:24],shunt_raw[0:24];
    integer feature_count=0,start_count=0,done_count=0,uart_count=0,cycles=0,bit_index;
    integer sample_index,poll_index,init_index;
    string error_message;
    reg done_previous=0;
    reg [7:0] received;
    reg [31:0] exit_code=32'hffffffff;
    initial begin
        #1;
        if(SENSOR_MODE==1) begin
            $readmemh("../../../tb/soc/firmware_assets/fake.hex",dut.u_rom.u_storage.mem);
            $readmemh("../../../tb/soc/firmware_assets/fake_features.hex",expected_features);
            $readmemh("../../../tb/soc/firmware_assets/fake_results.hex",expected_results);
            $readmemh("../../../tb/soc/firmware_assets/fake_uart.hex",expected_uart);
            $readmemh("../../../tb/soc/firmware_assets/fake_uart_length.hex",expected_length);
        end else begin
            $readmemh("../../../tb/soc/firmware_assets/ina228.hex",dut.u_rom.u_storage.mem);
            $readmemh("../../../tb/soc/firmware_assets/ina228_features.hex",expected_features);
            $readmemh("../../../tb/soc/firmware_assets/ina228_results.hex",expected_results);
            $readmemh("../../../tb/soc/firmware_assets/ina228_uart.hex",expected_uart);
            $readmemh("../../../tb/soc/firmware_assets/ina228_uart_length.hex",expected_length);
            $readmemh("../../../tb/soc/firmware_assets/bus_raw.hex",bus_raw);
            $readmemh("../../../tb/soc/firmware_assets/current_raw.hex",current_raw);
            $readmemh("../../../tb/soc/firmware_assets/shunt_raw.hex",shunt_raw);
        end
        if(FAULT_MODE!=0) begin
            if(FAULT_MODE<=3) error_message="SIM\nSENSOR_INIT_ERROR\n";
            else error_message="SIM\nSENSOR_ERROR\n";
            expected_length[0]=error_message.len();
            for(init_index=0;init_index<error_message.len();init_index=init_index+1)
                expected_uart[init_index]=error_message[init_index];
        end
        repeat(5) @(negedge clk); rst=0;
        while(!trap&&cycles<3000000) begin @(negedge clk); cycles=cycles+1; end
        if(!halted||!trap||cause!==3||pc!==32'h60) $fatal(1,"Firmware trap pc=%h cause=%d cycles=%d",pc,cause,cycles);
        repeat(20) @(negedge clk);
        if(FAULT_MODE==0) begin
            if(start_count!=6||done_count!=6||feature_count!=480||uart_count!=expected_length[0]||exit_code!==0)
                $fatal(1,"Firmware counts start=%d done=%d features=%d uart=%d exit=%h",start_count,done_count,feature_count,uart_count,exit_code);
        end else if(start_count||feature_count||exit_code!==1||uart_count!=expected_length[0])
            $fatal(1,"Sensor error incorrectly ran inference or failed to report");
        $display("PASS tb_rv32_firmware_e2e sensor=%0d fault=%0d cycles=%0d features=%0d results=%0d UART=%0d",SENSOR_MODE,FAULT_MODE,cycles,feature_count,done_count,uart_count);
        $finish;
    end
    always @(posedge clk) if(!rst) begin
        if(dut.u_core.retire_valid_o&&dut.u_core.retire_rd_we_o&&dut.u_core.retire_rd_addr_o==10)
            exit_code<=dut.u_core.retire_rd_data_o;
        if(dut.u_qnn.bus_req_i&&dut.u_qnn.bus_ready_o&&dut.u_qnn.bus_we_i) begin
            if(dut.u_qnn.bus_addr_i>=12'h100 && dut.u_qnn.bus_addr_i<12'h240) begin
                if(qbusy||feature_count>=480||dut.u_qnn.bus_addr_i!==(12'h100+4*(feature_count%80))||
                    dut.u_qnn.bus_wdata_i[7:0]!==expected_features[feature_count])
                    $fatal(1,"Feature order/value mismatch at %d",feature_count);
                feature_count<=feature_count+1;
            end else if(dut.u_qnn.bus_addr_i==0&&dut.u_qnn.bus_wdata_i[0]) begin
                if(qbusy||feature_count!=80*(start_count+1)) $fatal(1,"QNN start before full idle feature window");
                start_count<=start_count+1;
            end
        end
        if(qdone&&!done_previous) begin
            if(done_count>=6||result!==expected_results[done_count]) $fatal(1,"QNN golden mismatch result=%d index=%d",result,done_count);
            done_count<=done_count+1;
        end
        done_previous<=qdone;
    end
    initial forever begin
        @(negedge uart);
        if(!rst) begin
            repeat(13) @(posedge clk);
            for(bit_index=0;bit_index<8;bit_index=bit_index+1) begin
                received[bit_index]=uart;
                repeat(9) @(posedge clk);
            end
            if(uart!==1) $fatal(1,"UART stop bit");
            if(uart_count>=expected_length[0]||received!==expected_uart[uart_count])
                $fatal(1,"UART byte[%d]=%h expected=%h",uart_count,received,expected_uart[uart_count]);
            uart_count=uart_count+1;
        end
    end
    // Independent pin target: validates address, pointer, MSB-first data,
    // repeated START, final NACK and STOP. Never reads the I2C master's FSM.
    task wait_start;
        begin : waiting_start
            forever begin @(negedge sda); if(scl) disable waiting_start; end
        end
    endtask
    task wait_stop;
        begin : waiting_stop
            forever begin @(posedge sda); if(scl) disable waiting_stop; end
        end
    endtask
    task target_receive;
        input has_start;
        input [7:0] expected;
        input ack;
        integer b;
        reg [7:0] value;
        begin
            if(has_start) begin wait_start(); @(negedge scl); end
            for(b=7;b>=0;b=b-1) begin @(posedge scl); value[b]=sda; @(negedge scl); end
            if(value!==expected) $fatal(1,"INA228 target received %h expected %h",value,expected);
            target_sda_low=ack;
            @(posedge scl); @(negedge scl); target_sda_low=0;
        end
    endtask
    task target_transmit;
        input [7:0] value;
        input last;
        integer b;
        begin
            for(b=7;b>=0;b=b-1) begin
                target_sda_low=!value[b]; @(posedge scl); @(negedge scl);
            end
            target_sda_low=0;
            @(posedge scl);
            if(sda!==last) $fatal(1,"INA228 read ACK/NACK mismatch");
            @(negedge scl);
        end
    endtask
    task sensor_read;
        input [7:0] register_index;
        input [23:0] value;
        input integer bytes;
        begin
            target_receive(1,8'h80,1);
            target_receive(0,register_index,1);
            target_receive(1,8'h81,1);
            if(bytes==3) target_transmit(value[23:16],0);
            target_transmit(value[15:8],0);
            target_transmit(value[7:0],1);
            wait_stop();
        end
    endtask
    task sensor_write;
        input [7:0] register_index;
        input [15:0] value;
        begin
            target_receive(1,8'h80,1);
            target_receive(0,register_index,1);
            target_receive(0,value[15:8],1);
            target_receive(0,value[7:0],1);
            wait_stop();
        end
    endtask
    initial begin : ina_target
        if(SENSOR_MODE!=2) disable ina_target;
        if(FAULT_MODE==2) begin target_scl_low=1; disable ina_target; end
        wait(!rst);
        if(FAULT_MODE==1) begin target_receive(1,8'h80,0); disable ina_target; end
        sensor_read(8'h3e,FAULT_MODE==3 ? 24'h000000 : 24'h005449,2);
        if(FAULT_MODE==3) disable ina_target;
        sensor_read(8'h3f,24'h002281,2);
        sensor_write(8'h01,16'h0b68);
        sensor_write(8'h00,16'h0000);
        sensor_write(8'h02,16'h051e); // Test-only 10 mOhm, current LSB=10 uA.
        sensor_read(8'h00,24'h000000,2);
        sensor_read(8'h02,24'h00051e,2);
        sensor_read(8'h01,24'h000b68,2);
        for(sample_index=0;sample_index<25;sample_index=sample_index+1) begin
            sensor_read(8'h02,FAULT_MODE==7 ? 24'h000000 : 24'h00051e,2);
            if(FAULT_MODE==7) disable ina_target;
            sensor_read(8'h00,24'h000000,2);
            sensor_write(8'h01,16'h7b68);
            if(FAULT_MODE==4) begin
                for(poll_index=0;poll_index<128;poll_index=poll_index+1) sensor_read(8'h0b,24'h000001,2);
                disable ina_target;
            end
            sensor_read(8'h0b,FAULT_MODE==5 ? 24'h000203 : 24'h000001,2);
            if(FAULT_MODE==5) disable ina_target;
            sensor_read(8'h0b,24'h000003,2);
            if(FAULT_MODE==6) begin
                target_receive(1,8'h80,1); target_receive(0,8'h05,0); disable ina_target;
            end
            sensor_read(8'h05,bus_raw[sample_index],3);
            sensor_read(8'h07,current_raw[sample_index],3);
            sensor_read(8'h04,shunt_raw[sample_index],3);
            sensor_read(8'h06,24'h000c80,2); // 25 C die; unrelated simulated cell T.
        end
    end
endmodule
`default_nettype wire
