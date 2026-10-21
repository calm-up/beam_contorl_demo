`timescale 1ns/1ps

import beam_cmd_pkg::*;

module tb_debug_command_adapter;
    logic clk_i = 1'b0;
    logic rst_i = 1'b1;
    logic dbg_frame_we_i = 1'b0;
    logic [1:0] dbg_frame_array_sel_i = ARRAY_NONE;
    logic [2:0] dbg_line_index_i = '0;
    logic [1:0] dbg_chip_index_i = '0;
    logic [23:0] dbg_frame_data_i = '0;
    logic dbg_submit_toggle_i = 1'b0;
    logic [1:0] dbg_cmd_array_sel_i = ARRAY_NONE;
    logic [7:0] dbg_cmd_line_mask_i = '0;
    logic dbg_cmd_write_i = 1'b0;
    logic dbg_cmd_load_i = 1'b0;
    logic dbg_clear_status_i = 1'b0;
    logic cmd_ready_i = 1'b0;
    logic core_write_done_i = 1'b0;
    logic core_load_done_i = 1'b0;
    logic core_error_i = 1'b0;

    logic dbg_ack_toggle_o, dbg_pending_o, dbg_error_sticky_o;
    logic [15:0] dbg_write_done_count_o, dbg_load_done_count_o;
    logic cmd_valid_o, cmd_write_o, cmd_load_o;
    logic [1:0] cmd_array_sel_o;
    logic [7:0] cmd_line_mask_o;
    logic [ARRAY_FRAME_BITS-1:0] cmd_rx_frames_o, cmd_tx_frames_o;

    always #5 clk_i = ~clk_i;

    debug_command_adapter dut (.*);

    task automatic pulse_frame_write;
        input logic [1:0] array_sel;
        input logic [2:0] line_index;
        input logic [1:0] chip_index;
        input logic [23:0] frame_data;
        begin
            @(negedge clk_i);
            dbg_frame_array_sel_i = array_sel;
            dbg_line_index_i = line_index;
            dbg_chip_index_i = chip_index;
            dbg_frame_data_i = frame_data;
            dbg_frame_we_i = 1'b1;
            // Deliberately hold high: only the rising edge may write once.
            repeat (3) @(negedge clk_i);
            dbg_frame_we_i = 1'b0;
        end
    endtask

    task automatic pulse_status;
        input integer which_status;
        begin
            @(negedge clk_i);
            case (which_status)
                0: core_write_done_i = 1'b1;
                1: core_load_done_i  = 1'b1;
                2: core_error_i      = 1'b1;
            endcase
            @(negedge clk_i);
            core_write_done_i = 1'b0;
            core_load_done_i  = 1'b0;
            core_error_i      = 1'b0;
        end
    endtask

    initial begin
        repeat (4) @(posedge clk_i);
        rst_i = 1'b0;
        repeat (2) @(posedge clk_i);

        pulse_frame_write(ARRAY_RX, 3'd2, 2'd3, 24'hA5_23_3C);
        if (cmd_rx_frames_o[frame_lsb(3'd2, 2'd3) +: FRAME_BITS] !== 24'hA5_23_3C)
            $fatal(1, "RX staging frame write failed");
        if (cmd_tx_frames_o !== '0)
            $fatal(1, "RX staging write modified TX frames");

        @(negedge clk_i);
        dbg_cmd_array_sel_i = ARRAY_RX;
        dbg_cmd_line_mask_i = 8'h04;
        dbg_cmd_write_i = 1'b1;
        dbg_submit_toggle_i = 1'b1;
        @(posedge clk_i); #1;
        if (!cmd_valid_o || !dbg_pending_o || dbg_ack_toggle_o)
            $fatal(1, "submit toggle did not create a pending command");

        // VIO controls may move while pending; accepted command must remain stable.
        @(negedge clk_i);
        dbg_cmd_array_sel_i = ARRAY_TX;
        dbg_cmd_line_mask_i = 8'h80;
        dbg_cmd_write_i = 1'b0;
        dbg_cmd_load_i = 1'b1;
        repeat (2) @(posedge clk_i);
        if (cmd_array_sel_o !== ARRAY_RX || cmd_line_mask_o !== 8'h04 ||
            !cmd_write_o || cmd_load_o)
            $fatal(1, "pending command changed before ready");

        // A frame write while pending is rejected and does not change the buffer.
        pulse_frame_write(ARRAY_RX, 3'd2, 2'd3, 24'h00_00_00);
        if (cmd_rx_frames_o[frame_lsb(3'd2, 2'd3) +: FRAME_BITS] !== 24'hA5_23_3C)
            $fatal(1, "pending frame buffer was modified");
        if (!dbg_error_sticky_o)
            $fatal(1, "pending frame write did not set sticky error");

        @(negedge clk_i);
        cmd_ready_i = 1'b1;
        @(posedge clk_i); #1;
        if (cmd_valid_o || dbg_pending_o || dbg_ack_toggle_o !== 1'b1)
            $fatal(1, "ready handshake did not acknowledge exactly one command");
        @(negedge clk_i);
        cmd_ready_i = 1'b0;
        repeat (3) @(posedge clk_i);
        if (cmd_valid_o)
            $fatal(1, "held submit toggle retriggered a command");

        pulse_status(0);
        pulse_status(1);
        pulse_status(1);
        if (dbg_write_done_count_o !== 16'd1 || dbg_load_done_count_o !== 16'd2)
            $fatal(1, "completion counters are incorrect");

        @(negedge clk_i);
        dbg_clear_status_i = 1'b1;
        repeat (2) @(negedge clk_i);
        dbg_clear_status_i = 1'b0;
        @(posedge clk_i); #1;
        if (dbg_error_sticky_o || dbg_write_done_count_o != 0 ||
            dbg_load_done_count_o != 0)
            $fatal(1, "status clear failed");

        pulse_status(2);
        if (!dbg_error_sticky_o)
            $fatal(1, "core error was not latched");

        $display("DEBUG_COMMAND_ADAPTER_PASS");
        $finish;
    end
endmodule
