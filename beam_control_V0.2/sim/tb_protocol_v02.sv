`timescale 1ns/1ps

module tb_protocol_v02;
    localparam int unsigned UART_BAUD_TEST = 5_000_000;
    localparam int unsigned BIT_CYCLES = 10;

    logic sys_clk_i = 1'b0;
    logic [7:0] rx_sdo_i = '0, tx_sdo_i = '0;
    logic rs422_rx_i = 1'b1;
    logic debug_rs485_rx_i = 1'b1, spare_rs485_rx_i = 1'b1;
    wire rs422_tx_o, debug_rs485_tx_o, debug_rs485_dir_o;
    wire spare_rs485_tx_o, spare_rs485_dir_o;
    wire [31:0] rx_sdi_o, tx_sdi_o;
    wire [7:0] rx_clk_o, rx_csb_o, rx_ldb_o, rx_rstn_o, rx_t_o, rx_r_o;
    wire [7:0] tx_clk_o, tx_csb_o, tx_ldb_o, tx_rstn_o, tx_t_o, tx_r_o;

    logic previous_rx_clk = 1'b0;
    logic previous_tx_clk = 1'b0;
    logic [23:0] captured [0:1][0:3];
    logic [23:0] captured_tx [0:1][0:3];
    integer sample_count = 0;
    integer frame_count = 0;
    integer tx_sample_count = 0;
    integer tx_frame_count = 0;
    integer ldb_count = 0;
    integer chip;

    always #10 sys_clk_i = ~sys_clk_i;

    beam_ctrl_top #(
        .ENABLE_PROTOCOL_V02(1'b1),
        .SYS_CLK_HZ(50_000_000), .UART_BAUD(UART_BAUD_TEST),
        .POR_CYCLES(2), .SERIAL_HALF_PERIOD_CYCLES(1),
        .POST_FRAME_CLOCKS(2), .RESET_CLK_CYCLES(4),
        .POST_RESET_CYCLES(2), .CSB_TO_LDB_CYCLES(2),
        .LDB_LOW_CYCLES(2), .CHIP_CID_MAP(16'h3210)
    ) dut (.*);

    always @(posedge sys_clk_i) begin
        #1;
        if (!previous_rx_clk && rx_clk_o[0] && !rx_csb_o[0]) begin
            for (chip = 0; chip < 4; chip = chip + 1)
                captured[frame_count][chip] =
                    {captured[frame_count][chip][22:0], rx_sdi_o[chip]};
            sample_count = sample_count + 1;
            if (sample_count == 24) begin
                sample_count = 0;
                frame_count = frame_count + 1;
            end
        end
        if (!rx_ldb_o[0]) ldb_count = ldb_count + 1;
        previous_rx_clk = rx_clk_o[0];

        if (!previous_tx_clk && tx_clk_o[1] && !tx_csb_o[1]) begin
            for (chip = 0; chip < 4; chip = chip + 1)
                captured_tx[tx_frame_count][chip] =
                    {captured_tx[tx_frame_count][chip][22:0], tx_sdi_o[4+chip]};
            tx_sample_count = tx_sample_count + 1;
            if (tx_sample_count == 24) begin
                tx_sample_count = 0;
                tx_frame_count = tx_frame_count + 1;
            end
        end
        previous_tx_clk = tx_clk_o[1];
    end

    task automatic uart_send_byte(input logic [7:0] value);
        integer b;
        begin
            rs422_rx_i = 1'b0;
            repeat (BIT_CYCLES) @(posedge sys_clk_i);
            for (b = 0; b < 8; b = b + 1) begin
                rs422_rx_i = value[b];
                repeat (BIT_CYCLES) @(posedge sys_clk_i);
            end
            rs422_rx_i = 1'b1;
            repeat (BIT_CYCLES) @(posedge sys_clk_i);
        end
    endtask

    task automatic send_tx_example;
        begin
            uart_send_byte(8'hAA);
            uart_send_byte(8'h01); // TX array
            uart_send_byte(8'h01); // line 1
            uart_send_byte(8'h01); // SDI2 / chip index 1
            uart_send_byte(8'h03); // local channel 3
            uart_send_byte(8'h01); // enable
            uart_send_byte(8'h05); // phase code
            uart_send_byte(8'h06); // attenuation code
            uart_send_byte(8'h12); // sum of bytes 1..7
            uart_send_byte(8'h55);
        end
    endtask

    task automatic send_rx_example(input logic [7:0] checksum);
        begin
            uart_send_byte(8'hAA);
            uart_send_byte(8'h00); // RX array
            uart_send_byte(8'h00); // line 0
            uart_send_byte(8'h02); // SDI3 / chip index 2
            uart_send_byte(8'h01); // local channel 1
            uart_send_byte(8'h01); // enable
            uart_send_byte(8'h10); // 90 degrees
            uart_send_byte(8'h14); // 10 dB
            uart_send_byte(checksum);
            uart_send_byte(8'h55);
        end
    endtask

    initial begin
        for (integer f = 0; f < 2; f = f + 1)
            for (integer c = 0; c < 4; c = c + 1) begin
                captured[f][c] = '0;
                captured_tx[f][c] = '0;
            end

        wait (dut.core_init_done);
        repeat (5) @(posedge sys_clk_i);
        if (rs422_tx_o !== 1'b1) $fatal(1, "RS422 TX is not at UART idle");

        // Bad checksum must not start a transaction.
        send_rx_example(8'h29);
        repeat (20) @(posedge sys_clk_i);
        if (dut.protocol_rejected_count != 1 || dut.protocol_accepted_count != 0)
            $fatal(1, "Bad checksum was not rejected");

        send_rx_example(8'h28);
        wait (dut.protocol_done);
        #1;
        if (frame_count != 2 || sample_count != 0 || ldb_count == 0)
            $fatal(1, "V0.2 did not execute two writes and an LDB pulse");

        if (captured[0][0] !== 24'h080000 ||
            captured[0][1] !== 24'h180000 ||
            captured[0][2] !== 24'h200002 ||
            captured[0][3] !== 24'h380000)
            $fatal(1, "Per-chip enable frames are incorrect");
        if (captured[1][0] !== 24'h080000 ||
            captured[1][1] !== 24'h180000 ||
            captured[1][2] !== 24'h221510 ||
            captured[1][3] !== 24'h380000)
            $fatal(1, "RX target/filler amplitude-phase frames are incorrect");
        if (rx_r_o !== 8'h01 || rx_t_o !== 0 || tx_t_o !== 0 || tx_r_o !== 0)
            $fatal(1, "RX line enable state is incorrect");
        if (dut.protocol_accepted_count != 1 || dut.protocol_completed_count != 1 ||
            dut.protocol_rejected_count != 1)
            $fatal(1, "V0.2 status counters are incorrect");

        send_tx_example();
        wait (dut.protocol_done);
        #1;
        if (tx_frame_count != 2 || tx_sample_count != 0)
            $fatal(1, "TX V0.2 did not execute two writes");
        if (captured_tx[0][0] !== 24'h080000 ||
            captured_tx[0][1] !== 24'h100008 ||
            captured_tx[0][2] !== 24'h280000 ||
            captured_tx[0][3] !== 24'h380000)
            $fatal(1, "TX per-chip enable frames are incorrect");
        if (captured_tx[1][0] !== 24'h080000 ||
            captured_tx[1][1] !== 24'h113185 ||
            captured_tx[1][2] !== 24'h280000 ||
            captured_tx[1][3] !== 24'h380000)
            $fatal(1, "TX target/filler amplitude-phase frames are incorrect");
        if (rx_r_o !== 8'h01 || tx_t_o !== 8'h02 || rx_t_o !== 0 || tx_r_o !== 0)
            $fatal(1, "Separate RX/TX line enable state is incorrect");
        if (dut.protocol_accepted_count != 2 || dut.protocol_completed_count != 2 ||
            dut.protocol_rejected_count != 1)
            $fatal(1, "V0.2 RX/TX status counters are incorrect");

        $display("PROTOCOL_V02_PASS");
        $finish;
    end
endmodule
