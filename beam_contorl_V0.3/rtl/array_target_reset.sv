`timescale 1ns/1ps

// Runtime reset: selected RX/TX lines receive 128 complete serial clock
// periods with RSTN low. Nonselected outputs are unaffected by the caller.
module array_target_reset #(
    parameter int unsigned HALF_PERIOD_CYCLES = 5,
    parameter int unsigned RESET_CLOCKS = 128,
    parameter int unsigned POST_CYCLES = 10
) (
    input  logic       clk_i,
    input  logic       rst_i,
    input  logic       start_i,
    input  logic [1:0] array_sel_i,
    input  logic [7:0] line_mask_i,
    output logic       busy_o,
    output logic       done_o,
    output logic [1:0] active_array_o,
    output logic [7:0] active_lines_o,
    output logic [7:0] clk_o,
    output logic [7:0] rstn_o
);
    localparam int unsigned DIV_W = (HALF_PERIOD_CYCLES < 2) ? 1 : $clog2(HALF_PERIOD_CYCLES);
    localparam int unsigned CNT_W = (RESET_CLOCKS < 2) ? 1 : $clog2(RESET_CLOCKS);
    localparam int unsigned POST_W = (POST_CYCLES < 2) ? 1 : $clog2(POST_CYCLES);
    typedef enum logic [1:0] {IDLE, CLOCK, POST} state_t;
    state_t state_q;
    logic [DIV_W-1:0] div_q;
    logic [CNT_W-1:0] cycles_q;
    logic [POST_W-1:0] post_q;
    logic serial_clk_q;
    assign busy_o = state_q != IDLE;
    assign clk_o = (state_q == CLOCK && serial_clk_q) ? active_lines_o : 8'h00;
    assign rstn_o = (state_q == CLOCK) ? ~active_lines_o : 8'hff;
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            state_q <= IDLE;
            div_q <= '0;
            cycles_q <= '0;
            post_q <= '0;
            serial_clk_q <= 1'b0;
            active_array_o <= '0;
            active_lines_o <= '0;
            done_o <= 1'b0;
        end else begin
            done_o <= 1'b0;
            case (state_q)
                IDLE: if (start_i && array_sel_i != 0 && line_mask_i != 0) begin
                    active_array_o <= array_sel_i;
                    active_lines_o <= line_mask_i;
                    div_q <= '0;
                    cycles_q <= '0;
                    serial_clk_q <= 1'b0;
                    state_q <= CLOCK;
                end
                CLOCK: if (div_q == HALF_PERIOD_CYCLES - 1) begin
                    div_q <= '0;
                    serial_clk_q <= ~serial_clk_q;
                    if (serial_clk_q) begin
                        if (cycles_q == RESET_CLOCKS - 1) begin
                            serial_clk_q <= 1'b0;
                            cycles_q <= '0;
                            post_q <= '0;
                            state_q <= POST;
                        end else cycles_q <= cycles_q + 1'b1;
                    end
                end else div_q <= div_q + 1'b1;
                POST: if (post_q == POST_CYCLES - 1) begin
                    done_o <= 1'b1;
                    state_q <= IDLE;
                end else post_q <= post_q + 1'b1;
                default: state_q <= IDLE;
            endcase
        end
    end
endmodule
