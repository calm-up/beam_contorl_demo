`timescale 1ns/1ps

module tb_protocol_v03_top #(
    parameter bit BOARD_TIMING = 1'b1
);
    localparam int TB_CLK_HZ = BOARD_TIMING ? 50_000_000 : 1_000_000;
    localparam int TB_BAUD = BOARD_TIMING ? 115_200 : 100_000;
    localparam int UART_BIT_CYCLES = TB_CLK_HZ / TB_BAUD;
    bit capture_commands = 0;
    integer startup_frames = 0;
    // UART integration regression, not the hardware top. Select THIS module
    // as simulation top. Default BOARD_TIMING=1 matches s53 hardware timing.
    // BOARD_TIMING=0 retains the legacy accelerated regression.
    // mock_sdo is a supplied response, not a validated physical chip model.
    logic [7:0] active_command = 0;
    logic sys_clk_i = 0;
    always #10 sys_clk_i = ~sys_clk_i;
    logic debug_rx_i = 1;
    wire debug_tx_o;
    wire rs422_tx_o;
    logic spare_rx_i = 1;
    wire spare_tx_o;
    bit use_spare = 0;
    wire [31:0] rx_sdi_o, tx_sdi_o;
    wire [7:0] rx_clk_o, rx_csb_o, rx_ldb_o, rx_rstn_o, rx_t_o, rx_r_o;
    wire [7:0] tx_clk_o, tx_csb_o, tx_ldb_o, tx_rstn_o, tx_t_o, tx_r_o;
    wire u22_cs_n, u22_sck, u22_mosi, u22_wp_n, u22_hold_n;
    localparam logic [23:0] MOCK_ID = 24'h20BA18;
    integer u22_edges = 0;
    reg [7:0] u22_opcode = 0, u22_command_shift = 0;
    reg [23:0] u22_addr = 0, u22_addr_shift = 0;
    reg [7:0] u22_data_shift = 0;
    reg u22_write_enable = 0;
    reg [7:0] u22_memory [0:16383];
    function automatic integer mock_index(input reg [23:0] a);
        begin
            mock_index = (a[23] || a[20:12] != 0) ? -1 :
                         (a[22:21] * 4096 + a[11:0]);
        end
    endfunction
    integer mi;
    initial for (mi=0;mi<16384;mi=mi+1) u22_memory[mi] = 8'hFF;
    wire [23:0] u22_read_addr = u22_addr + ((u22_edges-40)/8);
    wire [7:0] u22_read_byte = mock_index(u22_read_addr) >= 0 ?
        u22_memory[mock_index(u22_read_addr)] : 8'hFF;
    wire u22_miso = u22_cs_n ? 1'b1 :
                    (u22_opcode == 8'h9F && u22_edges >= 8 && u22_edges < 32) ?
                        MOCK_ID[31-u22_edges] :
                    (u22_opcode == 8'h05 && u22_edges >= 8 && u22_edges < 16) ? 1'b0 :
                    (u22_opcode == 8'h0B && u22_edges >= 40) ?
                        u22_read_byte[7-((u22_edges-40)%8)] : 1'b1;
    always @(negedge u22_cs_n) begin
        u22_edges <= 0;
        u22_opcode <= 0;
        u22_command_shift <= 0;
        u22_addr <= 0;
        u22_addr_shift <= 0;
        u22_data_shift <= 0;
    end
    always @(posedge u22_sck) if (!u22_cs_n) begin
        if (u22_edges < 8) begin
            u22_command_shift <= {u22_command_shift[6:0],u22_mosi};
            if (u22_edges == 7) u22_opcode <= {u22_command_shift[6:0],u22_mosi};
        end else if (u22_edges >= 8 && u22_edges < 32 &&
                     (u22_opcode == 8'h0B || u22_opcode == 8'h02 || u22_opcode == 8'hD8)) begin
            u22_addr_shift <= {u22_addr_shift[22:0],u22_mosi};
            if (u22_edges == 31) u22_addr <= {u22_addr_shift[22:0],u22_mosi};
        end else if (u22_opcode == 8'h02 && u22_edges >= 32) begin
            u22_data_shift <= {u22_data_shift[6:0],u22_mosi};
            if (u22_edges % 8 == 7 && u22_write_enable &&
                mock_index(u22_addr + ((u22_edges-32)/8)) >= 0)
                u22_memory[mock_index(u22_addr + ((u22_edges-32)/8))] <=
                    u22_memory[mock_index(u22_addr + ((u22_edges-32)/8))] &
                    {u22_data_shift[6:0],u22_mosi};
        end
        u22_edges <= u22_edges + 1;
    end
    always @(posedge u22_cs_n) begin
        if (u22_opcode == 8'h06) u22_write_enable <= 1;
        if (u22_opcode == 8'h02) u22_write_enable <= 0;
        if (u22_opcode == 8'hD8 && u22_write_enable) begin
            if (mock_index(u22_addr) >= 0)
                for (integer k=0;k<4096;k=k+1)
                    u22_memory[(u22_addr[22:21] * 4096)+k] <= 8'hFF;
            u22_write_enable <= 0;
        end
    end
    reg [7:0] response [0:14];
    reg [23:0] captured_frame [0:31];
    reg [23:0] captured_line7 [0:15];
    integer frame_count = 0, bit_count = 0, load_count = 0, reset_edges = 0;
    integer line7_frame_count = 0, line7_bit_count = 0;
    integer sdo_bit_index = -1;
    logic sdo_bit_q = 1'b0;
    logic [23:0] mock_sdo = 24'h2C0C08;
    reg [23:0] shift_frame = 0;
    reg [23:0] shift_line7 = 0;
    beam_ctrl_top #(
        .SYS_CLK_HZ(TB_CLK_HZ), .UART_BAUD(TB_BAUD),
        .ENABLE_CHIP_INIT(BOARD_TIMING),
        .POR_CYCLES(BOARD_TIMING ? 4 : 2), .SERIAL_HALF_PERIOD_CYCLES(BOARD_TIMING ? 5 : 2),
        .RESET_CLK_CYCLES(128), .POST_RESET_CYCLES(BOARD_TIMING ? 10 : 3),
        .CSB_TO_LDB_CYCLES(BOARD_TIMING ? 10 : 3), .LDB_LOW_CYCLES(BOARD_TIMING ? 5 : 2)
    ) dut (
        .sys_clk_i(sys_clk_i), .rx_sdo_i({7'b0,sdo_bit_q}), .tx_sdo_i(8'b0),
        .rs422_rx_i(1'b1), .rs422_tx_o(rs422_tx_o),
        .sync_clk_i(1'b0), .wavefront_i(1'b0), .beam_apply_i(1'b0),
        .external_t_i(1'b0), .external_r_i(1'b0),
        .debug_rs485_rx_i(debug_rx_i), .debug_rs485_tx_o(debug_tx_o), .debug_rs485_dir_o(),
        .spare_rs485_rx_i(spare_rx_i), .spare_rs485_tx_o(spare_tx_o), .spare_rs485_dir_o(),
        .u22_cs_n_o(u22_cs_n), .u22_sck_o(u22_sck), .u22_mosi_o(u22_mosi),
        .u22_miso_i(u22_miso), .u22_wp_n_o(u22_wp_n),
        .u22_hold_n_o(u22_hold_n),
        .rx_sdi_o(rx_sdi_o), .rx_clk_o(rx_clk_o), .rx_csb_o(rx_csb_o),
        .rx_ldb_o(rx_ldb_o), .rx_rstn_o(rx_rstn_o), .rx_t_o(rx_t_o),
        .rx_r_o(rx_r_o), .tx_sdi_o(tx_sdi_o), .tx_clk_o(tx_clk_o),
        .tx_csb_o(tx_csb_o), .tx_ldb_o(tx_ldb_o), .tx_rstn_o(tx_rstn_o),
        .tx_t_o(tx_t_o), .tx_r_o(tx_r_o)
    );
    if (BOARD_TIMING) begin : g_board_timing
        tb_s53_pin_timing rx_timing(rx_clk_o[0], rx_csb_o[0], rx_ldb_o[0], rx_rstn_o[0]);
        tb_s53_pin_timing tx_timing(tx_clk_o[0], tx_csb_o[0], tx_ldb_o[0], tx_rstn_o[0]);
        for (genvar n=0;n<8;n++) begin : g_continuous
            tb_continuous_sclk rx_clock(sys_clk_i, dut.por_done_q, rx_clk_o[n]);
            tb_continuous_sclk tx_clock(sys_clk_i, dut.por_done_q, tx_clk_o[n]);
        end
    end
    always @(negedge rx_csb_o[0]) begin
        bit_count = 0;
        shift_frame = 0;
        sdo_bit_index = 23;
        sdo_bit_q = 1'b0;
        #1;
        if (capture_commands && dut.u_channel.batch_mode_q && rx_csb_o !== 8'h00)
            $fatal(1,"batch CSB is not parallel: %h",rx_csb_o);
    end
    always @(negedge rx_clk_o[0]) begin
        // A free-running clock also falls while CSB is idle. Only shift an
        // answer after a selected data rising edge; skip the CSB-assert edge.
        #2;
        if (!rx_csb_o[0] && bit_count > 0 && sdo_bit_index >= 0) begin
            sdo_bit_q <= #25 mock_sdo[sdo_bit_index];
            sdo_bit_index = sdo_bit_index - 1;
        end
    end
    always @(posedge rx_clk_o[0]) begin
        #1;
        if (!rx_rstn_o[0]) reset_edges = reset_edges + 1;
        if (!rx_csb_o[0] && bit_count < 24) begin
            shift_frame = {shift_frame[22:0],rx_sdi_o[2]};
            bit_count = bit_count + 1;
        end
    end
    always @(posedge rx_csb_o[0]) begin
        if (!capture_commands && bit_count == 24) startup_frames = startup_frames + 1;
        if (capture_commands && bit_count == 24) begin
            if (frame_count >= 32) $fatal(1,"command capture overflow");
            captured_frame[frame_count] = shift_frame;
            frame_count = frame_count + 1;
        end
    end
    always @(negedge rx_ldb_o[0]) load_count = load_count + 1;
    always @(negedge rx_csb_o[7]) begin line7_bit_count = 0; shift_line7 = 0; end
    always @(posedge rx_clk_o[7]) begin
        #1;
        if (!rx_csb_o[7] && line7_bit_count < 24) begin
            shift_line7 = {shift_line7[22:0],rx_sdi_o[30]};
            line7_bit_count = line7_bit_count + 1;
        end
    end
    always @(posedge rx_csb_o[7]) begin
        if (capture_commands && line7_bit_count == 24) begin
            captured_line7[line7_frame_count] = shift_line7;
            line7_frame_count = line7_frame_count + 1;
        end
    end

    // Observe every selected physical SDI lane for single-chip 40/C0.
    // Batch 20/A0 and read 41 intentionally have different lane policies.
    integer p1_rx_frames = 0, p1_tx_frames = 0;
    integer all_spi_frames = 0, all_load_pulses = 0;
    for (genvar ln=0;ln<8;ln++) begin : g_p1_check
        always @(posedge rx_csb_o[ln]) if (capture_commands) all_spi_frames++;
        always @(posedge tx_csb_o[ln]) if (capture_commands) all_spi_frames++;
        always @(negedge rx_ldb_o[ln]) if (capture_commands) all_load_pulses++;
        always @(negedge tx_ldb_o[ln]) if (capture_commands) all_load_pulses++;
        always @(posedge rx_clk_o[ln]) begin
            #2;
            if (capture_commands && !rx_csb_o[ln] &&
                (active_command==8'h40 || active_command==8'hC0)) begin
                if (rx_sdi_o[ln*4+:4] !== {4{rx_sdi_o[ln*4]}})
                    $fatal(1,"P1 RX line%0d SDIs differ: %b",ln,rx_sdi_o[ln*4+:4]);
            end
        end
        always @(posedge tx_clk_o[ln]) begin
            #2;
            if (capture_commands && !tx_csb_o[ln] &&
                (active_command==8'h40 || active_command==8'hC0)) begin
                if (tx_sdi_o[ln*4+:4] !== {4{tx_sdi_o[ln*4]}})
                    $fatal(1,"P1 TX line%0d SDIs differ: %b",ln,tx_sdi_o[ln*4+:4]);
            end
        end
    end
    always @(posedge rx_csb_o[0]) if (capture_commands && bit_count==24 &&
        (active_command==8'h40 || active_command==8'hC0)) p1_rx_frames++;
    always @(posedge tx_csb_o[0]) if (capture_commands &&
        (active_command==8'h40 || active_command==8'hC0)) p1_tx_frames++;

    task automatic put_byte(input reg [7:0] value);
        integer bit_index;
        begin
            @(negedge sys_clk_i);
            if (use_spare) spare_rx_i = 0; else debug_rx_i = 0;
            repeat (UART_BIT_CYCLES) @(negedge sys_clk_i);
            for (bit_index=0;bit_index<8;bit_index=bit_index+1) begin
                if (use_spare) spare_rx_i = value[bit_index];
                else debug_rx_i = value[bit_index];
                repeat (UART_BIT_CYCLES) @(negedge sys_clk_i);
            end
            if (use_spare) spare_rx_i = 1; else debug_rx_i = 1;
            repeat (UART_BIT_CYCLES) @(negedge sys_clk_i);
        end
    endtask
    task automatic send_request(input reg [7:0] command, input reg [7:0] array,
                                 input integer data_size, input reg [447:0] payload,
                                 input bit bad_checksum);
        reg [7:0] sum, length;
        integer i;
        begin
            length = data_size + 8;
            active_command = command;
            $display("UART_REQUEST t=%0t cmd=%02h array=%02h bytes=%0d bad_checksum=%0b",
                     $time, command, array, data_size+8, bad_checksum);
            sum = 8'h01 + length + command + array;
            put_byte(8'hAA); put_byte(8'hDD); put_byte(8'h01);
            put_byte(length); put_byte(command); put_byte(array);
            for (i=0;i<data_size;i=i+1) begin
                put_byte(payload[i*8 +: 8]);
                sum = sum + payload[i*8 +: 8];
            end
            put_byte(bad_checksum ? sum ^ 8'h01 : sum);
            put_byte(8'h55);
        end
    endtask
    task automatic read_byte(output reg [7:0] value);
        integer i;
        begin
            if (use_spare) @(negedge spare_tx_o);
            else @(negedge debug_tx_o);
            repeat (UART_BIT_CYCLES + UART_BIT_CYCLES/2) @(posedge sys_clk_i);
            for (i=0;i<8;i=i+1) begin
                value[i] = use_spare ? spare_tx_o : debug_tx_o;
                repeat (UART_BIT_CYCLES) @(posedge sys_clk_i);
            end
        end
    endtask
    task automatic read_response(input reg [7:0] command,
                                 input reg [7:0] array,
                                 input reg [7:0] expected_status,
                                 input integer length);
        reg [7:0] sum;
        integer i;
        begin
            for (i=0;i<length;i=i+1) read_byte(response[i]);
            if (response[0] !== 8'hAA || response[1] !== 8'hDD ||
                response[2] !== 8'h01 || response[3] !== length ||
                response[4] !== 8'h7F || response[5] !== array ||
                response[6] !== command || response[7] !== expected_status ||
                response[length-1] !== 8'h55)
                $fatal(1,"response fields wrong cmd=%h status=%h",response[6],response[7]);
            sum = 0;
            for (i=2;i<length-2;i=i+1) sum = sum + response[i];
            if (response[length-2] !== sum) $fatal(1,"response checksum wrong");
            $display("UART_RESPONSE t=%0t cmd=%02h status=%02h PASS",
                     $time, command, response[7]);
        end
    endtask
    task automatic exchange(input reg [7:0] command, input reg [7:0] array,
                            input integer data_size, input reg [447:0] payload,
                            input reg [7:0] status, input integer length);
        begin
            fork
                send_request(command,array,data_size,payload,0);
                read_response(command,array,status,length);
            join
            repeat (20) @(posedge sys_clk_i);
        end
    endtask
    initial begin : main
        reg [447:0] payload;
        integer frames_before_reject;
        integer loads_before_reject;
        integer all_frames_before_reject, all_loads_before_reject;
        $display("TIMING_CONFIG board=%0b clock=50MHz uart_div=%0d spi_half=%0d ldb_cycles=%0d init=%0b",
                 BOARD_TIMING, UART_BIT_CYCLES, dut.SERIAL_HALF_PERIOD_CYCLES,
                 dut.LDB_LOW_CYCLES, BOARD_TIMING);
        wait (dut.core_init === 1'b1 && dut.flash_probe_done === 1'b1);
        repeat (20) @(negedge sys_clk_i);
        if (BOARD_TIMING && startup_frames != 512)
            $fatal(1,"startup initialization frame count=%0d expected=512",startup_frames);
        $display("STARTUP_READY t=%0t frames=%0d",$time,startup_frames);
        capture_commands = 1;
        if (!dut.core_init) $fatal(1,"power-on reset incomplete");
        if (dut.rx_gate != 0 || dut.tx_gate != 0 ||
            dut.rx_pulse_mode != 0 || dut.tx_pulse_mode != 0 ||
            rx_r_o != 0 || tx_t_o != 0 ||
            rx_csb_o !== 8'hFF || tx_csb_o !== 8'hFF ||
            rx_ldb_o !== 8'hFF || tx_ldb_o !== 8'hFF)
            $fatal(1,"power-on RF safety state failed");
        if (!dut.flash_probe_done || dut.flash_jedec_id !== MOCK_ID)
            $fatal(1,"U22 JEDEC probe failed: %h",dut.flash_jedec_id);
        reset_edges = 0;

        payload = 0;
        payload[0*8 +: 8] = 0;   // J1
        payload[1*8 +: 8] = 2;   // SDI3
        payload[2*8 +: 8] = 1;   // channel 1
        payload[3*8 +: 8] = 1;   // on
        payload[5*8 +: 8] = 8'h10;
        payload[7*8 +: 8] = 8'h14;
        payload[10*8 +: 8] = 8'h02;
        exchange(8'h40,8'h00,15,payload,8'h00,10);
        if (frame_count != 2 || captured_frame[1] !== 24'h221510 || load_count != 1)
            $fatal(1,"SDI/LDB mismatch frames=%0d target=%h loads=%0d",
                   frame_count,captured_frame[1],load_count);
        if (rx_r_o[0] !== 1'b1 || tx_t_o != 0 || rx_r_o[7:1] != 0)
            $fatal(1,"RX gate wrong");

        payload = 0;
        exchange(8'hE0,8'hFF,0,payload,8'h00,15);
        if (response[8] != 3 || response[9][1] != 1 ||
            response[10][1] != 1 || response[11] != 1 || response[12] != 0)
            $fatal(1,"status bytes wrong init=%h rx=%h tx=%h",
                   response[8],response[11],response[12]);

        payload = 0;
        payload[1*8 +: 8] = 2;
        payload[2*8 +: 8] = 1;
        payload[3*8 +: 8] = 1;
        payload[5*8 +: 8] = 8'h11;
        payload[7*8 +: 8] = 8'h15;
        payload[8*8 +: 8] = 2;
        exchange(8'hC0,0,9,payload,0,10);
        if (frame_count != 4 || captured_frame[3] !== 24'h221551)
            $fatal(1,"C0 selected-position overwrite wrong: %h",captured_frame[3]);

        payload = 0;
        payload[3*8 +: 8] = 1;
        payload[4*8 +: 8] = 3;
        payload[6*8 +: 8] = 63;
        payload[10*8 +: 8] = 1;
        exchange(8'h40,1,15,payload,0,10);
        if (tx_t_o[0] !== 1'b1 || rx_r_o[0] !== 1'b1)
            $fatal(1,"TX/RX gate failed tx=%b rx=%b modes=%h/%h enables=%b/%b gates=%b/%b pulses=%b/%b resetbusy=%b",
                   tx_t_o[0],rx_r_o[0],dut.tx_pulse_mode,dut.rx_pulse_mode,
                   dut.channel_tx_enable[0],dut.channel_rx_enable[0],dut.tx_gate[0],dut.rx_gate[0],
                   dut.pulse_tx_active,dut.pulse_rx_active,dut.target_reset_busy);

        payload = 0;
        payload[0*8 +: 8] = 8'h06; // 1600 in 10 MHz units
        payload[1*8 +: 8] = 8'h40;
        payload[2*8 +: 8] = 8'h0B; // azimuth 30.00 degrees
        payload[3*8 +: 8] = 8'hB8;
        payload[4*8 +: 8] = 8'h05; // elevation 15.00 degrees
        payload[5*8 +: 8] = 8'hDC;
        payload[8*8 +: 8] = 8'h02;
        exchange(8'h20,0,10,payload,8'h00,10);
        if (frame_count != 9 || line7_frame_count != 5 || load_count != 6 ||
            captured_frame[4] !== 24'h20000F ||
            captured_line7[0] !== 24'h20000F ||
            captured_frame[5] !== 24'h22003A ||
            dut.channel_rx_enable !== 8'hFF ||
            // Photo: chip0 at right. DXF mid4: RF4,RF3,RF1,RF2 left-to-right.
            // chip0/RF1 x=62.4mm; RF2 x=72mm; chip3/RF4 x=-72mm.
            dut.beam_phase[0 +: 6] !== 6'd59 ||
            dut.beam_phase[6 +: 6] !== 6'd44 ||
            dut.beam_phase[2*6 +: 6] !== 6'd11 ||
            dut.beam_phase[3*6 +: 6] !== 6'd27 ||
            dut.beam_phase[127*6 +: 6] !== 6'd20)
            $fatal(1,"20 full-array batch failed frames=%0d loads=%0d f4=%h f5=%h en=%h",
                   frame_count,load_count,captured_frame[4],captured_frame[5],dut.channel_rx_enable);
        payload = 0;
        payload[0*8 +: 8] = 8'h81; // lines 0 and 7
        payload[1*8 +: 8] = 8'h04; // chip 2
        payload[2*8 +: 8] = 8'h02; // channel 1
        payload[3*8 +: 8] = 8'h06;
        payload[4*8 +: 8] = 8'h40;
        payload[5*8 +: 8] = 8'hF4; // azimuth -30.00 degrees
        payload[6*8 +: 8] = 8'h48;
        payload[7*8 +: 8] = 8'h05;
        payload[8*8 +: 8] = 8'hDC;
        payload[9*8 +: 8] = 8'h02;
        exchange(8'hA0,0,10,payload,8'h00,10);
        if (frame_count != 14 || line7_frame_count != 10 || load_count != 10 ||
            captured_frame[9] !== 24'h200002 ||
            captured_line7[5] !== 24'h200002 ||
            dut.channel_rx_enable !== 8'h81 ||
            dut.u_channel.enable_mem_q[0 +: 128] !== (128'h1 << 9 | 128'h1 << 121) ||
            dut.beam_phase[9*6 +: 6] !== 6'd26 ||
            dut.beam_phase[121*6 +: 6] !== 6'd22)
            $fatal(1,"A0 Cartesian selection failed frames=%0d loads=%0d f9=%h en=%h",
                   frame_count,load_count,captured_frame[9],dut.channel_rx_enable);
        payload[3*8 +: 8] = 0;
        payload[4*8 +: 8] = 0;
        exchange(8'hA0,0,10,payload,8'h03,10);
        payload = 0;
        payload[0*8 +: 8] = 8'h06;
        payload[1*8 +: 8] = 8'h40;
        payload[6*8 +: 8] = 1;
        frames_before_reject = frame_count;
        loads_before_reject = load_count;
        exchange(8'h20,0,10,payload,8'h05,10);
        if (frame_count != frames_before_reject || load_count != loads_before_reject)
            $fatal(1,"unsupported mode changed RF frames or LDB");
        exchange(8'hD0,0,2,payload,8'h05,10); // removed command

        // F1/F2 use the BJN110 byte positions inside a V0.3 envelope.
        payload = 0;
        payload[10*8 +: 8] = 8'hA5;
        payload[11*8 +: 8] = 8'h5A;
        exchange(8'hF1,0,12,payload,8'h00,10);
        payload = 0;
        payload[7*8 +: 8] = 8'h10;
        exchange(8'hF2,0,12,payload,8'h00,10);
        exchange(8'hF2,0,12,payload,8'h06,10); // NOR slot is no longer blank
        payload[4*8 +: 8] = 1;
        payload[7*8 +: 8] = 8'h11;
        exchange(8'hF2,0,12,payload,8'h00,10);
        payload = 0;
        exchange(8'hF3,0,1,payload,8'h00,15);
        if (dut.flash_loaded_count != 2) $fatal(1,"F3 should see two records");
        payload[10*8 +: 8] = 8'hA5;
        payload[11*8 +: 8] = 8'h5A;
        exchange(8'hF1,0,12,payload,8'h00,10);
        payload = 0;
        exchange(8'hF3,0,1,payload,8'h00,15);
        if (dut.flash_loaded_count != 0) $fatal(1,"F1 did not erase whole 64-KiB sector");
        payload[7*8 +: 8] = 8'h10;
        exchange(8'hF2,0,12,payload,8'h00,10);
        payload = 0;
        payload[0 +: 8] = 8'h11;
        exchange(8'hF2,0,12,payload,8'h00,10);
        payload[0 +: 8] = 8'h12;
        exchange(8'hF2,0,12,payload,8'h00,10);
        payload[0 +: 8] = 8'h13;
        exchange(8'hF2,0,12,payload,8'h00,10);
        payload = 0;
        exchange(8'hF3,0,1,payload,8'h00,15);
        if (dut.flash_loaded_count != 1 || response[8] != 1 ||
            response[9] != 0 || response[10] != 8'h4A ||
            response[11] != 8'hFF || response[12] != 8'hA5)
            $fatal(1,"F3 did not reload one ordinary record");
        payload = 0;
        payload[0 +: 8] = 8'hA5;
        payload[8 +: 8] = 8'h5A;
        exchange(8'hF5,0,2,payload,8'h00,10);
        if (u22_memory[0] != 8'hFF || u22_memory[4096] != 8'hFF ||
            u22_memory[8192] != 8'hFF || u22_memory[12288] != 8'hFF)
            $fatal(1,"F5 did not clear U22 protocol partitions");
        payload = 0;
        exchange(8'hF5,0,2,payload,8'h03,10);

        payload = 0;
        payload[0 +: 8] = 1;
        capture_commands = 0; // full reinitialization is not a command capture
        exchange(8'h00,0,2,payload,0,10);
        if (reset_edges != 128 || rx_r_o[0] != 0 || tx_rstn_o[0] != 1)
            $fatal(1,"target reset mismatch edges=%0d",reset_edges);

        wait (dut.core_init === 1'b1);
        repeat (20) @(negedge sys_clk_i);
        capture_commands = 1;
        payload = 0;
        payload[1*8 +: 8] = 2;
        payload[2*8 +: 8] = 1;
        payload[3*8 +: 8] = 1;
        payload[8*8 +: 8] = 2;
        exchange(8'hC0,0,9,payload,8'h00,10);

        payload = 0;
        send_request(8'hE0,8'hFF,0,payload,1);
        repeat (30) @(posedge sys_clk_i);
        if (debug_tx_o !== 1'b1) $fatal(1,"bad checksum caused response");
        exchange(8'hE0,8'hFF,0,payload,0,15);
        use_spare = 1;
        exchange(8'hE0,8'hFF,0,payload,0,15);
        use_spare = 0;
        if (rs422_tx_o !== 1'b1) $fatal(1,"reserved RS422 transmitted data");
        payload = 0;
        payload[1*8 +: 8] = 2; // chip CID 2
        payload[2*8 +: 8] = 4; // control register
        payload[3*8 +: 8] = 12;
        frames_before_reject = frame_count;
        exchange(8'h41,0,4,payload,0,15);
        if (frame_count != frames_before_reject + 2 ||
            captured_frame[frames_before_reject] !== 24'h2C0C00 ||
            captured_frame[frames_before_reject+1] !== 24'h280000 ||
            response[8] !== 0 || response[9] !== 2 ||
            response[10] !== 8'h08 || response[11] !== 8'h0C ||
            response[12] !== 8'h2C)
            $fatal(1,"41 SDO pipeline read mismatch");
        mock_sdo = 24'h2A17C0;
        payload[2*8 +: 8] = 2;
        payload[3*8 +: 8] = 1;
        frames_before_reject = frame_count;
        exchange(8'h41,0,4,payload,0,15);
        if (captured_frame[frames_before_reject] !== 24'h2A1000 ||
            response[10] !== 8'hC0 || response[11] !== 8'h17 || response[12] !== 8'h2A)
            $fatal(1,"41 dynamic RX read mismatch");
        payload[2*8 +: 8] = 4;
        payload[3*8 +: 8] = 12;
        mock_sdo = 24'hFFFFFF;
        exchange(8'h41,0,4,payload,8'h06,10);
        // Retired commands must take the unsupported-command path and must
        // not produce any SPI frame or LDB on any RX/TX line.
        all_frames_before_reject = all_spi_frames;
        all_loads_before_reject = all_load_pulses;
        payload = 0;
        payload[1*8 +: 8] = 2;
        payload[2*8 +: 8] = 8'h22;
        payload[4*8 +: 8] = 8'h40;
        exchange(8'h42,0,5,payload,8'h05,10);
        exchange(8'h42,1,5,payload,8'h05,10);
        payload = 0;
        exchange(8'h43,0,1,payload,8'h05,10);
        exchange(8'h43,1,1,payload,8'h05,10);
        if (all_spi_frames != all_frames_before_reject || all_load_pulses != all_loads_before_reject)
            $fatal(1,"removed 42/43 still caused SPI or LDB activity");
        $display("REMOVED_42_43_PASS RX/TX status=05 no SPI frames or LDB; SCLK remains continuous");
        if (p1_rx_frames < 6 || p1_tx_frames < 2)
            $fatal(1,"P1 checks did not cover RX/TX paths rx=%0d tx=%0d",p1_rx_frames,p1_tx_frames);
        $display("P1_LANE_POLICY_PASS RX_frames=%0d TX_frames=%0d; 40/C0 all four SDIs identical",p1_rx_frames,p1_tx_frames);
        $display("TB_V03_PASS dual-RS485 41-SDO 40 C0 00 E0 20 A0 F1 F2 F3 F5 removed-D0/42/43 checksum");
        $finish;
    end
    initial begin
        #500_000_000;
        $fatal(1,"timeout");
    end
endmodule

// Check generated FPGA pin timing; this is not a chip functional model.
module tb_s53_pin_timing(input wire sclk, csb, ldb, rstn);
    realtime all_rise = 0, all_fall = 0;
    realtime previous_rise = 0, last_fall = 0, cs_rise = 0, load_fall = 0;
    integer edges = 0, post_edges = 0;
    bit frame_seen = 0, frame_active = 0, load_active = 0;
    // Reset clocks are a separate phase, not part of a write transaction.
    always @(negedge rstn) begin
        frame_seen = 0; frame_active = 0; post_edges = 0;
        all_rise = 0; all_fall = 0;
    end
    always @(negedge csb) if (rstn === 1'b1) begin
        if (frame_seen && post_edges < 2) $fatal(1,"%m missing post-frame clocks");
        frame_active = 1;
        all_rise = 0; all_fall = 0;
        edges = 0;
        previous_rise = 0;
    end
    always @(posedge sclk) if (rstn === 1'b1) begin
        if (frame_active || (frame_seen && post_edges < 2)) begin
            if (all_rise != 0 && $realtime-all_rise != 200.0)
                $fatal(1,"%m nonperiodic SCLK rising edges");
            if (all_fall != 0 && $realtime-all_fall != 100.0)
                $fatal(1,"%m nonperiodic SCLK low width");
            all_rise = $realtime;
        end
        if (csb === 1'b0 && frame_active) begin
            if (edges > 0 && $realtime - previous_rise != 200.0)
                $fatal(1,"%m SPI period is not 200ns");
            previous_rise = $realtime;
            edges = edges + 1;
        end else if (frame_seen) post_edges = post_edges + 1;
    end
    always @(negedge sclk) if (rstn === 1'b1 && all_rise != 0 && (frame_active || post_edges <= 2)) begin
        if ($realtime-all_rise != 100.0) $fatal(1,"%m nonperiodic SCLK high width");
        all_fall = $realtime;
    end
    always @(negedge sclk) if (frame_active && csb === 1'b0) begin
        if ($realtime - previous_rise != 100.0)
            $fatal(1,"%m SPI high time is not 100ns");
        last_fall = $realtime;
    end
    always @(posedge csb) if (frame_active) begin
        if (edges != 24) $fatal(1,"%m SPI frame does not have 24 clocks: %0d",edges);
        if ($realtime - last_fall != 80.0)
            $fatal(1,"%m final CS hold is not 80ns");
        cs_rise = $realtime;
        post_edges = 0;
        frame_seen = 1;
        frame_active = 0;
    end
    always @(negedge ldb) if (rstn === 1'b1) begin
        if (csb !== 1'b1 || post_edges < 2 || $realtime - cs_rise < 200.0)
            $fatal(1,"%m LDB guard/post clocks invalid");
        load_fall = $realtime;
        load_active = 1;
        $display("BOARD_LDB %m t=%0t CS_to_LDB_ns=%0.0f",$time,$realtime-cs_rise);
    end
    always @(posedge ldb) if (load_active) begin
        if ($realtime - load_fall != 100.0)
            $fatal(1,"%m LDB low time is not 100ns");
        load_active = 0;
    end
endmodule

// Intentionally spans idle, UART receive/transmit, LDB and runtime reset.
// A clock that stops produces a fatal within 120ns, not only when it resumes.
module tb_continuous_sclk(input wire sysclk, enabled, sclk);
    realtime last_edge=0;
    bit seen=0;
    integer edges=0;
    always @(sclk) if (enabled) begin
        if (seen && $realtime-last_edge != 100.0)
            $fatal(1,"%m noncontinuous SCLK half-period=%0.0fns",$realtime-last_edge);
        last_edge=$realtime;
        seen=1;
        edges++;
    end
    always @(posedge sysclk) if (enabled && seen && $realtime-last_edge>120.0)
        $fatal(1,"%m SCLK stopped");
endmodule
