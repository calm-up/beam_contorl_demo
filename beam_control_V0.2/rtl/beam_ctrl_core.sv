`timescale 1ns/1ps

import beam_cmd_pkg::*;

module beam_ctrl_core #(
    parameter bit ENABLE_CHIP_INIT = 1'b0,
    parameter logic [15:0] CID_MAP = 16'h3210,
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
    logic reset_complete;
    logic [9:0] init_index_q;
    logic init_request, init_accept;
    logic [23:0] init_frame [0:3];
    logic [ARRAY_FRAME_BITS-1:0] init_frames;
    logic [1:0] active_array_sel;
    logic [7:0] active_line_mask;
    logic [ARRAY_FRAME_BITS-1:0] active_rx_frames, active_tx_frames;
    logic active_write, active_load;
    logic internal_ready;

    // Control_Reg E column, addresses 0..127, low byte first.
    // CCAR10405L详测码表_202609.xlsx SHA256:
    // 997cb1308d838f724cfea3f4005bffa2a4f598db493404ecf35b534e10b192fc
    localparam logic [1023:0] CONTROL_DEFAULTS = {
        256'h000000000000000000000000000000000000000F0F0F0F0F0F0F0F0F0F0F0200,
        256'h0001010203030101020201010101010100000000000000080004040404040404,
        256'h0404040400000000000000080004040404040404040404040000000000000008,
        256'h0004040404040404040404040000000000000008000404040404040404040404
    };

    function automatic [23:0] chip_init_frame(
        input logic [9:0] index,
        input logic [3:0] cid
    );
        logic [7:0] address;
        logic [7:0] data_byte;
        logic [5:0] att_address;
        begin
            address = '0;
            data_byte = '0;
            att_address = '0;
            if (index < 10'd128) begin
                address = index[7:0];
                data_byte = CONTROL_DEFAULTS[index[6:0]*8 +: 8];
                chip_init_frame = {cid, 4'b0100, address, data_byte};
            end else if (index < 10'd384) begin
                // TXPS 0..127, then RXPS 128..255. Each 16-bit
                // table word is (state << 6), high byte before low byte.
                address = index[7:0] - 8'd128;
                if (!index[0]) data_byte = {4'b0, index[6:3]};
                else           data_byte = {index[2:1], 6'b0};
                chip_init_frame = {cid, 4'b0101, address, data_byte};
            end else if (index < 10'd448) begin
                att_address = index[5:0];
                chip_init_frame = {cid, 4'b0110, att_address,
                                   2'b00, att_address, 2'b00};
            end else if (index < 10'd512) begin
                att_address = index[5:0];
                chip_init_frame = {cid, 4'b0111, att_address,
                                   2'b00, att_address, 2'b00};
            end else begin
                // CHANNEL_ENA default is zero; leave all 16 channels off.
                chip_init_frame = {cid, 20'b0};
            end
        end
    endfunction

    always_comb begin
        init_frame[0] = chip_init_frame(init_index_q, CID_MAP[3:0]);
        init_frame[1] = chip_init_frame(init_index_q, CID_MAP[7:4]);
        init_frame[2] = chip_init_frame(init_index_q, CID_MAP[11:8]);
        init_frame[3] = chip_init_frame(init_index_q, CID_MAP[15:12]);
        for (int line = 0; line < LINE_COUNT; line++) begin
            init_frames[line*96 +: 96] = {init_frame[3], init_frame[2],
                                          init_frame[1], init_frame[0]};
        end
    end

    assign init_done_o = reset_complete &&
                         (!ENABLE_CHIP_INIT || init_index_q == 10'd513);
    assign init_request = ENABLE_CHIP_INIT && reset_complete &&
                          (init_index_q < 10'd513) && internal_ready;
    assign active_array_sel = init_request ? ARRAY_BOTH : cmd_array_sel_i;
    assign active_line_mask = init_request ? {LINE_COUNT{1'b1}} : cmd_line_mask_i;
    assign active_rx_frames = init_request ? init_frames : cmd_rx_frames_i;
    assign active_tx_frames = init_request ? init_frames : cmd_tx_frames_i;
    assign active_write = init_request ? 1'b1 : cmd_write_i;
    assign active_load  = init_request ? 1'b0 : cmd_load_i;

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

    assign internal_ready = reset_complete && !transaction_active_q &&
                         rx_write_ready && tx_write_ready &&
                         rx_load_ready && tx_load_ready;
    assign cmd_ready_o = init_done_o && internal_ready;
    assign busy_o = !init_done_o || transaction_active_q;
    assign command_legal = command_is_legal(
        active_array_sel, active_line_mask, active_write, active_load);
    assign command_accept = cmd_valid_i && cmd_ready_o && command_legal;
    assign init_accept = init_request;
    assign rx_write_start = (command_accept || init_accept) && active_write && active_array_sel[0];
    assign tx_write_start = (command_accept || init_accept) && active_write && active_array_sel[1];
    assign rx_load_start  = command_accept && active_load && active_array_sel[0];
    assign tx_load_start  = command_accept && active_load && active_array_sel[1];

    array_reset_ctrl #(
        .SERIAL_HALF_PERIOD_CYCLES(SERIAL_HALF_PERIOD_CYCLES),
        .RESET_CLK_CYCLES(RESET_CLK_CYCLES),
        .POST_RESET_CYCLES(POST_RESET_CYCLES)
    ) u_reset (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .restart_i(1'b0),
        .reset_complete_o(reset_complete),
        .reset_clk_o(reset_clk),
        .rstn_o(reset_rstn)
    );

    array_write_engine #(
        .SERIAL_HALF_PERIOD_CYCLES(SERIAL_HALF_PERIOD_CYCLES),
        .POST_FRAME_CLOCKS(POST_FRAME_CLOCKS)
    ) u_rx_write (
        .clk_i(clk_i), .rst_i(rst_i || !reset_complete),
        .start_i(rx_write_start), .line_mask_i(active_line_mask),
        .frames_i(active_rx_frames), .ready_o(rx_write_ready),
        .busy_o(rx_write_busy), .write_done_o(rx_write_done),
        .sdi_o(rx_write_sdi), .serial_clk_o(rx_write_clk), .csb_o(rx_write_csb)
    );

    array_write_engine #(
        .SERIAL_HALF_PERIOD_CYCLES(SERIAL_HALF_PERIOD_CYCLES),
        .POST_FRAME_CLOCKS(POST_FRAME_CLOCKS)
    ) u_tx_write (
        .clk_i(clk_i), .rst_i(rst_i || !reset_complete),
        .start_i(tx_write_start), .line_mask_i(active_line_mask),
        .frames_i(active_tx_frames), .ready_o(tx_write_ready),
        .busy_o(tx_write_busy), .write_done_o(tx_write_done),
        .sdi_o(tx_write_sdi), .serial_clk_o(tx_write_clk), .csb_o(tx_write_csb)
    );

    array_load_ctrl #(
        .CSB_TO_LDB_CYCLES(CSB_TO_LDB_CYCLES),
        .LDB_LOW_CYCLES(LDB_LOW_CYCLES)
    ) u_rx_load (
        .clk_i(clk_i), .rst_i(rst_i || !reset_complete),
        .start_i(rx_load_start), .line_mask_i(active_line_mask),
        .write_busy_i(rx_write_busy), .csb_i(rx_write_csb),
        .ready_o(rx_load_ready), .busy_o(rx_load_busy),
        .write_inhibit_o(rx_load_inhibit), .load_done_o(rx_load_done),
        .ldb_o(rx_load_ldb)
    );

    array_load_ctrl #(
        .CSB_TO_LDB_CYCLES(CSB_TO_LDB_CYCLES),
        .LDB_LOW_CYCLES(LDB_LOW_CYCLES)
    ) u_tx_load (
        .clk_i(clk_i), .rst_i(rst_i || !reset_complete),
        .start_i(tx_load_start), .line_mask_i(active_line_mask),
        .write_busy_i(tx_write_busy), .csb_i(tx_write_csb),
        .ready_o(tx_load_ready), .busy_o(tx_load_busy),
        .write_inhibit_o(tx_load_inhibit), .load_done_o(tx_load_done),
        .ldb_o(tx_load_ldb)
    );

    array_output_router u_rx_router (
        .init_done_i(reset_complete), .reset_clk_i(reset_clk),
        .reset_rstn_i(reset_rstn), .write_sdi_i(rx_write_sdi),
        .write_clk_i(rx_write_clk), .write_csb_i(rx_write_csb),
        .load_ldb_i(rx_load_ldb), .sdi_o(rx_sdi_o), .clk_o(rx_clk_o),
        .csb_o(rx_csb_o), .ldb_o(rx_ldb_o), .rstn_o(rx_rstn_o)
    );

    array_output_router u_tx_router (
        .init_done_i(reset_complete), .reset_clk_i(reset_clk),
        .reset_rstn_i(reset_rstn), .write_sdi_i(tx_write_sdi),
        .write_clk_i(tx_write_clk), .write_csb_i(tx_write_csb),
        .load_ldb_i(tx_load_ldb), .sdi_o(tx_sdi_o), .clk_o(tx_clk_o),
        .csb_o(tx_csb_o), .ldb_o(tx_ldb_o), .rstn_o(tx_rstn_o)
    );

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            init_index_q         <= '0;
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

            if (transaction_active_q && transaction_write_q &&
                (pending_q & ~done_vector) == ARRAY_NONE &&
                !init_done_o && ENABLE_CHIP_INIT) begin
                init_index_q <= init_index_q + 1'b1;
            end

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
            end else if (init_accept || (cmd_valid_i && cmd_ready_o)) begin
                if (!command_legal) begin
                    error_o <= 1'b1;
                end else begin
                    pending_q           <= active_array_sel;
                    transaction_write_q <= active_write;
                    transaction_active_q <= 1'b1;
                end
            end
        end
    end

endmodule
