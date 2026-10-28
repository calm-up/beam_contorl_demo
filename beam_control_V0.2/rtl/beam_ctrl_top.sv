`timescale 1ns/1ps

// Physical board wrapper. Internal commands are tied idle until the JTAG/VIO
// or upstream protocol adapter is enabled; beam_ctrl_core is tested directly.
module beam_ctrl_top #(
    parameter bit          ENABLE_DEBUG_VIO              = 1'b0,
    parameter bit          ENABLE_PROTOCOL_V02           = 1'b1,
    parameter int unsigned SYS_CLK_HZ                    = 50_000_000,
    parameter int unsigned UART_BAUD                     = 115_200,
    parameter logic [15:0] CHIP_CID_MAP                  = 16'h3210,
    parameter int unsigned POR_CYCLES                    = 4,
    parameter int unsigned SERIAL_HALF_PERIOD_CYCLES     = 5,
    parameter int unsigned POST_FRAME_CLOCKS             = 2,
    parameter int unsigned RESET_CLK_CYCLES              = 128,
    parameter int unsigned POST_RESET_CYCLES             = 10,
    parameter int unsigned CSB_TO_LDB_CYCLES             = 10,
    parameter int unsigned LDB_LOW_CYCLES                = 5
) (
    input  wire        sys_clk_i,
    input  wire [7:0]  rx_sdo_i,
    input  wire [7:0]  tx_sdo_i,
    input  wire        rs422_rx_i,
    output wire        rs422_tx_o,
    input  wire        debug_rs485_rx_i,
    output wire        debug_rs485_tx_o,
    output wire        debug_rs485_dir_o,
    input  wire        spare_rs485_rx_i,
    output wire        spare_rs485_tx_o,
    output wire        spare_rs485_dir_o,
    output wire [31:0] rx_sdi_o,
    output wire [7:0]  rx_clk_o,
    output wire [7:0]  rx_csb_o,
    output wire [7:0]  rx_ldb_o,
    output wire [7:0]  rx_rstn_o,
    output wire [7:0]  rx_t_o,
    output wire [7:0]  rx_r_o,
    output wire [31:0] tx_sdi_o,
    output wire [7:0]  tx_clk_o,
    output wire [7:0]  tx_csb_o,
    output wire [7:0]  tx_ldb_o,
    output wire [7:0]  tx_rstn_o,
    output wire [7:0]  tx_t_o,
    output wire [7:0]  tx_r_o
);

    localparam int unsigned POR_COUNT_W =
        (POR_CYCLES <= 1) ? 1 : $clog2(POR_CYCLES);

    logic [POR_COUNT_W-1:0] por_count_q = '0;
    logic por_done_q = 1'b0;

    wire [31:0] core_rx_sdi, core_tx_sdi;
    wire [7:0] core_rx_clk, core_rx_csb, core_rx_ldb, core_rx_rstn;
    wire [7:0] core_tx_clk, core_tx_csb, core_tx_ldb, core_tx_rstn;
    wire core_cmd_ready, core_busy, core_write_done, core_load_done;
    wire core_error, core_init_done;
    wire debug_cmd_valid, debug_cmd_write, debug_cmd_load;
    wire debug_cmd_ready;
    wire [1:0] debug_cmd_array_sel;
    wire [7:0] debug_cmd_line_mask;
    wire [767:0] debug_rx_frames, debug_tx_frames;

    wire protocol_uart_valid, protocol_uart_error;
    wire [7:0] protocol_uart_data;
    wire protocol_frame_valid, protocol_frame_error;
    wire protocol_array, protocol_enable;
    wire [2:0] protocol_line;
    wire [1:0] protocol_chip, protocol_channel;
    wire [5:0] protocol_phase, protocol_attenuation;
    wire protocol_cmd_valid, protocol_cmd_write, protocol_cmd_load;
    wire protocol_core_ready, protocol_busy, protocol_done, protocol_error;
    wire [1:0] protocol_cmd_array_sel;
    wire [7:0] protocol_cmd_line_mask;
    wire [767:0] protocol_rx_frames, protocol_tx_frames;
    wire [7:0] protocol_rx_line_enable, protocol_tx_line_enable;
    wire [15:0] protocol_accepted_count;
    wire [15:0] protocol_completed_count, protocol_rejected_count;

    wire selected_cmd_valid, selected_cmd_write, selected_cmd_load;
    wire [1:0] selected_cmd_array_sel;
    wire [7:0] selected_cmd_line_mask;
    wire [767:0] selected_rx_frames, selected_tx_frames;

    assign protocol_core_ready = core_cmd_ready && protocol_busy;
    assign debug_cmd_ready      = core_cmd_ready && !protocol_busy;
    assign selected_cmd_valid   = protocol_busy ? protocol_cmd_valid : debug_cmd_valid;
    assign selected_cmd_write   = protocol_busy ? protocol_cmd_write : debug_cmd_write;
    assign selected_cmd_load    = protocol_busy ? protocol_cmd_load  : debug_cmd_load;
    assign selected_cmd_array_sel = protocol_busy ? protocol_cmd_array_sel :
                                                    debug_cmd_array_sel;
    assign selected_cmd_line_mask = protocol_busy ? protocol_cmd_line_mask :
                                                    debug_cmd_line_mask;
    assign selected_rx_frames = protocol_busy ? protocol_rx_frames : debug_rx_frames;
    assign selected_tx_frames = protocol_busy ? protocol_tx_frames : debug_tx_frames;

    generate
        if (ENABLE_PROTOCOL_V02) begin : g_protocol_v02
            uart_rx #(
                .CLK_HZ(SYS_CLK_HZ), .BAUD_RATE(UART_BAUD)
            ) u_uart_rx (
                .clk_i(sys_clk_i), .rst_i(!por_done_q), .serial_i(rs422_rx_i),
                .data_valid_o(protocol_uart_valid), .data_o(protocol_uart_data),
                .frame_error_o(protocol_uart_error)
            );

            protocol_v02_parser u_protocol_parser (
                .clk_i(sys_clk_i), .rst_i(!por_done_q),
                .byte_valid_i(protocol_uart_valid), .byte_i(protocol_uart_data),
                .uart_error_i(protocol_uart_error),
                .command_valid_o(protocol_frame_valid),
                .command_error_o(protocol_frame_error),
                .array_o(protocol_array), .line_o(protocol_line),
                .chip_o(protocol_chip), .channel_o(protocol_channel),
                .enable_o(protocol_enable), .phase_o(protocol_phase),
                .attenuation_o(protocol_attenuation)
            );

            protocol_v02_controller #(
                .CID_MAP(CHIP_CID_MAP)
            ) u_protocol_controller (
                .clk_i(sys_clk_i), .rst_i(!por_done_q),
                .command_valid_i(protocol_frame_valid),
                .command_error_i(protocol_frame_error),
                .array_i(protocol_array), .line_i(protocol_line),
                .chip_i(protocol_chip), .channel_i(protocol_channel),
                .enable_i(protocol_enable), .phase_i(protocol_phase),
                .attenuation_i(protocol_attenuation),
                .core_init_done_i(core_init_done),
                .core_cmd_valid_o(protocol_cmd_valid),
                .core_cmd_ready_i(protocol_core_ready),
                .core_array_sel_o(protocol_cmd_array_sel),
                .core_line_mask_o(protocol_cmd_line_mask),
                .core_rx_frames_o(protocol_rx_frames),
                .core_tx_frames_o(protocol_tx_frames),
                .core_cmd_write_o(protocol_cmd_write),
                .core_cmd_load_o(protocol_cmd_load),
                .core_write_done_i(core_write_done),
                .core_load_done_i(core_load_done), .core_error_i(core_error),
                .rx_line_enable_o(protocol_rx_line_enable),
                .tx_line_enable_o(protocol_tx_line_enable),
                .busy_o(protocol_busy), .done_o(protocol_done),
                .error_o(protocol_error),
                .accepted_count_o(protocol_accepted_count),
                .completed_count_o(protocol_completed_count),
                .rejected_count_o(protocol_rejected_count)
            );
        end else begin : g_no_protocol_v02
            assign protocol_uart_valid       = 1'b0;
            assign protocol_uart_data        = 8'b0;
            assign protocol_uart_error       = 1'b0;
            assign protocol_frame_valid      = 1'b0;
            assign protocol_frame_error      = 1'b0;
            assign protocol_array            = 1'b0;
            assign protocol_line             = 3'b0;
            assign protocol_chip             = 2'b0;
            assign protocol_channel          = 2'b0;
            assign protocol_enable           = 1'b0;
            assign protocol_phase            = 6'b0;
            assign protocol_attenuation      = 6'b0;
            assign protocol_cmd_valid        = 1'b0;
            assign protocol_cmd_array_sel    = 2'b0;
            assign protocol_cmd_line_mask    = 8'b0;
            assign protocol_rx_frames        = 768'b0;
            assign protocol_tx_frames        = 768'b0;
            assign protocol_cmd_write        = 1'b0;
            assign protocol_cmd_load         = 1'b0;
            assign protocol_rx_line_enable   = 8'b0;
            assign protocol_tx_line_enable   = 8'b0;
            assign protocol_busy             = 1'b0;
            assign protocol_done             = 1'b0;
            assign protocol_error            = 1'b0;
            assign protocol_accepted_count   = 16'b0;
            assign protocol_completed_count  = 16'b0;
            assign protocol_rejected_count   = 16'b0;
        end
    endgenerate

    generate
        if (ENABLE_DEBUG_VIO) begin : g_debug_vio
            wire frame_we, submit_toggle, clear_status;
            wire [1:0] frame_array_sel, vio_cmd_array_sel;
            wire [2:0] line_index;
            wire [1:0] chip_index;
            wire [23:0] frame_data;
            wire [7:0] vio_cmd_line_mask;
            wire vio_cmd_write, vio_cmd_load;
            wire ack_toggle, adapter_pending, adapter_error;
            wire [15:0] write_count, load_count;
            wire [39:0] debug_status;

            assign debug_status = {
                write_count, load_count,
                core_init_done, core_busy, core_cmd_ready,
                core_write_done, core_load_done, core_error,
                adapter_pending, 1'b0
            };

            debug_vio_bridge u_debug_vio (
                .clk_i(sys_clk_i), .status_i(debug_status),
                .ack_toggle_i(ack_toggle), .adapter_error_i(adapter_error),
                .frame_we_o(frame_we), .frame_array_sel_o(frame_array_sel),
                .line_index_o(line_index), .chip_index_o(chip_index),
                .frame_data_o(frame_data), .submit_toggle_o(submit_toggle),
                .cmd_array_sel_o(vio_cmd_array_sel),
                .cmd_line_mask_o(vio_cmd_line_mask),
                .cmd_write_o(vio_cmd_write), .cmd_load_o(vio_cmd_load),
                .clear_status_o(clear_status)
            );

            debug_command_adapter u_debug_adapter (
                .clk_i(sys_clk_i), .rst_i(!por_done_q),
                .dbg_frame_we_i(frame_we),
                .dbg_frame_array_sel_i(frame_array_sel),
                .dbg_line_index_i(line_index), .dbg_chip_index_i(chip_index),
                .dbg_frame_data_i(frame_data),
                .dbg_submit_toggle_i(submit_toggle),
                .dbg_cmd_array_sel_i(vio_cmd_array_sel),
                .dbg_cmd_line_mask_i(vio_cmd_line_mask),
                .dbg_cmd_write_i(vio_cmd_write), .dbg_cmd_load_i(vio_cmd_load),
                .dbg_clear_status_i(clear_status),
                .dbg_ack_toggle_o(ack_toggle), .dbg_pending_o(adapter_pending),
                .dbg_error_sticky_o(adapter_error),
                .dbg_write_done_count_o(write_count),
                .dbg_load_done_count_o(load_count),
                .cmd_valid_o(debug_cmd_valid), .cmd_ready_i(debug_cmd_ready),
                .cmd_array_sel_o(debug_cmd_array_sel),
                .cmd_line_mask_o(debug_cmd_line_mask),
                .cmd_rx_frames_o(debug_rx_frames),
                .cmd_tx_frames_o(debug_tx_frames),
                .cmd_write_o(debug_cmd_write), .cmd_load_o(debug_cmd_load),
                .core_write_done_i(core_write_done),
                .core_load_done_i(core_load_done), .core_error_i(core_error)
            );
        end else begin : g_no_debug_vio
            assign debug_cmd_valid     = 1'b0;
            assign debug_cmd_array_sel = 2'b00;
            assign debug_cmd_line_mask = 8'h00;
            assign debug_rx_frames     = 768'b0;
            assign debug_tx_frames     = 768'b0;
            assign debug_cmd_write     = 1'b0;
            assign debug_cmd_load      = 1'b0;
        end
    endgenerate

    initial begin
        if (POR_CYCLES < 1) begin
            $error("POR_CYCLES must be at least 1");
        end
    end

    always @(posedge sys_clk_i) begin
        if (!por_done_q) begin
            if (por_count_q == POR_CYCLES - 1) begin
                por_done_q <= 1'b1;
            end else begin
                por_count_q <= por_count_q + 1'b1;
            end
        end
    end

    (* KEEP = "true" *) wire unused_inputs = ^{
        rx_sdo_i, tx_sdo_i, debug_rs485_rx_i, spare_rs485_rx_i
    };

    // V0.2 has no response frame. Keep the UART TX input at its idle mark.
    assign rs422_tx_o        = 1'b1;
    assign debug_rs485_tx_o  = 1'b0;
    assign debug_rs485_dir_o = 1'b0;
    assign spare_rs485_tx_o  = 1'b0;
    assign spare_rs485_dir_o = 1'b0;

    beam_ctrl_core #(
        .ENABLE_CHIP_INIT(1'b1),
        .CID_MAP(CHIP_CID_MAP),
        .SERIAL_HALF_PERIOD_CYCLES(SERIAL_HALF_PERIOD_CYCLES),
        .POST_FRAME_CLOCKS(POST_FRAME_CLOCKS),
        .RESET_CLK_CYCLES(RESET_CLK_CYCLES),
        .POST_RESET_CYCLES(POST_RESET_CYCLES),
        .CSB_TO_LDB_CYCLES(CSB_TO_LDB_CYCLES),
        .LDB_LOW_CYCLES(LDB_LOW_CYCLES)
    ) u_core (
        .clk_i(sys_clk_i), .rst_i(!por_done_q),
        .cmd_valid_i(selected_cmd_valid), .cmd_ready_o(core_cmd_ready),
        .cmd_array_sel_i(selected_cmd_array_sel),
        .cmd_line_mask_i(selected_cmd_line_mask),
        .cmd_rx_frames_i(selected_rx_frames), .cmd_tx_frames_i(selected_tx_frames),
        .cmd_write_i(selected_cmd_write), .cmd_load_i(selected_cmd_load),
        .busy_o(core_busy), .write_done_o(core_write_done),
        .load_done_o(core_load_done), .error_o(core_error),
        .init_done_o(core_init_done),
        .rx_sdi_o(core_rx_sdi), .rx_clk_o(core_rx_clk),
        .rx_csb_o(core_rx_csb), .rx_ldb_o(core_rx_ldb),
        .rx_rstn_o(core_rx_rstn),
        .tx_sdi_o(core_tx_sdi), .tx_clk_o(core_tx_clk),
        .tx_csb_o(core_tx_csb), .tx_ldb_o(core_tx_ldb),
        .tx_rstn_o(core_tx_rstn)
    );

    assign rx_sdi_o  = por_done_q ? core_rx_sdi  : 32'b0;
    assign rx_clk_o  = por_done_q ? core_rx_clk  : 8'b0;
    assign rx_csb_o  = por_done_q ? core_rx_csb  : 8'hff;
    assign rx_ldb_o  = por_done_q ? core_rx_ldb  : 8'hff;
    assign rx_rstn_o = por_done_q ? core_rx_rstn : 8'b0;
    assign rx_t_o    = 8'b0;
    assign rx_r_o    = (por_done_q && core_init_done) ? protocol_rx_line_enable : 8'b0;
    assign tx_sdi_o  = por_done_q ? core_tx_sdi  : 32'b0;
    assign tx_clk_o  = por_done_q ? core_tx_clk  : 8'b0;
    assign tx_csb_o  = por_done_q ? core_tx_csb  : 8'hff;
    assign tx_ldb_o  = por_done_q ? core_tx_ldb  : 8'hff;
    assign tx_rstn_o = por_done_q ? core_tx_rstn : 8'b0;
    assign tx_t_o    = (por_done_q && core_init_done) ? protocol_tx_line_enable : 8'b0;
    assign tx_r_o    = 8'b0;

endmodule
