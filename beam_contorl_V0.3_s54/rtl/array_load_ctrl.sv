`timescale 1ns/1ps

import beam_cmd_pkg::*;

// Independent active-low LDB controller for one array.
module array_load_ctrl #(
    // At 50 MHz, 10 cycles equal one complete 5 MHz serial-clock period.
    parameter int unsigned CSB_TO_LDB_CYCLES = 10,
    parameter int unsigned LDB_LOW_CYCLES    = 5
) (
    input  logic                  clk_i,
    input  logic                  rst_i,
    input  logic                  start_i,
    input  logic [LINE_COUNT-1:0] line_mask_i,
    input  logic                  write_busy_i,
    input  logic [LINE_COUNT-1:0] csb_i,

    output logic                  ready_o,
    output logic                  busy_o,
    output logic                  write_inhibit_o,
    output logic                  load_done_o,
    output logic [LINE_COUNT-1:0] ldb_o
);

    localparam int unsigned GUARD_COUNT_W =
        (CSB_TO_LDB_CYCLES <= 1) ? 1 : $clog2(CSB_TO_LDB_CYCLES);
    localparam int unsigned LOW_COUNT_W =
        (LDB_LOW_CYCLES <= 1) ? 1 : $clog2(LDB_LOW_CYCLES);

    typedef enum logic [1:0] {
        ST_IDLE,
        ST_GUARD,
        ST_PULSE
    } state_t;

    state_t state_q;
    logic [GUARD_COUNT_W-1:0] guard_count_q;
    logic [LOW_COUNT_W-1:0] low_count_q;
    logic [LINE_COUNT-1:0] line_mask_q;
    logic selected_csb_high;

    initial begin
        if (CSB_TO_LDB_CYCLES < 1) begin
            $error("CSB_TO_LDB_CYCLES must be at least 1");
        end
        if (LDB_LOW_CYCLES < 1) begin
            $error("LDB_LOW_CYCLES must be at least 1");
        end
    end

    assign selected_csb_high = &(csb_i | ~line_mask_q);
    assign ready_o           = (state_q == ST_IDLE) && !write_busy_i;
    assign busy_o            = (state_q != ST_IDLE);
    assign write_inhibit_o   = busy_o;
    assign ldb_o             = (state_q == ST_PULSE) ?
                               ~line_mask_q : {LINE_COUNT{1'b1}};

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            state_q       <= ST_IDLE;
            guard_count_q <= '0;
            low_count_q   <= '0;
            line_mask_q   <= '0;
            load_done_o   <= 1'b0;
        end else begin
            load_done_o <= 1'b0;

            case (state_q)
                ST_IDLE: begin
                    guard_count_q <= '0;
                    low_count_q   <= '0;
                    if (start_i && !write_busy_i) begin
                        line_mask_q <= line_mask_i;
                        state_q     <= ST_GUARD;
                    end
                end

                ST_GUARD: begin
                    // Restart the full guard interval if a selected CSB is
                    // active or the writer becomes busy unexpectedly.
                    if (write_busy_i || !selected_csb_high) begin
                        guard_count_q <= '0;
                    end else if (guard_count_q == CSB_TO_LDB_CYCLES - 1) begin
                        guard_count_q <= '0;
                        low_count_q   <= '0;
                        state_q       <= ST_PULSE;
                    end else begin
                        guard_count_q <= guard_count_q + 1'b1;
                    end
                end

                ST_PULSE: begin
                    if (low_count_q == LDB_LOW_CYCLES - 1) begin
                        low_count_q <= '0;
                        line_mask_q <= '0;
                        load_done_o <= 1'b1;
                        state_q     <= ST_IDLE;
                    end else begin
                        low_count_q <= low_count_q + 1'b1;
                    end
                end

                default: begin
                    state_q <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
