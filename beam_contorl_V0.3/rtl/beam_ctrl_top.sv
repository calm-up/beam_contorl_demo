`timescale 1ns/1ps

// XC7A200T board wrapper. V0.3 RS422 owns the core command path.
module beam_ctrl_top #(
    parameter bit ENABLE_DEBUG_ILA = 1'b0,
    parameter int unsigned SYS_CLK_HZ = 50_000_000,
    parameter int unsigned UART_BAUD = 115_200,
    parameter logic [15:0] CHIP_CID_MAP = 16'h3210,
    parameter int unsigned POR_CYCLES = 4,
    parameter int unsigned SERIAL_HALF_PERIOD_CYCLES = 5,
    parameter int unsigned POST_FRAME_CLOCKS = 2,
    parameter int unsigned RESET_CLK_CYCLES = 128,
    parameter int unsigned POST_RESET_CYCLES = 10,
    parameter int unsigned CSB_TO_LDB_CYCLES = 10,
    parameter int unsigned LDB_LOW_CYCLES = 5
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
    localparam int unsigned POR_W = (POR_CYCLES < 2) ? 1 : $clog2(POR_CYCLES);
    logic [POR_W-1:0] por_count_q = '0;
    logic por_done_q = 1'b0;
    always_ff @(posedge sys_clk_i) if (!por_done_q) begin
        if (por_count_q == POR_CYCLES - 1) por_done_q <= 1'b1;
        else por_count_q <= por_count_q + 1'b1;
    end
    wire rst = !por_done_q;
    (* KEEP = "true" *) wire unused_inputs = ^{
        rx_sdo_i, tx_sdo_i, debug_rs485_rx_i, spare_rs485_rx_i
    };
    assign debug_rs485_tx_o = 1'b0;
    assign debug_rs485_dir_o = 1'b0;
    assign spare_rs485_tx_o = 1'b0;
    assign spare_rs485_dir_o = 1'b0;

    wire rx_byte_valid, rx_byte_error;
    wire [7:0] rx_byte;
    wire frame_valid, frame_error;
    wire [7:0] frame_error_status, frame_command, frame_array, payload_len;
    wire [447:0] frame_payload;
    wire [5:0] rx_index;
    uart_rx #(.CLK_HZ(SYS_CLK_HZ), .BAUD_RATE(UART_BAUD)) u_uart_rx (
        .clk_i(sys_clk_i), .rst_i(rst), .serial_i(rs422_rx_i),
        .data_valid_o(rx_byte_valid), .data_o(rx_byte), .frame_error_o(rx_byte_error)
    );
    protocol_v03_parser u_parser (
        .clk_i(sys_clk_i), .rst_i(rst), .byte_valid_i(rx_byte_valid),
        .byte_i(rx_byte), .uart_error_i(rx_byte_error),
        .frame_valid_o(frame_valid), .frame_error_o(frame_error),
        .error_status_o(frame_error_status), .command_o(frame_command),
        .array_o(frame_array), .payload_len_o(payload_len),
        .payload_o(frame_payload), .rx_index_o(rx_index)
    );

    wire channel_start, channel_array, channel_enable;
    wire [2:0] channel_line;
    wire [1:0] channel_chip, channel_index;
    wire [5:0] channel_phase, channel_atten;
    wire channel_busy, channel_done, channel_error;
    wire [7:0] channel_rx_enable, channel_tx_enable;
    wire channel_core_valid, channel_core_write, channel_core_load;
    wire [1:0] channel_core_array;
    wire [7:0] channel_core_lines;
    wire [767:0] channel_rx_frames, channel_tx_frames;
    wire [15:0] accepted_count, completed_count, rejected_count;
    wire core_ready, core_busy, core_write_done, core_load_done, core_error, core_init;
    wire clear_valid;
    wire [1:0] clear_array;
    wire [7:0] clear_lines;
    channel_executor #(.CID_MAP(CHIP_CID_MAP)) u_channel (
        .clk_i(sys_clk_i), .rst_i(rst), .command_valid_i(channel_start),
        .command_error_i(1'b0), .clear_valid_i(clear_valid),
        .clear_array_i(clear_array), .clear_lines_i(clear_lines),
        .array_i(channel_array), .line_i(channel_line),
        .chip_i(channel_chip), .channel_i(channel_index),
        .enable_i(channel_enable), .phase_i(channel_phase),
        .attenuation_i(channel_atten), .core_init_done_i(core_init),
        .core_cmd_valid_o(channel_core_valid), .core_cmd_ready_i(core_ready),
        .core_array_sel_o(channel_core_array), .core_line_mask_o(channel_core_lines),
        .core_rx_frames_o(channel_rx_frames), .core_tx_frames_o(channel_tx_frames),
        .core_cmd_write_o(channel_core_write), .core_cmd_load_o(channel_core_load),
        .core_write_done_i(core_write_done), .core_load_done_i(core_load_done),
        .core_error_i(core_error), .rx_line_enable_o(channel_rx_enable),
        .tx_line_enable_o(channel_tx_enable), .busy_o(channel_busy),
        .done_o(channel_done), .error_o(channel_error),
        .accepted_count_o(accepted_count), .completed_count_o(completed_count),
        .rejected_count_o(rejected_count)
    );

    wire reset_start, target_reset_busy, target_reset_done;
    wire [1:0] reset_array, active_reset_array;
    wire [7:0] reset_lines, active_reset_lines, target_reset_clk, target_reset_rstn;
    array_target_reset #(
        .HALF_PERIOD_CYCLES(SERIAL_HALF_PERIOD_CYCLES),
        .RESET_CLOCKS(RESET_CLK_CYCLES), .POST_CYCLES(POST_RESET_CYCLES)
    ) u_target_reset (
        .clk_i(sys_clk_i), .rst_i(rst), .start_i(reset_start),
        .array_sel_i(reset_array), .line_mask_i(reset_lines),
        .busy_o(target_reset_busy), .done_o(target_reset_done),
        .active_array_o(active_reset_array), .active_lines_o(active_reset_lines),
        .clk_o(target_reset_clk), .rstn_o(target_reset_rstn)
    );

    wire response_start, response_ready, response_done, response_extra_valid;
    wire [7:0] response_array, response_command, response_status, response_byte;
    wire [39:0] response_extra;
    wire response_byte_valid;
    protocol_v03_response #(.CLK_HZ(SYS_CLK_HZ), .BAUD_RATE(UART_BAUD)) u_response (
        .clk_i(sys_clk_i), .rst_i(rst), .start_i(response_start),
        .array_i(response_array), .original_command_i(response_command),
        .status_i(response_status), .extra_valid_i(response_extra_valid),
        .extra_i(response_extra), .ready_o(response_ready), .done_o(response_done),
        .tx_byte_valid_o(response_byte_valid), .tx_byte_o(response_byte),
        .serial_o(rs422_tx_o)
    );
    wire [7:0] rx_gate, tx_gate;
    wire dispatcher_busy;
    wire [3:0] dispatcher_state;
    protocol_v03_dispatcher u_dispatcher (
        .clk_i(sys_clk_i), .rst_i(rst), .frame_valid_i(frame_valid),
        .frame_error_i(frame_error), .command_i(frame_command),
        .array_i(frame_array), .payload_len_i(payload_len),
        .payload_i(frame_payload), .init_done_i(core_init),
        .core_ready_i(core_ready), .channel_busy_i(channel_busy),
        .channel_done_i(channel_done), .channel_error_i(channel_error),
        .rx_enable_i(channel_rx_enable), .tx_enable_i(channel_tx_enable),
        .reset_busy_i(target_reset_busy), .reset_done_i(target_reset_done),
        .response_ready_i(response_ready), .response_done_i(response_done),
        .channel_start_o(channel_start), .channel_array_o(channel_array),
        .channel_line_o(channel_line), .channel_chip_o(channel_chip),
        .channel_index_o(channel_index), .channel_enable_o(channel_enable),
        .channel_phase_o(channel_phase), .channel_atten_o(channel_atten),
        .clear_valid_o(clear_valid), .clear_array_o(clear_array),
        .clear_lines_o(clear_lines), .reset_start_o(reset_start),
        .reset_array_o(reset_array), .reset_lines_o(reset_lines),
        .rx_gate_o(rx_gate), .tx_gate_o(tx_gate),
        .response_start_o(response_start), .response_array_o(response_array),
        .response_command_o(response_command), .response_status_o(response_status),
        .response_extra_valid_o(response_extra_valid),
        .response_extra_o(response_extra), .busy_o(dispatcher_busy),
        .state_probe_o(dispatcher_state)
    );

    wire [31:0] core_rx_sdi, core_tx_sdi;
    wire [7:0] core_rx_clk, core_rx_csb, core_rx_ldb, core_rx_rstn;
    wire [7:0] core_tx_clk, core_tx_csb, core_tx_ldb, core_tx_rstn;
    beam_ctrl_core #(
        .SERIAL_HALF_PERIOD_CYCLES(SERIAL_HALF_PERIOD_CYCLES),
        .POST_FRAME_CLOCKS(POST_FRAME_CLOCKS),
        .RESET_CLK_CYCLES(RESET_CLK_CYCLES),
        .POST_RESET_CYCLES(POST_RESET_CYCLES),
        .CSB_TO_LDB_CYCLES(CSB_TO_LDB_CYCLES),
        .LDB_LOW_CYCLES(LDB_LOW_CYCLES)
    ) u_core (
        .clk_i(sys_clk_i), .rst_i(rst),
        .cmd_valid_i(channel_core_valid && !target_reset_busy),
        .cmd_ready_o(core_ready), .cmd_array_sel_i(channel_core_array),
        .cmd_line_mask_i(channel_core_lines),
        .cmd_rx_frames_i(channel_rx_frames), .cmd_tx_frames_i(channel_tx_frames),
        .cmd_write_i(channel_core_write), .cmd_load_i(channel_core_load),
        .busy_o(core_busy), .write_done_o(core_write_done),
        .load_done_o(core_load_done), .error_o(core_error),
        .init_done_o(core_init), .rx_sdi_o(core_rx_sdi),
        .rx_clk_o(core_rx_clk), .rx_csb_o(core_rx_csb),
        .rx_ldb_o(core_rx_ldb), .rx_rstn_o(core_rx_rstn),
        .tx_sdi_o(core_tx_sdi), .tx_clk_o(core_tx_clk),
        .tx_csb_o(core_tx_csb), .tx_ldb_o(core_tx_ldb),
        .tx_rstn_o(core_tx_rstn)
    );

    genvar line, chip;
    generate for (line=0;line<8;line=line+1) begin : g_line
        wire reset_rx = target_reset_busy && active_reset_array[0] && active_reset_lines[line];
        wire reset_tx = target_reset_busy && active_reset_array[1] && active_reset_lines[line];
        assign rx_clk_o[line] = por_done_q && (reset_rx ? target_reset_clk[line] : core_rx_clk[line]);
        assign rx_csb_o[line] = !por_done_q || reset_rx ? 1'b1 : core_rx_csb[line];
        assign rx_ldb_o[line] = !por_done_q || reset_rx ? 1'b1 : core_rx_ldb[line];
        assign rx_rstn_o[line] = por_done_q ? (reset_rx ? target_reset_rstn[line] : core_rx_rstn[line]) : 1'b0;
        assign rx_t_o[line] = 1'b0;
        assign rx_r_o[line] = por_done_q && core_init && !reset_rx &&
                              rx_gate[line] && channel_rx_enable[line];
        assign tx_clk_o[line] = por_done_q && (reset_tx ? target_reset_clk[line] : core_tx_clk[line]);
        assign tx_csb_o[line] = !por_done_q || reset_tx ? 1'b1 : core_tx_csb[line];
        assign tx_ldb_o[line] = !por_done_q || reset_tx ? 1'b1 : core_tx_ldb[line];
        assign tx_rstn_o[line] = por_done_q ? (reset_tx ? target_reset_rstn[line] : core_tx_rstn[line]) : 1'b0;
        assign tx_t_o[line] = por_done_q && core_init && !reset_tx &&
                              tx_gate[line] && channel_tx_enable[line];
        assign tx_r_o[line] = 1'b0;
        for (chip=0;chip<4;chip=chip+1) begin : g_chip
            assign rx_sdi_o[line*4+chip] = por_done_q && !reset_rx ? core_rx_sdi[line*4+chip] : 1'b0;
            assign tx_sdi_o[line*4+chip] = por_done_q && !reset_tx ? core_tx_sdi[line*4+chip] : 1'b0;
        end
    end endgenerate

    // Two small debug cores: byte/transaction events and continuous J1 waveform.
    // Both sample the free-running 50 MHz FPGA clock.
    generate if (ENABLE_DEBUG_ILA) begin : g_ila
        ila_v03_protocol u_ila_protocol (
            .clk(sys_clk_i), .probe0(rx_byte), .probe1(rx_byte_valid),
            .probe2(rx_index), .probe3(frame_command), .probe4(dispatcher_state),
            .probe5(response_status), .probe6(response_byte),
            .probe7(response_byte_valid), .probe8({frame_valid,frame_error,channel_done,channel_error})
        );
        ila_v03_array u_ila_array (
            .clk(sys_clk_i), .probe0(rx_sdi_o[3:0]), .probe1(rx_clk_o[0]),
            .probe2(rx_csb_o[0]), .probe3(rx_ldb_o[0]), .probe4(rx_rstn_o[0]),
            .probe5(rx_r_o[0]), .probe6(channel_rx_frames[23:0]),
            .probe7({channel_start,channel_busy,core_write_done,core_load_done,
                     reset_start,target_reset_busy,target_reset_done,core_error})
        );
    end endgenerate
endmodule
