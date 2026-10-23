`timescale 1ns/1ps

module tb_protocol_v03_top;
    logic sys_clk_i = 0;
    always #10 sys_clk_i = ~sys_clk_i;
    logic rs422_rx_i = 1;
    wire rs422_tx_o;
    wire [31:0] rx_sdi_o, tx_sdi_o;
    wire [7:0] rx_clk_o, rx_csb_o, rx_ldb_o, rx_rstn_o, rx_t_o, rx_r_o;
    wire [7:0] tx_clk_o, tx_csb_o, tx_ldb_o, tx_rstn_o, tx_t_o, tx_r_o;
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
        repeat (1200) @(posedge sys_clk_i);
        if (!dut.core_init) $fatal(1,"power-on reset incomplete");
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
        if (response[8] != 1 || response[11] != 1 || response[12] != 0)
            $fatal(1,"status bytes wrong init=%h rx=%h tx=%h",
                   response[8],response[11],response[12]);

        payload = 0;
        payload[1*8 +: 8] = 2;
        payload[2*8 +: 8] = 1;
        payload[3*8 +: 8] = 1;
        payload[5*8 +: 8] = 1;
        payload[7*8 +: 8] = 8'hFF;
        payload[8*8 +: 8] = 2;
        exchange(8'hC0,0,9,payload,0,10);
        if (frame_count != 4 || captured_frame[3] !== 24'h2214D1)
            $fatal(1,"C0 arithmetic wrong: %h",captured_frame[3]);

        payload = 0;
        exchange(8'h20,0,10,payload,8'h05,10);

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
        exchange(8'hC0,0,9,payload,8'h07,10);

        payload = 0;
        send_request(8'hE0,8'hFF,0,payload,1);
        repeat (30) @(posedge sys_clk_i);
        if (rs422_tx_o !== 1'b1) $fatal(1,"bad checksum caused response");
        exchange(8'hE0,8'hFF,0,payload,0,15);
        $display("TB_V03_PASS 40 C0 00 E0 unsupported bad-checksum recovery");
        $finish;
    end
    initial begin
        #2_000_000;
        $fatal(1,"timeout");
    end
endmodule
