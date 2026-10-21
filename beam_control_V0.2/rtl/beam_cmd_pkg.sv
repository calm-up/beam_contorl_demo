`timescale 1ns/1ps

package beam_cmd_pkg;

    localparam int unsigned FRAME_BITS       = 24;
    localparam int unsigned CHIPS_PER_LINE   = 4;
    localparam int unsigned LINE_COUNT       = 8;
    localparam int unsigned ARRAY_FRAME_BITS =
        FRAME_BITS * CHIPS_PER_LINE * LINE_COUNT;

    // Array selection is a bit mask so RX and TX can be selected together.
    typedef enum logic [1:0] {
        ARRAY_NONE = 2'b00,
        ARRAY_RX   = 2'b01,
        ARRAY_TX   = 2'b10,
        ARRAY_BOTH = 2'b11
    } array_sel_t;

    // Frame vector layout:
    //   base = ((line * 4) + chip) * 24
    //   frame[base +: 24] is that chip's complete frame.
    // The serializer sends frame[base + 23] first and frame[base] last.
    function automatic int unsigned frame_lsb(
        input int unsigned line_index,
        input int unsigned chip_index
    );
        frame_lsb =
            ((line_index * CHIPS_PER_LINE) + chip_index) * FRAME_BITS;
    endfunction

    // V1 accepts exactly one operation per command. A zero array selection or
    // zero line mask is illegal. Frame contents are ignored for LOAD commands.
    function automatic logic command_is_legal(
        input logic [1:0] array_sel,
        input logic [7:0] line_mask,
        input logic       cmd_write,
        input logic       cmd_load
    );
        command_is_legal =
            (array_sel != ARRAY_NONE) &&
            (line_mask != 8'h00) &&
            (cmd_write ^ cmd_load);
    endfunction

endpackage
