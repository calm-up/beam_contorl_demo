`timescale 1ns/1ps

import beam_cmd_pkg::*;

// VIO-facing staging adapter. Slow human/JTAG actions are converted into the
// same valid/ready command interface used by future upstream protocols.
module debug_command_adapter (
    input  logic                        clk_i,
    input  logic                        rst_i,
    input  logic                        dbg_frame_we_i,
    input  logic [1:0]                  dbg_frame_array_sel_i,
    input  logic [2:0]                  dbg_line_index_i,
    input  logic [1:0]                  dbg_chip_index_i,
    input  logic [23:0]                 dbg_frame_data_i,
    input  logic                        dbg_submit_toggle_i,
    input  logic [1:0]                  dbg_cmd_array_sel_i,
    input  logic [7:0]                  dbg_cmd_line_mask_i,
    input  logic                        dbg_cmd_write_i,
    input  logic                        dbg_cmd_load_i,
    input  logic                        dbg_clear_status_i,

    output logic                        dbg_ack_toggle_o,
    output logic                        dbg_pending_o,
    output logic                        dbg_error_sticky_o,
    output logic [15:0]                 dbg_write_done_count_o,
    output logic [15:0]                 dbg_load_done_count_o,

    output logic                        cmd_valid_o,
    input  logic                        cmd_ready_i,
    output logic [1:0]                  cmd_array_sel_o,
    output logic [7:0]                  cmd_line_mask_o,
    output logic [ARRAY_FRAME_BITS-1:0] cmd_rx_frames_o,
    output logic [ARRAY_FRAME_BITS-1:0] cmd_tx_frames_o,
    output logic                        cmd_write_o,
    output logic                        cmd_load_o,
    input  logic                        core_write_done_i,
    input  logic                        core_load_done_i,
    input  logic                        core_error_i
);

    logic previous_frame_we_q;
    logic previous_clear_q;
    logic pending_toggle_q;
    integer frame_base;

    assign dbg_pending_o = cmd_valid_o;

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            previous_frame_we_q   <= 1'b0;
            previous_clear_q      <= 1'b0;
            pending_toggle_q      <= 1'b0;
            dbg_ack_toggle_o      <= 1'b0;
            dbg_error_sticky_o    <= 1'b0;
            dbg_write_done_count_o <= '0;
            dbg_load_done_count_o  <= '0;
            cmd_valid_o           <= 1'b0;
            cmd_array_sel_o       <= ARRAY_NONE;
            cmd_line_mask_o       <= '0;
            cmd_rx_frames_o       <= '0;
            cmd_tx_frames_o       <= '0;
            cmd_write_o           <= 1'b0;
            cmd_load_o            <= 1'b0;
        end else begin
            previous_frame_we_q <= dbg_frame_we_i;
            previous_clear_q    <= dbg_clear_status_i;

            if (dbg_clear_status_i && !previous_clear_q) begin
                dbg_error_sticky_o     <= 1'b0;
                dbg_write_done_count_o <= '0;
                dbg_load_done_count_o  <= '0;
            end else begin
                if (core_error_i) begin
                    dbg_error_sticky_o <= 1'b1;
                end
                if (core_write_done_i) begin
                    dbg_write_done_count_o <= dbg_write_done_count_o + 1'b1;
                end
                if (core_load_done_i) begin
                    dbg_load_done_count_o <= dbg_load_done_count_o + 1'b1;
                end
            end

            // Rising-edge detection prevents a held VIO level from repeatedly
            // modifying the staging memory.
            if (dbg_frame_we_i && !previous_frame_we_q) begin
                if (cmd_valid_o || dbg_frame_array_sel_i == ARRAY_NONE) begin
                    dbg_error_sticky_o <= 1'b1;
                end else begin
                    frame_base = frame_lsb(dbg_line_index_i, dbg_chip_index_i);
                    if (dbg_frame_array_sel_i[0]) begin
                        cmd_rx_frames_o[frame_base +: FRAME_BITS] <= dbg_frame_data_i;
                    end
                    if (dbg_frame_array_sel_i[1]) begin
                        cmd_tx_frames_o[frame_base +: FRAME_BITS] <= dbg_frame_data_i;
                    end
                end
            end

            if (!cmd_valid_o && (dbg_submit_toggle_i != dbg_ack_toggle_o)) begin
                cmd_array_sel_o  <= dbg_cmd_array_sel_i;
                cmd_line_mask_o  <= dbg_cmd_line_mask_i;
                cmd_write_o      <= dbg_cmd_write_i;
                cmd_load_o       <= dbg_cmd_load_i;
                pending_toggle_q <= dbg_submit_toggle_i;
                cmd_valid_o      <= 1'b1;
            end else if (cmd_valid_o) begin
                if (dbg_submit_toggle_i != pending_toggle_q) begin
                    dbg_error_sticky_o <= 1'b1;
                end
                if (cmd_ready_i) begin
                    cmd_valid_o      <= 1'b0;
                    dbg_ack_toggle_o <= pending_toggle_q;
                end
            end
        end
    end

endmodule
