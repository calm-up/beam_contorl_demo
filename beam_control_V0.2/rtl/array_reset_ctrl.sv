`timescale 1ns/1ps

import beam_cmd_pkg::*;

// Common reset sequencer. The same eight-line waveform can be routed to both
// RX and TX arrays so all 64 front-end chips reset together.
module array_reset_ctrl #(
    parameter int unsigned SERIAL_HALF_PERIOD_CYCLES = 5,
    parameter int unsigned RESET_CLK_CYCLES          = 128,
    parameter int unsigned POST_RESET_CYCLES         = 10
) (
    input  logic                  clk_i,
    input  logic                  rst_i,
    input  logic                  restart_i,
    output logic                  reset_complete_o,
    output logic [LINE_COUNT-1:0] reset_clk_o,
    output logic [LINE_COUNT-1:0] rstn_o
);

    localparam int unsigned DIV_COUNT_W =
        (SERIAL_HALF_PERIOD_CYCLES <= 1) ? 1 : $clog2(SERIAL_HALF_PERIOD_CYCLES);
    localparam int unsigned RESET_COUNT_W =
        (RESET_CLK_CYCLES <= 1) ? 1 : $clog2(RESET_CLK_CYCLES);
    localparam int unsigned POST_COUNT_W =
        (POST_RESET_CYCLES <= 1) ? 1 : $clog2(POST_RESET_CYCLES);

    typedef enum logic [1:0] {
        ST_HOLD,
        ST_CLOCK,
        ST_POST,
        ST_READY
    } state_t;

    state_t state_q;
    logic [DIV_COUNT_W-1:0] div_count_q;
    logic [RESET_COUNT_W-1:0] reset_count_q;
    logic [POST_COUNT_W-1:0] post_count_q;
    logic serial_clk_q;

    initial begin
        if (SERIAL_HALF_PERIOD_CYCLES < 1 || RESET_CLK_CYCLES < 1 ||
            POST_RESET_CYCLES < 1) begin
            $error("Reset timing parameters must all be at least 1");
        end
    end

    assign reset_complete_o = (state_q == ST_READY);
    assign reset_clk_o      = (state_q == ST_CLOCK) ?
                              {LINE_COUNT{serial_clk_q}} : '0;
    assign rstn_o           = ((state_q == ST_POST) || (state_q == ST_READY)) ?
                              {LINE_COUNT{1'b1}} : '0;

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            state_q       <= ST_HOLD;
            div_count_q   <= '0;
            reset_count_q <= '0;
            post_count_q  <= '0;
            serial_clk_q  <= 1'b0;
        end else begin
            case (state_q)
                ST_HOLD: begin
                    div_count_q   <= '0;
                    reset_count_q <= '0;
                    post_count_q  <= '0;
                    serial_clk_q  <= 1'b0;
                    state_q       <= ST_CLOCK;
                end

                ST_CLOCK: begin
                    if (div_count_q == SERIAL_HALF_PERIOD_CYCLES - 1) begin
                        div_count_q <= '0;
                        if (!serial_clk_q) begin
                            serial_clk_q <= 1'b1;
                        end else begin
                            serial_clk_q <= 1'b0;
                            if (reset_count_q == RESET_CLK_CYCLES - 1) begin
                                reset_count_q <= '0;
                                post_count_q  <= '0;
                                state_q       <= ST_POST;
                            end else begin
                                reset_count_q <= reset_count_q + 1'b1;
                            end
                        end
                    end else begin
                        div_count_q <= div_count_q + 1'b1;
                    end
                end

                ST_POST: begin
                    serial_clk_q <= 1'b0;
                    if (post_count_q == POST_RESET_CYCLES - 1) begin
                        post_count_q <= '0;
                        state_q      <= ST_READY;
                    end else begin
                        post_count_q <= post_count_q + 1'b1;
                    end
                end

                ST_READY: begin
                    if (restart_i) begin
                        div_count_q   <= '0;
                        reset_count_q <= '0;
                        post_count_q  <= '0;
                        serial_clk_q  <= 1'b0;
                        state_q       <= ST_CLOCK;
                    end
                end

                default: state_q <= ST_HOLD;
            endcase
        end
    end

endmodule
