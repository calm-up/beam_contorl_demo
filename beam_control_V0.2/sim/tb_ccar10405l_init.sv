`timescale 1ns/1ps

module tb_ccar10405l_init;
    import beam_cmd_pkg::*;

    logic clk_i = 1'b0;
    logic rst_i = 1'b1;
    logic cmd_valid_i = 1'b0;
    logic [1:0] cmd_array_sel_i = ARRAY_RX;
    logic [7:0] cmd_line_mask_i = 8'h01;
    logic [ARRAY_FRAME_BITS-1:0] cmd_rx_frames_i = '0;
    logic [ARRAY_FRAME_BITS-1:0] cmd_tx_frames_i = '0;
    logic cmd_write_i = 1'b1;
    logic cmd_load_i = 1'b0;
    logic cmd_ready_o, busy_o, write_done_o, load_done_o, error_o, init_done_o;
    logic [31:0] rx_sdi_o, tx_sdi_o;
    logic [7:0] rx_clk_o, rx_csb_o, rx_ldb_o, rx_rstn_o;
    logic [7:0] tx_clk_o, tx_csb_o, tx_ldb_o, tx_rstn_o;
    logic [23:0] expected [0:512];
    logic [23:0] rx_word [0:1][0:3];
    logic [23:0] tx_word [0:1][0:3];
    logic [7:0] prev_rx_clk = '0, prev_tx_clk = '0;
    logic [7:0] prev_rx_csb = '1, prev_tx_csb = '1;
    integer rx_bits [0:1];
    integer tx_bits [0:1];
    integer rx_frames [0:1];
    integer tx_frames [0:1];
    integer reset_edges = 0;

    always #10 clk_i = ~clk_i;

    beam_ctrl_core #(
        .ENABLE_CHIP_INIT(1'b1), .CID_MAP(16'h3210),
        .SERIAL_HALF_PERIOD_CYCLES(1), .POST_FRAME_CLOCKS(2),
        .RESET_CLK_CYCLES(128), .POST_RESET_CYCLES(3),
        .CSB_TO_LDB_CYCLES(2), .LDB_LOW_CYCLES(2)
    ) dut (.*);

    initial begin
        $readmemh("ccar10405l_expected_frames.mem", expected);
        for (int lane = 0; lane < 2; lane++) begin
            rx_bits[lane] = 0;
            tx_bits[lane] = 0;
            rx_frames[lane] = 0;
            tx_frames[lane] = 0;
            for (int chip = 0; chip < 4; chip++) begin
                rx_word[lane][chip] = '0;
                tx_word[lane][chip] = '0;
            end
        end
        repeat (3) @(posedge clk_i);
        @(negedge clk_i) rst_i = 1'b0;
        wait (init_done_o);
        #2;
        if (reset_edges != 128 || !cmd_ready_o || busy_o)
            $fatal(1, "Reset or initialization completion failed");
        for (int lane = 0; lane < 2; lane++)
            if (rx_frames[lane] != 513 || tx_frames[lane] != 513)
                $fatal(1, "Incomplete table lane=%0d RX=%0d TX=%0d",
                       lane, rx_frames[lane], tx_frames[lane]);
        @(negedge clk_i);
        cmd_rx_frames_i[0 +: 24] = 24'h320500;
        cmd_valid_i = 1'b1;
        @(negedge clk_i) cmd_valid_i = 1'b0;
        wait (write_done_o);
        #2;
        if (!cmd_ready_o || error_o) $fatal(1, "Normal command rejected after init");
        $display("CCAR10405L_INIT_PASS 513 frames on all 4 chip lanes, RX/TX lines 0 and 7");
        $finish;
    end

    initial begin
        #2_000_000;
        $fatal(1, "Initialization timed out");
    end

    always @(posedge clk_i) begin
        #1;
        if (!prev_rx_clk[0] && rx_clk_o[0] && !rx_rstn_o[0])
            reset_edges++;
        if (!init_done_o && (cmd_ready_o || rx_ldb_o !== 8'hff || tx_ldb_o !== 8'hff))
            $fatal(1, "Command accepted or LDB pulsed during initialization");
        for (int lane = 0; lane < 2; lane++) begin
            int line;
            line = lane == 0 ? 0 : 7;
            if (!prev_rx_clk[line] && rx_clk_o[line] && !rx_csb_o[line]) begin
                rx_bits[lane]++;
                for (int chip = 0; chip < 4; chip++)
                    rx_word[lane][chip] = {rx_word[lane][chip][22:0],
                                           rx_sdi_o[line*4+chip]};
            end
            if (!prev_tx_clk[line] && tx_clk_o[line] && !tx_csb_o[line]) begin
                tx_bits[lane]++;
                for (int chip = 0; chip < 4; chip++)
                    tx_word[lane][chip] = {tx_word[lane][chip][22:0],
                                           tx_sdi_o[line*4+chip]};
            end
            if (!prev_rx_csb[line] && rx_csb_o[line] && rx_frames[lane] < 513) begin
                if (rx_bits[lane] != 24) $fatal(1, "RX bit count at frame %0d", rx_frames[lane]);
                for (int chip = 0; chip < 4; chip++)
                    if (rx_word[lane][chip] !== ({4'(chip), expected[rx_frames[lane]][19:0]}))
                        $fatal(1, "RX line %0d chip %0d frame %0d: got %h expected %h",
                               line, chip, rx_frames[lane], rx_word[lane][chip],
                               {4'(chip), expected[rx_frames[lane]][19:0]});
                rx_frames[lane]++;
                rx_bits[lane] = 0;
            end
            if (!prev_tx_csb[line] && tx_csb_o[line] && tx_frames[lane] < 513) begin
                if (tx_bits[lane] != 24) $fatal(1, "TX bit count at frame %0d", tx_frames[lane]);
                for (int chip = 0; chip < 4; chip++)
                    if (tx_word[lane][chip] !== ({4'(chip), expected[tx_frames[lane]][19:0]}))
                        $fatal(1, "TX line %0d chip %0d frame %0d: got %h expected %h",
                               line, chip, tx_frames[lane], tx_word[lane][chip],
                               {4'(chip), expected[tx_frames[lane]][19:0]});
                tx_frames[lane]++;
                tx_bits[lane] = 0;
            end
        end
        prev_rx_clk = rx_clk_o;
        prev_tx_clk = tx_clk_o;
        prev_rx_csb = rx_csb_o;
        prev_tx_csb = tx_csb_o;
    end
endmodule
