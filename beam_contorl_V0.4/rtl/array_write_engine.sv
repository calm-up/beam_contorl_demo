`timescale 1ns/1ps

import beam_cmd_pkg::*;

// One-array write engine: eight line arrays, four independent SDI lanes each.
// All lines receive free-running SCLK. The mask selects CSB/SDI only.
// Selected lines share the D23-to-D0 bit index; idle and LDB never gate SCLK.
module array_write_engine #(
    parameter int unsigned SERIAL_HALF_PERIOD_CYCLES = 5,
    parameter int unsigned POST_FRAME_CLOCKS         = 2
) (
    input  logic                          clk_i,
    input  logic                          rst_i,
    input  logic                          start_i,
    input  logic [LINE_COUNT-1:0]         line_mask_i,
    input  logic [ARRAY_FRAME_BITS-1:0]   frames_i,
    input  logic [LINE_COUNT-1:0]         sdo_i,
    output logic [LINE_COUNT*FRAME_BITS-1:0] sdo_last_o,

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

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_ARM,
        ST_SHIFT,
        ST_FINAL,
        ST_POST
    } state_t;

    // Sample the final SDO bit BEFORE the next periodic SCLK rising edge.
    // At 50MHz / half=5: sample & release CSB at +80ns, rise at +100ns.
    localparam int unsigned FINAL_SAMPLE_CYCLES = SERIAL_HALF_PERIOD_CYCLES - 1;
    logic final_sampled_q;
    state_t state_q;
    logic [DIV_COUNT_W-1:0] div_count_q;
    logic [POST_COUNT_W-1:0] post_count_q;
    logic [4:0] bit_index_q;
    logic serial_clk_q;
    logic [LINE_COUNT-1:0] line_mask_q;
    logic [ARRAY_FRAME_BITS-1:0] frames_q;

    initial begin
        if (SERIAL_HALF_PERIOD_CYCLES < 2) begin
            $error("SERIAL_HALF_PERIOD_CYCLES must be at least 2 for a final-sample/CSB guard interval");
        end
        if (POST_FRAME_CLOCKS < 1) begin
            $error("POST_FRAME_CLOCKS must be at least 1");
        end
    end

    assign ready_o      = (state_q == ST_IDLE);
    assign busy_o       = (state_q != ST_IDLE);
    assign serial_clk_o = {LINE_COUNT{serial_clk_q}}; // free-running on ALL lines
    assign csb_o        = ((state_q == ST_SHIFT) ||
                           ((state_q == ST_FINAL) && !final_sampled_q)) ?
                          ~line_mask_q : {LINE_COUNT{1'b1}};

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

    // Clock generation is independent of SPI transactions and line selection.
    // Only power-on/system reset may hold it low; requests never reset its phase.
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            div_count_q <= '0;
            serial_clk_q <= 1'b0;
        end else if (div_count_q == SERIAL_HALF_PERIOD_CYCLES - 1) begin
            div_count_q <= '0;
            serial_clk_q <= ~serial_clk_q;
        end else div_count_q <= div_count_q + 1'b1;
    end

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            state_q <= ST_IDLE;
            post_count_q <= '0;
            bit_index_q <= 5'd23;
            line_mask_q <= '0;
            frames_q <= '0;
            final_sampled_q <= 1'b0;
            sdo_last_o <= '0;
            write_done_o <= 1'b0;
        end else begin
            write_done_o <= 1'b0;
            case (state_q)
                ST_IDLE: begin
                    post_count_q <= '0;
                    bit_index_q <= 5'd23;
                    final_sampled_q <= 1'b0;
                    if (start_i) begin
                        line_mask_q <= line_mask_i;
                        frames_q <= frames_i;
                        state_q <= ST_ARM;
                    end
                end
                ST_ARM: begin
                    // Assert CSB only at a regular falling edge. The first
                    // selected sampling edge is exactly one half-period later.
                    if (div_count_q == SERIAL_HALF_PERIOD_CYCLES - 1 && serial_clk_q)
                        state_q <= ST_SHIFT;
                end
                ST_SHIFT: begin
                    if (div_count_q == SERIAL_HALF_PERIOD_CYCLES - 1) begin
                        if (!serial_clk_q) begin
                            for (int line=0;line<LINE_COUNT;line++)
                                if (line_mask_q[line])
                                    sdo_last_o[line*FRAME_BITS +: FRAME_BITS] <=
                                        {sdo_last_o[line*FRAME_BITS +: FRAME_BITS-1],sdo_i[line]};
                        end else if (bit_index_q == 0) begin
                            post_count_q <= '0;
                            state_q <= ST_FINAL;
                        end else bit_index_q <= bit_index_q - 1'b1;
                    end
                end
                ST_FINAL: begin
                    // At half=5, sample +80ns after the final falling edge,
                    // release CSB, then the free-running clock rises at +100ns.
                    if (div_count_q == FINAL_SAMPLE_CYCLES - 1) begin
                        for (int line=0;line<LINE_COUNT;line++)
                            if (line_mask_q[line])
                                sdo_last_o[line*FRAME_BITS +: FRAME_BITS] <=
                                    {sdo_last_o[line*FRAME_BITS +: FRAME_BITS-1],sdo_i[line]};
                        final_sampled_q <= 1'b1;
                    end
                    if (div_count_q == SERIAL_HALF_PERIOD_CYCLES - 1) begin
                        post_count_q <= 1;
                        state_q <= ST_POST;
                    end
                end
                ST_POST: begin
                    if (div_count_q == SERIAL_HALF_PERIOD_CYCLES - 1) begin
                        if (!serial_clk_q) post_count_q <= post_count_q + 1'b1;
                        else if (post_count_q == POST_FRAME_CLOCKS) begin
                            line_mask_q <= '0;
                            write_done_o <= 1'b1;
                            state_q <= ST_IDLE;
                        end
                    end
                end
                default: state_q <= ST_IDLE;
            endcase
        end
    end
endmodule
