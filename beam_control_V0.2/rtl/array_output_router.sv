`timescale 1ns/1ps

import beam_cmd_pkg::*;

// One-array physical output router and safety override.
module array_output_router (
    input  logic                          init_done_i,
    input  logic [LINE_COUNT-1:0]         reset_clk_i,
    input  logic [LINE_COUNT-1:0]         reset_rstn_i,
    input  logic [LINE_COUNT*CHIPS_PER_LINE-1:0] write_sdi_i,
    input  logic [LINE_COUNT-1:0]         write_clk_i,
    input  logic [LINE_COUNT-1:0]         write_csb_i,
    input  logic [LINE_COUNT-1:0]         load_ldb_i,

    output logic [LINE_COUNT*CHIPS_PER_LINE-1:0] sdi_o,
    output logic [LINE_COUNT-1:0]         clk_o,
    output logic [LINE_COUNT-1:0]         csb_o,
    output logic [LINE_COUNT-1:0]         ldb_o,
    output logic [LINE_COUNT-1:0]         rstn_o
);

    always_comb begin
        sdi_o  = '0;
        clk_o  = reset_clk_i;
        csb_o  = {LINE_COUNT{1'b1}};
        ldb_o  = {LINE_COUNT{1'b1}};
        rstn_o = reset_rstn_i;

        if (init_done_i) begin
            sdi_o  = write_sdi_i;
            clk_o  = write_clk_i;
            csb_o  = write_csb_i;
            ldb_o  = load_ldb_i;
            rstn_o = {LINE_COUNT{1'b1}};
        end
    end

endmodule
