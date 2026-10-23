`timescale 1ns/1ps

import beam_cmd_pkg::*;

module beam_ctrl_core #(
    parameter int unsigned SERIAL_HALF_PERIOD_CYCLES = 5,
    parameter int unsigned POST_FRAME_CLOCKS         = 2,
    parameter int unsigned RESET_CLK_CYCLES          = 128,
    parameter int unsigned POST_RESET_CYCLES         = 10,
    parameter int unsigned CSB_TO_LDB_CYCLES         = 10,
    parameter int unsigned LDB_LOW_CYCLES            = 5
) (
    input  logic                         clk_i,
    input  logic                         rst_i,

    input  logic                         cmd_valid_i,
    output logic                         cmd_ready_o,
    input  logic [1:0]                   cmd_array_sel_i,
    input  logic [LINE_COUNT-1:0]        cmd_line_mask_i,
    input  logic [ARRAY_FRAME_BITS-1:0]  cmd_rx_frames_i,
    input  logic [ARRAY_FRAME_BITS-1:0]  cmd_tx_frames_i,
    input  logic                         cmd_write_i,
    input  logic                         cmd_load_i,
    output logic                         busy_o,
    output logic                         write_done_o,
    output logic                         load_done_o,
    output logic                         error_o,
    output logic                         init_done_o,

    output logic [31:0] rx_sdi_o,
    output logic [7:0]  rx_clk_o,
    output logic [7:0]  rx_csb_o,
    output logic [7:0]  rx_ldb_o,
    output logic [7:0]  rx_rstn_o,
    output logic [31:0] tx_sdi_o,
    output logic [7:0]  tx_clk_o,
    output logic [7:0]  tx_csb_o,
    output logic [7:0]  tx_ldb_o,
    output logic [7:0]  tx_rstn_o
);

    logic [7:0] reset_clk, reset_rstn;

    logic rx_write_start, tx_write_start;
    logic rx_write_ready, tx_write_ready;
    logic rx_write_busy, tx_write_busy;
    logic rx_write_done, tx_write_done;
    logic [31:0] rx_write_sdi, tx_write_sdi;
    logic [7:0] rx_write_clk, tx_write_clk;
    logic [7:0] rx_write_csb, tx_write_csb;

    logic rx_load_start, tx_load_start;
    logic rx_load_ready, tx_load_ready;
    logic rx_load_busy, tx_load_busy;
    logic rx_load_inhibit, tx_load_inhibit;
    logic rx_load_done, tx_load_done;
    logic [7:0] rx_load_ldb, tx_load_ldb;

    logic transaction_active_q;
    logic transaction_write_q;
    logic [1:0] pending_q;
    logic [1:0] done_vector;
    logic command_legal;
    logic command_accept;

    assign done_vector = transaction_write_q ?
                         {tx_write_done, rx_write_done} :
                         {tx_load_done, rx_load_done};

    assign cmd_ready_o = init_done_o && !transaction_active_q &&
                         rx_write_ready && tx_write_ready &&
                         rx_load_ready && tx_load_ready;
    assign busy_o = !init_done_o || transaction_active_q;
    assign command_legal = command_is_legal(
        cmd_array_sel_i, cmd_line_mask_i, cmd_write_i, cmd_load_i);
    assign command_accept = cmd_valid_i && cmd_ready_o && command_legal;
    assign rx_write_start = command_accept && cmd_write_i && cmd_array_sel_i[0];
    assign tx_write_start = command_accept && cmd_write_i && cmd_array_sel_i[1];
    assign rx_load_start  = command_accept && cmd_load_i  && cmd_array_sel_i[0];
    assign tx_load_start  = command_accept && cmd_load_i  && cmd_array_sel_i[1];

    array_reset_ctrl #(
        .SERIAL_HALF_PERIOD_CYCLES(SERIAL_HALF_PERIOD_CYCLES),
        .RESET_CLK_CYCLES(RESET_CLK_CYCLES),
        .POST_RESET_CYCLES(POST_RESET_CYCLES)
    ) u_reset (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .restart_i(1'b0),
        .reset_complete_o(init_done_o),
        .reset_clk_o(reset_clk),
        .rstn_o(reset_rstn)
    );

    array_write_engine #(
        .SERIAL_HALF_PERIOD_CYCLES(SERIAL_HALF_PERIOD_CYCLES),
        .POST_FRAME_CLOCKS(POST_FRAME_CLOCKS)
    ) u_rx_write (
        .clk_i(clk_i), .rst_i(rst_i || !init_done_o),
        .start_i(rx_write_start), .line_mask_i(cmd_line_mask_i),
        .frames_i(cmd_rx_frames_i), .ready_o(rx_write_ready),
        .busy_o(rx_write_busy), .write_done_o(rx_write_done),
        .sdi_o(rx_write_sdi), .serial_clk_o(rx_write_clk), .csb_o(rx_write_csb)
    );

    array_write_engine #(
        .SERIAL_HALF_PERIOD_CYCLES(SERIAL_HALF_PERIOD_CYCLES),
        .POST_FRAME_CLOCKS(POST_FRAME_CLOCKS)
    ) u_tx_write (
        .clk_i(clk_i), .rst_i(rst_i || !init_done_o),
        .start_i(tx_write_start), .line_mask_i(cmd_line_mask_i),
        .frames_i(cmd_tx_frames_i), .ready_o(tx_write_ready),
        .busy_o(tx_write_busy), .write_done_o(tx_write_done),
        .sdi_o(tx_write_sdi), .serial_clk_o(tx_write_clk), .csb_o(tx_write_csb)
    );

    array_load_ctrl #(
        .CSB_TO_LDB_CYCLES(CSB_TO_LDB_CYCLES),
        .LDB_LOW_CYCLES(LDB_LOW_CYCLES)
    ) u_rx_load (
        .clk_i(clk_i), .rst_i(rst_i || !init_done_o),
        .start_i(rx_load_start), .line_mask_i(cmd_line_mask_i),
        .write_busy_i(rx_write_busy), .csb_i(rx_write_csb),
        .ready_o(rx_load_ready), .busy_o(rx_load_busy),
        .write_inhibit_o(rx_load_inhibit), .load_done_o(rx_load_done),
        .ldb_o(rx_load_ldb)
    );

    array_load_ctrl #(
        .CSB_TO_LDB_CYCLES(CSB_TO_LDB_CYCLES),
        .LDB_LOW_CYCLES(LDB_LOW_CYCLES)
    ) u_tx_load (
        .clk_i(clk_i), .rst_i(rst_i || !init_done_o),
        .start_i(tx_load_start), .line_mask_i(cmd_line_mask_i),
        .write_busy_i(tx_write_busy), .csb_i(tx_write_csb),
        .ready_o(tx_load_ready), .busy_o(tx_load_busy),
        .write_inhibit_o(tx_load_inhibit), .load_done_o(tx_load_done),
        .ldb_o(tx_load_ldb)
    );

    array_output_router u_rx_router (
        .init_done_i(init_done_o), .reset_clk_i(reset_clk),
        .reset_rstn_i(reset_rstn), .write_sdi_i(rx_write_sdi),
        .write_clk_i(rx_write_clk), .write_csb_i(rx_write_csb),
        .load_ldb_i(rx_load_ldb), .sdi_o(rx_sdi_o), .clk_o(rx_clk_o),
        .csb_o(rx_csb_o), .ldb_o(rx_ldb_o), .rstn_o(rx_rstn_o)
    );

    array_output_router u_tx_router (
        .init_done_i(init_done_o), .reset_clk_i(reset_clk),
        .reset_rstn_i(reset_rstn), .write_sdi_i(tx_write_sdi),
        .write_clk_i(tx_write_clk), .write_csb_i(tx_write_csb),
        .load_ldb_i(tx_load_ldb), .sdi_o(tx_sdi_o), .clk_o(tx_clk_o),
        .csb_o(tx_csb_o), .ldb_o(tx_ldb_o), .rstn_o(tx_rstn_o)
    );

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            transaction_active_q <= 1'b0;
            transaction_write_q  <= 1'b0;
            pending_q            <= '0;
            write_done_o         <= 1'b0;
            load_done_o          <= 1'b0;
            error_o              <= 1'b0;
        end else begin
            write_done_o   <= 1'b0;
            load_done_o    <= 1'b0;
            error_o        <= 1'b0;

            if (transaction_active_q) begin
                pending_q <= pending_q & ~done_vector;
                if ((pending_q & ~done_vector) == ARRAY_NONE) begin
                    transaction_active_q <= 1'b0;
                    if (transaction_write_q) begin
                        write_done_o <= 1'b1;
                    end else begin
                        load_done_o <= 1'b1;
                    end
                end
            end else if (cmd_valid_i && cmd_ready_o) begin
                if (!command_legal) begin
                    error_o <= 1'b1;
                end else begin
                    pending_q           <= cmd_array_sel_i;
                    transaction_write_q <= cmd_write_i;
                    transaction_active_q <= 1'b1;
                end
            end
        end
    end

endmodule
