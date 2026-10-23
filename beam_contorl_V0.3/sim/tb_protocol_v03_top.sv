`timescale 1ns/1ps

module tb_protocol_v03_top;
    logic sys_clk_i = 0;
    always #10 sys_clk_i = ~sys_clk_i;
    logic rs422_rx_i = 1;
    wire rs422_tx_o;
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
    reg [23:0] captured_frame [0:15];
    integer frame_count = 0, bit_count = 0, load_count = 0, reset_edges = 0;
    reg [23:0] shift_frame = 0;
    beam_ctrl_top #(
        .SYS_CLK_HZ(1_000_000), .UART_BAUD(100_000),
        .POR_CYCLES(2), .SERIAL_HALF_PERIOD_CYCLES(2),
        .RESET_CLK_CYCLES(128), .POST_RESET_CYCLES(3),
        .CSB_TO_LDB_CYCLES(3), .LDB_LOW_CYCLES(2)
    ) dut (
        .sys_clk_i(sys_clk_i), .rx_sdo_i(8'b0), .tx_sdo_i(8'b0),
        .rs422_rx_i(rs422_rx_i), .rs422_tx_o(rs422_tx_o),
        .debug_rs485_rx_i(1'b1), .debug_rs485_tx_o(), .debug_rs485_dir_o(),
        .spare_rs485_rx_i(1'b1), .spare_rs485_tx_o(), .spare_rs485_dir_o(),
        .u22_cs_n_o(u22_cs_n), .u22_sck_o(u22_sck), .u22_mosi_o(u22_mosi),
        .u22_miso_i(u22_miso), .u22_wp_n_o(u22_wp_n),
        .u22_hold_n_o(u22_hold_n),
        .rx_sdi_o(rx_sdi_o), .rx_clk_o(rx_clk_o), .rx_csb_o(rx_csb_o),
        .rx_ldb_o(rx_ldb_o), .rx_rstn_o(rx_rstn_o), .rx_t_o(rx_t_o),
        .rx_r_o(rx_r_o), .tx_sdi_o(tx_sdi_o), .tx_clk_o(tx_clk_o),
        .tx_csb_o(tx_csb_o), .tx_ldb_o(tx_ldb_o), .tx_rstn_o(tx_rstn_o),
        .tx_t_o(tx_t_o), .tx_r_o(tx_r_o)
    );
    always @(negedge rx_csb_o[0]) begin bit_count = 0; shift_frame = 0; end
    always @(posedge rx_clk_o[0]) begin
        #1;
        if (!rx_rstn_o[0]) reset_edges = reset_edges + 1;
        if (!rx_csb_o[0] && bit_count < 24) begin
            shift_frame = {shift_frame[22:0],rx_sdi_o[2]};
            bit_count = bit_count + 1;
        end
    end
    always @(posedge rx_csb_o[0]) begin
        if (bit_count == 24) begin
            captured_frame[frame_count] = shift_frame;
            frame_count = frame_count + 1;
        end
    end
    always @(negedge rx_ldb_o[0]) load_count = load_count + 1;

    task automatic put_byte(input reg [7:0] value);
        integer bit_index;
        begin
            @(negedge sys_clk_i); rs422_rx_i = 0;
            repeat (10) @(negedge sys_clk_i);
            for (bit_index=0;bit_index<8;bit_index=bit_index+1) begin
                rs422_rx_i = value[bit_index];
                repeat (10) @(negedge sys_clk_i);
            end
            rs422_rx_i = 1;
            repeat (10) @(negedge sys_clk_i);
        end
    endtask
    task automatic send_request(input reg [7:0] command, input reg [7:0] array,
                                 input integer data_size, input reg [447:0] payload,
                                 input bit bad_checksum);
        reg [7:0] sum, length;
        integer i;
        begin
            length = data_size + 8;
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
            @(negedge rs422_tx_o);
            repeat (15) @(posedge sys_clk_i);
            for (i=0;i<8;i=i+1) begin
                value[i] = rs422_tx_o;
                repeat (10) @(posedge sys_clk_i);
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
        repeat (2000) @(posedge sys_clk_i);
        if (!dut.core_init) $fatal(1,"power-on reset incomplete");
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
        if (response[8] != 1 || response[9][1] != 1 ||
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
        exchange(8'h20,0,10,payload,8'h05,10);
        exchange(8'hA0,0,10,payload,8'h05,10);
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
        exchange(8'h00,0,2,payload,0,10);
        if (reset_edges != 128 || rx_r_o[0] != 0 || tx_rstn_o[0] != 1)
            $fatal(1,"target reset mismatch edges=%0d",reset_edges);

        payload = 0;
        payload[1*8 +: 8] = 2;
        payload[2*8 +: 8] = 1;
        payload[3*8 +: 8] = 1;
        payload[8*8 +: 8] = 2;
        exchange(8'hC0,0,9,payload,8'h00,10);

        payload = 0;
        send_request(8'hE0,8'hFF,0,payload,1);
        repeat (30) @(posedge sys_clk_i);
        if (rs422_tx_o !== 1'b1) $fatal(1,"bad checksum caused response");
        exchange(8'hE0,8'hFF,0,payload,0,15);
        $display("TB_V03_PASS 40 C0 00 E0 20 A0 F1 F2 F3 F5 removed-D0 checksum");
        $finish;
    end
    initial begin
        #80_000_000;
        $fatal(1,"timeout");
    end
endmodule
