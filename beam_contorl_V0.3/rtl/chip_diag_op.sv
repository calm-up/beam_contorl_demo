`timescale 1ns/1ps
import beam_cmd_pkg::*;

// Debug-only single-frame write or independent LDB operation.
module chip_diag_op #(
    parameter logic [15:0] CID_MAP = 16'h3210
) (
    input logic clk_i, rst_i, start_i, load_i, array_i,
    input logic [2:0] line_i,
    input logic [1:0] chip_i,
    input logic [23:0] frame_i,
    input logic core_ready_i, core_write_done_i, core_load_done_i, core_error_i,
    output logic core_valid_o, core_write_o, core_load_o,
    output logic [1:0] core_array_o,
    output logic [7:0] core_lines_o,
    output logic [767:0] core_frames_o,
    output logic busy_o, done_o, error_o
);
    typedef enum logic [1:0] {IDLE, ISSUE, WAIT_DONE} state_t;
    state_t state_q;
    logic load_q, array_q;
    logic [2:0] line_q;
    logic [1:0] chip_q;
    logic [23:0] frame_q;
    assign core_valid_o = state_q == ISSUE && core_ready_i;
    assign core_write_o = !load_q;
    assign core_load_o = load_q;
    assign core_array_o = array_q ? ARRAY_TX : ARRAY_RX;
    assign core_lines_o = 8'b1 << line_q;
    assign busy_o = state_q != IDLE;
    always_comb begin
        core_frames_o = '0;
        for (int line = 0; line < 8; line++)
            for (int chip = 0; chip < 4; chip++)
                core_frames_o[(line*4+chip)*24 +: 24] =
                    line == line_q && chip == chip_q ? frame_q :
                    {CID_MAP[chip*4 +: 4], 4'b1000, 16'b0};
    end
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            state_q <= IDLE; load_q <= 0; array_q <= 0; line_q <= 0;
            chip_q <= 0; frame_q <= 0; done_o <= 0; error_o <= 0;
        end else begin
            done_o <= 0; error_o <= 0;
            case (state_q)
                IDLE: if (start_i) begin
                    load_q <= load_i; array_q <= array_i; line_q <= line_i;
                    chip_q <= chip_i; frame_q <= frame_i; state_q <= ISSUE;
                end
                ISSUE: if (core_ready_i) state_q <= WAIT_DONE;
                WAIT_DONE: if (core_error_i) begin
                    error_o <= 1; state_q <= IDLE;
                end else if ((!load_q && core_write_done_i) || (load_q && core_load_done_i)) begin
                    done_o <= 1; state_q <= IDLE;
                end
                default: state_q <= IDLE;
            endcase
        end
    end
endmodule
