`timescale 1ns/1ps

import beam_cmd_pkg::*;

// One-array write engine: eight line arrays, four independent SDI lanes each.
// All selected lines share CLK/CSB timing and the D23-to-D0 bit index.
module array_write_engine #(
    parameter int unsigned SERIAL_HALF_PERIOD_CYCLES = 5,
    parameter int unsigned POST_FRAME_CLOCKS         = 2
) (
    input  logic                          clk_i,
    input  logic                          rst_i,
    input  logic                          start_i,
    input  logic [LINE_COUNT-1:0]         line_mask_i,
    input  logic [ARRAY_FRAME_BITS-1:0]   frames_i,

    output logic                          ready_o,
    output logic                          busy_o,
    output logic                          write_done_o,
    output logic [LINE_COUNT*CHIPS_PER_LINE-1:0] sdi_o,
    output logic [LINE_COUNT-1:0]         serial_clk_o,
    output logic [LINE_COUNT-1:0]         csb_o
);

    localparam int unsigned DIV_COUNT_W =
        (SERIAL_HALF_PERIOD_CYCLES <= 1) ? 1 : $clog2(SERIAL_HALF_PERIOD_CYCLES);
    localparam int unsigned POST_COUNT_W =
        (POST_FRAME_CLOCKS <= 1) ? 1 : $clog2(POST_FRAME_CLOCKS + 1);

    typedef enum logic [1:0] {
        ST_IDLE,
        ST_SHIFT,
        ST_POST
    } state_t;

    state_t state_q;
    logic [DIV_COUNT_W-1:0] div_count_q;
    logic [POST_COUNT_W-1:0] post_count_q;
    logic [4:0] bit_index_q;
    logic serial_clk_q;
    logic [LINE_COUNT-1:0] line_mask_q;
    logic [ARRAY_FRAME_BITS-1:0] frames_q;

    initial begin
        if (SERIAL_HALF_PERIOD_CYCLES < 1) begin
            $error("SERIAL_HALF_PERIOD_CYCLES must be at least 1");
        end
        if (POST_FRAME_CLOCKS < 1) begin
            $error("POST_FRAME_CLOCKS must be at least 1");
        end
    end

    assign ready_o      = (state_q == ST_IDLE);
    assign busy_o       = (state_q != ST_IDLE);
    assign serial_clk_o = {LINE_COUNT{serial_clk_q}} & line_mask_q;
    assign csb_o        = (state_q == ST_SHIFT) ? ~line_mask_q : {LINE_COUNT{1'b1}};

    genvar line_index;
    genvar chip_index;
    generate
        for (line_index = 0; line_index < LINE_COUNT; line_index = line_index + 1) begin : g_line
            for (chip_index = 0; chip_index < CHIPS_PER_LINE; chip_index = chip_index + 1) begin : g_chip
                localparam int unsigned SDI_INDEX =
                    line_index * CHIPS_PER_LINE + chip_index;
                localparam int unsigned FRAME_BASE =
                    SDI_INDEX * FRAME_BITS;
                always_comb begin
                    if ((state_q == ST_SHIFT) && line_mask_q[line_index]) begin
                        sdi_o[SDI_INDEX] = frames_q[FRAME_BASE + bit_index_q];
                    end else begin
                        sdi_o[SDI_INDEX] = 1'b0;
                    end
                end
            end
        end
    endgenerate

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            state_q        <= ST_IDLE;
            div_count_q    <= '0;
            post_count_q   <= '0;
            bit_index_q    <= 5'd23;
            serial_clk_q   <= 1'b0;
            line_mask_q    <= '0;
            frames_q       <= '0;
            write_done_o   <= 1'b0;
        end else begin
            write_done_o <= 1'b0;

            case (state_q)
                ST_IDLE: begin
                    div_count_q  <= '0;
                    post_count_q <= '0;
                    bit_index_q  <= 5'd23;
                    serial_clk_q <= 1'b0;

                    if (start_i) begin
                        line_mask_q <= line_mask_i;
                        frames_q    <= frames_i;
                        state_q     <= ST_SHIFT;
                    end
                end

                ST_SHIFT: begin
                    if (div_count_q == SERIAL_HALF_PERIOD_CYCLES - 1) begin
                        div_count_q <= '0;
                        if (!serial_clk_q) begin
                            // Rising edge: the selected chips sample current SDI.
                            serial_clk_q <= 1'b1;
                        end else begin
                            // Falling edge: advance data for the next sample.
                            serial_clk_q <= 1'b0;
                            if (bit_index_q == 0) begin
                                post_count_q <= '0;
                                state_q      <= ST_POST;
                            end else begin
                                bit_index_q <= bit_index_q - 1'b1;
                            end
                        end
                    end else begin
                        div_count_q <= div_count_q + 1'b1;
                    end
                end

                ST_POST: begin
                    if (div_count_q == SERIAL_HALF_PERIOD_CYCLES - 1) begin
                        div_count_q <= '0;
                        if (!serial_clk_q) begin
                            serial_clk_q <= 1'b1;
                            post_count_q <= post_count_q + 1'b1;
                        end else begin
                            serial_clk_q <= 1'b0;
                            if (post_count_q == POST_FRAME_CLOCKS) begin
                                line_mask_q  <= '0;
                                write_done_o <= 1'b1;
                                state_q      <= ST_IDLE;
                            end
                        end
                    end else begin
                        div_count_q <= div_count_q + 1'b1;
                    end
                end

                default: begin
                    state_q <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
