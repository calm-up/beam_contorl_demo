`timescale 1ns/1ps

module tb_beam_ctrl_core;
    import beam_cmd_pkg::*;

    localparam int unsigned RESET_CLOCKS = 128;
    localparam int unsigned POST_CLOCKS  = 2;

    logic clk_i = 1'b0;
    logic rst_i = 1'b1;
    logic cmd_valid_i = 1'b0;
    logic cmd_ready_o;
    logic [1:0] cmd_array_sel_i = ARRAY_NONE;
    logic [7:0] cmd_line_mask_i = 8'h00;
    logic [767:0] cmd_rx_frames_i = '0;
    logic [767:0] cmd_tx_frames_i = '0;
    logic cmd_write_i = 1'b0;
    logic cmd_load_i = 1'b0;
    logic busy_o, write_done_o, load_done_o, error_o, init_done_o;
    logic [31:0] rx_sdi_o, tx_sdi_o;
    logic [7:0] rx_clk_o, rx_csb_o, rx_ldb_o, rx_rstn_o;
    logic [7:0] tx_clk_o, tx_csb_o, tx_ldb_o, tx_rstn_o;

    logic monitor_write = 1'b0;
    logic [1:0] monitor_array_sel = ARRAY_NONE;
    logic [7:0] monitor_line_mask = '0;
    logic [7:0] previous_rx_clk = '0;
    logic [7:0] previous_tx_clk = '0;
    logic [23:0] rx_captured [0:7][0:3];
    logic [23:0] tx_captured [0:7][0:3];
    integer rx_sample_count [0:7];
    integer tx_sample_count [0:7];
    integer rx_post_count [0:7];
    integer tx_post_count [0:7];
    integer reset_rx_edges = 0;
    integer reset_tx_edges = 0;
    integer line_index;
    integer chip_index;

    always #10 clk_i = ~clk_i;

    beam_ctrl_core #(
        .SERIAL_HALF_PERIOD_CYCLES(1),
        .POST_FRAME_CLOCKS(POST_CLOCKS),
        .RESET_CLK_CYCLES(RESET_CLOCKS),
        .POST_RESET_CYCLES(3),
        .CSB_TO_LDB_CYCLES(2),
        .LDB_LOW_CYCLES(2)
    ) dut (.*);

    // Sample every physical rising edge after registered outputs settle.
    always @(posedge clk_i) begin
        #1;
        if (!init_done_o) begin
            if ((rx_clk_o != tx_clk_o) || rx_csb_o !== 8'hff || tx_csb_o !== 8'hff ||
                rx_ldb_o !== 8'hff || tx_ldb_o !== 8'hff ||
                rx_sdi_o !== 32'b0 || tx_sdi_o !== 32'b0) begin
                $fatal(1, "Unsafe output detected during array reset");
            end
            if ((|rx_clk_o) && (rx_rstn_o !== 8'b0 || tx_rstn_o !== 8'b0)) begin
                $fatal(1, "RSTN was released while reset clocks were active");
            end
        end

        if (!previous_rx_clk[0] && rx_clk_o[0] && !rx_rstn_o[0]) begin
            reset_rx_edges = reset_rx_edges + 1;
        end
        if (!previous_tx_clk[0] && tx_clk_o[0] && !tx_rstn_o[0]) begin
            reset_tx_edges = reset_tx_edges + 1;
        end

        if (monitor_write) begin
            for (line_index = 0; line_index < 8; line_index = line_index + 1) begin
                if (!previous_rx_clk[line_index] && rx_clk_o[line_index]) begin
                    if (!rx_csb_o[line_index]) begin
                        rx_sample_count[line_index] = rx_sample_count[line_index] + 1;
                        for (chip_index = 0; chip_index < 4; chip_index = chip_index + 1) begin
                            rx_captured[line_index][chip_index] = {
                                rx_captured[line_index][chip_index][22:0],
                                rx_sdi_o[line_index*4 + chip_index]
                            };
                        end
                    end else if (monitor_array_sel[0] && monitor_line_mask[line_index]) begin
                        rx_post_count[line_index] = rx_post_count[line_index] + 1;
                    end
                end
                if (!previous_tx_clk[line_index] && tx_clk_o[line_index]) begin
                    if (!tx_csb_o[line_index]) begin
                        tx_sample_count[line_index] = tx_sample_count[line_index] + 1;
                        for (chip_index = 0; chip_index < 4; chip_index = chip_index + 1) begin
                            tx_captured[line_index][chip_index] = {
                                tx_captured[line_index][chip_index][22:0],
                                tx_sdi_o[line_index*4 + chip_index]
                            };
                        end
                    end else if (monitor_array_sel[1] && monitor_line_mask[line_index]) begin
                        tx_post_count[line_index] = tx_post_count[line_index] + 1;
                    end
                end
            end
            if ((rx_ldb_o !== 8'hff) || (tx_ldb_o !== 8'hff)) begin
                $fatal(1, "A write command caused an automatic LDB load");
            end
        end

        previous_rx_clk = rx_clk_o;
        previous_tx_clk = tx_clk_o;
    end

    task automatic fill_frames(input logic [23:0] rx_seed,
                               input logic [23:0] tx_seed);
        begin
            for (line_index = 0; line_index < 8; line_index = line_index + 1) begin
                for (chip_index = 0; chip_index < 4; chip_index = chip_index + 1) begin
                    cmd_rx_frames_i[frame_lsb(line_index, chip_index) +: 24] =
                        rx_seed ^ (line_index << 8) ^ chip_index;
                    cmd_tx_frames_i[frame_lsb(line_index, chip_index) +: 24] =
                        tx_seed ^ (line_index << 8) ^ chip_index;
                end
            end
        end
    endtask

    task automatic clear_write_monitor(input logic [1:0] array_sel,
                                       input logic [7:0] line_mask);
        begin
            monitor_array_sel = array_sel;
            monitor_line_mask = line_mask;
            for (line_index = 0; line_index < 8; line_index = line_index + 1) begin
                rx_sample_count[line_index] = 0;
                tx_sample_count[line_index] = 0;
                rx_post_count[line_index] = 0;
                tx_post_count[line_index] = 0;
                for (chip_index = 0; chip_index < 4; chip_index = chip_index + 1) begin
                    rx_captured[line_index][chip_index] = '0;
                    tx_captured[line_index][chip_index] = '0;
                end
            end
        end
    endtask

    task automatic submit_command(input logic [1:0] array_sel,
                                  input logic [7:0] line_mask,
                                  input logic do_write,
                                  input logic do_load);
        begin
            wait (cmd_ready_o);
            @(negedge clk_i);
            cmd_array_sel_i = array_sel;
            cmd_line_mask_i = line_mask;
            cmd_write_i = do_write;
            cmd_load_i = do_load;
            cmd_valid_i = 1'b1;
            @(negedge clk_i);
            cmd_valid_i = 1'b0;
        end
    endtask

    task automatic verify_write(input logic [1:0] array_sel,
                                input logic [7:0] line_mask);
        begin
            for (line_index = 0; line_index < 8; line_index = line_index + 1) begin
                if (array_sel[0] && line_mask[line_index]) begin
                    if (rx_sample_count[line_index] != 24 ||
                        rx_post_count[line_index] != POST_CLOCKS) begin
                        $fatal(1, "RX line %0d edge count mismatch: data=%0d post=%0d",
                               line_index, rx_sample_count[line_index], rx_post_count[line_index]);
                    end
                    for (chip_index = 0; chip_index < 4; chip_index = chip_index + 1) begin
                        if (rx_captured[line_index][chip_index] !==
                            cmd_rx_frames_i[frame_lsb(line_index, chip_index) +: 24]) begin
                            $fatal(1, "RX route/frame mismatch line %0d chip %0d",
                                   line_index, chip_index);
                        end
                    end
                end else if (rx_sample_count[line_index] != 0 || rx_post_count[line_index] != 0) begin
                    $fatal(1, "Non-target RX line %0d toggled", line_index);
                end

                if (array_sel[1] && line_mask[line_index]) begin
                    if (tx_sample_count[line_index] != 24 ||
                        tx_post_count[line_index] != POST_CLOCKS) begin
                        $fatal(1, "TX line %0d edge count mismatch: data=%0d post=%0d",
                               line_index, tx_sample_count[line_index], tx_post_count[line_index]);
                    end
                    for (chip_index = 0; chip_index < 4; chip_index = chip_index + 1) begin
                        if (tx_captured[line_index][chip_index] !==
                            cmd_tx_frames_i[frame_lsb(line_index, chip_index) +: 24]) begin
                            $fatal(1, "TX route/frame mismatch line %0d chip %0d",
                                   line_index, chip_index);
                        end
                    end
                end else if (tx_sample_count[line_index] != 0 || tx_post_count[line_index] != 0) begin
                    $fatal(1, "Non-target TX line %0d toggled", line_index);
                end
            end
        end
    endtask

    task automatic run_write(input logic [1:0] array_sel,
                             input logic [7:0] line_mask,
                             input logic inject_busy_request);
        begin
            @(negedge clk_i);
            clear_write_monitor(array_sel, line_mask);
            monitor_write = 1'b1;
            submit_command(array_sel, line_mask, 1'b1, 1'b0);
            wait (busy_o);
            if (cmd_ready_o) $fatal(1, "cmd_ready remained high while busy");

            if (inject_busy_request) begin
                @(negedge clk_i);
                cmd_array_sel_i = ARRAY_RX;
                cmd_line_mask_i = 8'h01;
                cmd_write_i = 1'b0;
                cmd_load_i = 1'b1;
                cmd_valid_i = 1'b1;
                @(negedge clk_i);
                cmd_valid_i = 1'b0;
            end

            wait (write_done_o);
            #1;
            monitor_write = 1'b0;
            verify_write(array_sel, line_mask);
            if (busy_o || !cmd_ready_o || error_o || load_done_o ||
                rx_clk_o !== 8'b0 || tx_clk_o !== 8'b0 ||
                rx_csb_o !== 8'hff || tx_csb_o !== 8'hff) begin
                $fatal(1, "Write completion/idle handshake is incorrect");
            end
        end
    endtask

    task automatic run_load(input logic [1:0] array_sel,
                            input logic [7:0] line_mask);
        begin
            submit_command(array_sel, line_mask, 1'b0, 1'b1);
            wait (busy_o);
            if (array_sel[0]) begin
                while (rx_ldb_o != ~line_mask) @(posedge clk_i);
            end else begin
                while (tx_ldb_o != ~line_mask) @(posedge clk_i);
            end
            #1;
            if ((array_sel[0] && rx_ldb_o !== ~line_mask) ||
                (!array_sel[0] && rx_ldb_o !== 8'hff) ||
                (array_sel[1] && tx_ldb_o !== ~line_mask) ||
                (!array_sel[1] && tx_ldb_o !== 8'hff) ||
                rx_csb_o !== 8'hff || tx_csb_o !== 8'hff ||
                rx_clk_o !== 8'b0 || tx_clk_o !== 8'b0) begin
                $fatal(1, "LDB array/line routing is incorrect");
            end
            wait (load_done_o);
            #1;
            if (busy_o || !cmd_ready_o || rx_ldb_o !== 8'hff || tx_ldb_o !== 8'hff) begin
                $fatal(1, "Load completion/idle handshake is incorrect");
            end
        end
    endtask

    task automatic run_invalid(input logic [1:0] array_sel,
                               input logic [7:0] line_mask,
                               input logic do_write,
                               input logic do_load);
        begin
            submit_command(array_sel, line_mask, do_write, do_load);
            #1;
            if (!error_o || busy_o || write_done_o || load_done_o) begin
                $fatal(1, "Illegal command response is incorrect");
            end
            @(posedge clk_i);
            #1;
            if (error_o) $fatal(1, "error_o was not a one-cycle pulse");
        end
    endtask

    initial begin
        repeat (3) @(posedge clk_i);
        @(negedge clk_i);
        rst_i = 1'b0;

        wait (init_done_o);
        #1;
        if (reset_rx_edges != RESET_CLOCKS || reset_tx_edges != RESET_CLOCKS) begin
            $fatal(1, "Reset clock count mismatch: RX=%0d TX=%0d",
                   reset_rx_edges, reset_tx_edges);
        end
        if (!cmd_ready_o || busy_o || rx_rstn_o !== 8'hff || tx_rstn_o !== 8'hff ||
            rx_clk_o !== 8'b0 || tx_clk_o !== 8'b0) begin
            $fatal(1, "Core did not enter ready state after reset");
        end

        fill_frames(24'h810001, 24'h420002);
        run_write(ARRAY_RX, 8'hff, 1'b1);
        fill_frames(24'h930003, 24'h640004);
        run_write(ARRAY_TX, 8'hff, 1'b0);
        fill_frames(24'hA50005, 24'h560006);
        run_write(ARRAY_RX, 8'h08, 1'b0);
        fill_frames(24'hB70007, 24'h680008);
        run_write(ARRAY_BOTH, 8'hA5, 1'b0);

        // Back-to-back accepted commands after each prior done pulse.
        fill_frames(24'hC90009, 24'h7A000A);
        run_write(ARRAY_TX, 8'h03, 1'b0);
        fill_frames(24'hDB000B, 24'h8C000C);
        run_write(ARRAY_TX, 8'h03, 1'b0);

        run_load(ARRAY_RX, 8'hA5);
        run_load(ARRAY_BOTH, 8'h5A);

        run_invalid(ARRAY_NONE, 8'h01, 1'b1, 1'b0);
        run_invalid(ARRAY_RX, 8'h00, 1'b1, 1'b0);
        run_invalid(ARRAY_TX, 8'h01, 1'b1, 1'b1);
        run_invalid(ARRAY_TX, 8'h01, 1'b0, 1'b0);

        $display("STEP7_RESET_PASS");
        $display("STEP8_ROUTING_AND_COMMAND_PASS");
        $display("STEP9_SYSTEM_TEST_PASS");
        $finish;
    end

endmodule
