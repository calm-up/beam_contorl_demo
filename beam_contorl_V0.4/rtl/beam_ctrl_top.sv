`timescale 1ns/1ps

// XC7A200T board wrapper. J21 and J18 RS485 share the V0.3 command path.
module beam_ctrl_top #(
    parameter bit ENABLE_DEBUG_ILA = 1'b0,
    parameter bit ENABLE_CHIP_INIT = 1'b1,
    parameter int unsigned SYS_CLK_HZ = 50_000_000,
    parameter int unsigned UART_BAUD = 115_200,
    parameter logic [15:0] CHIP_CID_MAP = 16'h3210,
    parameter int unsigned POR_CYCLES = 4,
    parameter int unsigned SERIAL_HALF_PERIOD_CYCLES = 5,
    parameter int unsigned POST_FRAME_CLOCKS = 2,
    parameter int unsigned RESET_CLK_CYCLES = 128,
    parameter int unsigned POST_RESET_CYCLES = 10,
    parameter int unsigned CSB_TO_LDB_CYCLES = 10,
    parameter int unsigned LDB_LOW_CYCLES = 6 * SERIAL_HALF_PERIOD_CYCLES,
    parameter int unsigned SYNC_SETTLE_CYCLES = 50
) (
    input  wire        sys_clk_i,
    input  wire [7:0]  rx_sdo_i,
    input  wire [7:0]  tx_sdo_i,
    input  wire        rs422_rx_i,
    output wire        rs422_tx_o,
    input  wire        sync_clk_i,
    input  wire        wavefront_i,
    input  wire        beam_apply_i,
    input  wire        external_t_i,
    input  wire        external_r_i,
    input  wire        debug_rs485_rx_i,
    output wire        debug_rs485_tx_o,
    output wire        debug_rs485_dir_o,
    input  wire        spare_rs485_rx_i,
    output wire        spare_rs485_tx_o,
    output wire        spare_rs485_dir_o,
    output wire        u22_cs_n_o,
    output wire        u22_sck_o,
    output wire        u22_mosi_o,
    input  wire        u22_miso_i,
    output wire        u22_wp_n_o,
    output wire        u22_hold_n_o,
    output wire [31:0] rx_sdi_o,    //jieshou 每颗芯片配1位
    output wire [7:0]  rx_clk_o,
    output wire [7:0]  rx_csb_o,
    output wire [7:0]  rx_ldb_o,
    output wire [7:0]  rx_rstn_o,
    output wire [7:0]  rx_t_o,
    output wire [7:0]  rx_r_o,
    
    output wire [31:0] tx_sdi_o,    //fashe
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
    wire sync_owns, sync_write, sync_load, sync_tr_hold, sync_apply_rejected;
    wire channel_enable_only;
    wire sync_enable_start;
    wire [7:0] sync_enable_target;
    wire [1:0] sync_external;
    wire [1:0] sync_array, sync_applied;
    wire [7:0] sync_lines;
    wire [767:0] sync_frames;

    // U22 is independent of the U5 configuration Flash. Writes require the
    // exact expected JEDEC ID and are confined to the selected U22 half.
    wire flash_spi_busy, flash_spi_done, flash_spi_start;
    wire [5:0] flash_tx_count, flash_rx_count;
    wire [255:0] flash_tx_data, flash_rx_data;
    wire [23:0] flash_jedec_id;
    wire flash_probe_done, flash_probe_valid;
    wire probe_spi_start, device_spi_start;
    wire [5:0] probe_tx_count, probe_rx_count, device_tx_count, device_rx_count;
    wire [255:0] probe_tx_data, device_tx_data;
    wire flash_start, flash_array, flash_busy, flash_done, flash_error;
    wire [7:0] flash_command;
    wire [95:0] flash_payload;
    wire device_request, device_busy, device_done, device_error;
    wire [1:0] device_operation;
    wire [23:0] device_address;
    wire [4:0] device_length;
    wire [127:0] device_write_data, device_read_data;
    wire [10:0] flash_loaded_count;
    wire [23:0] flash_cache_sample;
    assign flash_spi_start = flash_probe_done ? device_spi_start : probe_spi_start;
    assign flash_tx_count = flash_probe_done ? device_tx_count : probe_tx_count;
    assign flash_rx_count = flash_probe_done ? device_rx_count : probe_rx_count;
    assign flash_tx_data = flash_probe_done ? device_tx_data : probe_tx_data;
    assign u22_wp_n_o = 1'b1;
    assign u22_hold_n_o = 1'b1;
    u22_flash_probe u_flash_probe (
        .clk_i(sys_clk_i), .rst_i(rst), .spi_busy_i(flash_spi_busy),
        .spi_done_i(flash_spi_done), .spi_rx_i(flash_rx_data),
        .spi_start_o(probe_spi_start), .spi_tx_count_o(probe_tx_count),
        .spi_rx_count_o(probe_rx_count), .spi_tx_o(probe_tx_data),
        .jedec_id_o(flash_jedec_id), .probe_done_o(flash_probe_done),
        .probe_valid_o(flash_probe_valid)
    );
    u22_flash_device u_flash_device (
        .clk_i(sys_clk_i), .rst_i(rst), .probe_done_i(flash_probe_done),
        .jedec_id_i(flash_jedec_id), .request_i(device_request),
        .operation_i(device_operation), .address_i(device_address),
        .length_i(device_length), .write_data_i(device_write_data),
        .spi_busy_i(flash_spi_busy), .spi_done_i(flash_spi_done),
        .spi_rx_i(flash_rx_data), .spi_start_o(device_spi_start),
        .spi_tx_count_o(device_tx_count), .spi_rx_count_o(device_rx_count),
        .spi_tx_data_o(device_tx_data), .busy_o(device_busy),
        .done_o(device_done), .error_o(device_error),
        .read_data_o(device_read_data)
    );
    u22_flash_record_service u_flash_records (
        .clk_i(sys_clk_i), .rst_i(rst), .start_i(flash_start),
        .command_i(flash_command), .array_i(flash_array),
        .payload_i(flash_payload), .device_busy_i(device_busy),
        .device_done_i(device_done), .device_error_i(device_error),
        .device_read_data_i(device_read_data),
        .device_request_o(device_request), .device_operation_o(device_operation),
        .device_address_o(device_address), .device_length_o(device_length),
        .device_write_data_o(device_write_data), .busy_o(flash_busy),
        .done_o(flash_done), .error_o(flash_error),
        .loaded_count_o(flash_loaded_count),
        .cache_sample_o(flash_cache_sample)
    );
    u22_spi_master u_flash_spi (
        .clk_i(sys_clk_i), .rst_i(rst), .start_i(flash_spi_start),
        .tx_count_i(flash_tx_count), .rx_count_i(flash_rx_count),
        .tx_data_i(flash_tx_data), .miso_i(u22_miso_i),
        .cs_n_o(u22_cs_n_o), .sck_o(u22_sck_o),
        .mosi_o(u22_mosi_o), .busy_o(flash_spi_busy),
        .done_o(flash_spi_done), .rx_data_o(flash_rx_data)
    );

    wire [1:0] rx_byte_valid, rx_byte_error;
    wire dispatcher_busy;
    wire [7:0] rx_byte [0:1];
    wire [1:0] port_frame_valid, port_frame_error;
    wire [7:0] port_command [0:1], port_array [0:1], port_payload_len [0:1];
    wire [447:0] port_payload [0:1];
    wire [5:0] port_rx_index [0:1];
    logic active_port_q;
    wire select_debug = !sync_owns && !dispatcher_busy && port_frame_valid[0];
    wire select_spare = !sync_owns && !dispatcher_busy && !port_frame_valid[0] && port_frame_valid[1];
    wire frame_valid, frame_error;
    wire [7:0] frame_error_status, frame_command, frame_array, payload_len;
    wire [447:0] frame_payload;
    wire [5:0] rx_index;
    genvar port;
    generate for (port=0;port<2;port=port+1) begin : g_receive
        uart_rx #(.CLK_HZ(SYS_CLK_HZ), .BAUD_RATE(UART_BAUD)) u_uart_rx (
            .clk_i(sys_clk_i), .rst_i(rst),
            .serial_i(port == 0 ? debug_rs485_rx_i : spare_rs485_rx_i),
            .data_valid_o(rx_byte_valid[port]), .data_o(rx_byte[port]),
            .frame_error_o(rx_byte_error[port])
        );
        protocol_v03_parser u_parser (
            .clk_i(sys_clk_i), .rst_i(rst), .byte_valid_i(rx_byte_valid[port]),
            .byte_i(rx_byte[port]), .uart_error_i(rx_byte_error[port]),
            .frame_valid_o(port_frame_valid[port]),
            .frame_error_o(port_frame_error[port]), .error_status_o(),
            .command_o(port_command[port]), .array_o(port_array[port]),
            .payload_len_o(port_payload_len[port]),
            .payload_o(port_payload[port]), .rx_index_o(port_rx_index[port])
        );
    end endgenerate
    assign frame_valid = select_debug || select_spare;
    assign frame_error = |port_frame_error;
    assign frame_error_status = 8'h02;
    assign frame_command = select_debug ? port_command[0] : port_command[1];
    assign frame_array = select_debug ? port_array[0] : port_array[1];
    assign payload_len = select_debug ? port_payload_len[0] : port_payload_len[1];
    assign frame_payload = select_debug ? port_payload[0] : port_payload[1];
    assign rx_index = port_rx_index[0];
    always_ff @(posedge sys_clk_i) begin
        if (rst) active_port_q <= 1'b0;
        else if (frame_valid) active_port_q <= select_spare;
    end

    wire channel_start, channel_array, channel_enable;
    wire [2:0] channel_line;
    wire [1:0] channel_chip, channel_index;
    wire [5:0] channel_phase, channel_atten;
    wire channel_busy, channel_done, channel_error;
    wire beam_calc_start, beam_batch_start, beam_array;
    wire [15:0] beam_frequency;
    wire signed [15:0] beam_azimuth, beam_elevation;
    wire [7:0] beam_lines;
    wire [3:0] beam_chips, beam_channels;
    wire [767:0] beam_phase;
    wire [127:0] beam_enable;
    wire beam_calc_busy, beam_calc_done, beam_batch_done, beam_batch_error;
    wire [7:0] channel_rx_enable, channel_tx_enable;
    wire channel_core_valid, channel_core_write, channel_core_load;
    wire [1:0] channel_core_array;
    wire [7:0] channel_core_lines;
    wire [767:0] channel_rx_frames, channel_tx_frames;
    wire [15:0] accepted_count, completed_count, rejected_count;
    wire core_ready, core_busy, core_write_done, core_load_done, core_error, core_init;
    wire core_reset_done, core_init_fault;
    wire read_start, read_array, read_busy, read_done, read_error;
    wire [2:0] read_line, read_function;
    wire [1:0] read_chip, read_core_array;
    wire [7:0] read_address, read_core_lines;
    wire [23:0] read_value;
    wire [767:0] read_core_frames;
    wire read_core_valid;
    wire [191:0] core_rx_sdo_last, core_tx_sdo_last;
    wire clear_valid;
    wire [1:0] clear_array;
    wire [7:0] clear_lines;
    beam_phase_calc u_beam_calc (
        .clk_i(sys_clk_i), .rst_i(rst), .start_i(beam_calc_start),
        .frequency_i(beam_frequency), .azimuth_i(beam_azimuth),
        .elevation_i(beam_elevation), .line_mask_i(beam_lines),
        .chip_mask_i(beam_chips), .channel_mask_i(beam_channels),
        .busy_o(beam_calc_busy), .done_o(beam_calc_done),
        .phase_codes_o(beam_phase), .enable_bits_o(beam_enable)
    );
    channel_executor #(.CID_MAP(CHIP_CID_MAP)) u_channel (
        .clk_i(sys_clk_i), .rst_i(rst), .command_valid_i(channel_start || sync_enable_start),
        .enable_only_i(channel_enable_only || sync_enable_start),
        .batch_valid_i(beam_batch_start), .batch_array_i(beam_array),
        .batch_phase_i(beam_phase), .batch_enable_i(beam_enable),
        .batch_done_o(beam_batch_done), .batch_error_o(beam_batch_error),
        .command_error_i(1'b0), .clear_valid_i(clear_valid),
        .clear_array_i(clear_array), .clear_lines_i(clear_lines),
        .array_i(sync_enable_start ? sync_array[1] : channel_array),
        .line_i(sync_enable_start ? sync_enable_target[7:5] : channel_line),
        .chip_i(sync_enable_start ? sync_enable_target[4:3] : channel_chip),
        .channel_i(sync_enable_start ? sync_enable_target[2:1] : channel_index),
        .enable_i(sync_enable_start ? sync_enable_target[0] : channel_enable),
        .phase_i(channel_phase),
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
    chip_sdo_reader #(.CID_MAP(CHIP_CID_MAP),
                      .TIMEOUT_CYCLES(SYS_CLK_HZ/10)) u_sdo_reader (
        .clk_i(sys_clk_i), .rst_i(rst), .start_i(read_start),
        .array_i(read_array), .line_i(read_line), .chip_i(read_chip),
        .function_i(read_function), .address_i(read_address),
        .core_ready_i(core_ready), .core_write_done_i(core_write_done),
        .core_error_i(core_error), .rx_sdo_last_i(core_rx_sdo_last),
        .tx_sdo_last_i(core_tx_sdo_last), .core_valid_o(read_core_valid),
        .core_array_o(read_core_array), .core_lines_o(read_core_lines),
        .core_frames_o(read_core_frames), .busy_o(read_busy),
        .done_o(read_done), .error_o(read_error), .value_o(read_value)
    );
    wire reset_start, target_reset_busy, target_reset_done;
    wire [1:0] reset_array, active_reset_array;
    wire [7:0] reset_lines, active_reset_lines, target_reset_clk, target_reset_rstn;
    array_target_reset #(
        .HALF_PERIOD_CYCLES(SERIAL_HALF_PERIOD_CYCLES),
        .RESET_CLOCKS(RESET_CLK_CYCLES), .POST_CYCLES(POST_RESET_CYCLES)
    ) u_target_reset (
        .clk_i(sys_clk_i), .rst_i(rst), .start_i(reset_start),
        .serial_clk_i(core_rx_clk[0]),
        .array_sel_i(reset_array), .line_mask_i(reset_lines),
        .busy_o(target_reset_busy), .done_o(target_reset_done),
        .active_array_o(active_reset_array), .active_lines_o(active_reset_lines),
        .clk_o(target_reset_clk), .rstn_o(target_reset_rstn)
    );

    wire response_start, response_ready, response_done, response_extra_valid;
    wire [7:0] response_array, response_command, response_status, response_byte;
    wire [39:0] response_extra;
    wire response_byte_valid;
    wire [1:0] port_main_ready, port_main_done, port_response_byte_valid;
    wire [7:0] port_response_byte [0:1];
    assign response_ready = active_port_q ? port_main_ready[1] : port_main_ready[0];
    assign response_done = active_port_q ? port_main_done[1] : port_main_done[0];
    assign response_byte_valid = active_port_q ?
                                 port_response_byte_valid[1] : port_response_byte_valid[0];
    assign response_byte = active_port_q ? port_response_byte[1] : port_response_byte[0];
    protocol_v03_rs485_port #(.CLK_HZ(SYS_CLK_HZ), .BAUD_RATE(UART_BAUD)) u_debug_port (
        .clk_i(sys_clk_i), .rst_i(rst), .main_start_i(response_start && !active_port_q),
        .main_array_i(response_array), .main_command_i(response_command),
        .main_status_i(response_status), .main_extra_valid_i(response_extra_valid),
        .main_extra_i(response_extra), .main_ready_o(port_main_ready[0]),
        .main_done_o(port_main_done[0]),
        .busy_request_i(port_frame_valid[0] && !select_debug),
        .busy_array_i(port_array[0]), .busy_command_i(port_command[0]),
        .tx_o(debug_rs485_tx_o), .dir_o(debug_rs485_dir_o),
        .tx_byte_valid_o(port_response_byte_valid[0]),
        .tx_byte_o(port_response_byte[0])
    );
    protocol_v03_rs485_port #(.CLK_HZ(SYS_CLK_HZ), .BAUD_RATE(UART_BAUD)) u_spare_port (
        .clk_i(sys_clk_i), .rst_i(rst), .main_start_i(response_start && active_port_q),
        .main_array_i(response_array), .main_command_i(response_command),
        .main_status_i(response_status), .main_extra_valid_i(response_extra_valid),
        .main_extra_i(response_extra), .main_ready_o(port_main_ready[1]),
        .main_done_o(port_main_done[1]),
        .busy_request_i(port_frame_valid[1] && !select_spare),
        .busy_array_i(port_array[1]), .busy_command_i(port_command[1]),
        .tx_o(spare_rs485_tx_o), .dir_o(spare_rs485_dir_o),
        .tx_byte_valid_o(port_response_byte_valid[1]),
        .tx_byte_o(port_response_byte[1])
    );
    wire [7:0] rx_gate, tx_gate;
    wire [7:0] rx_pulse_mode, tx_pulse_mode;
    wire pulse_tx_active, pulse_rx_active;
    wire external_tx_mode = sync_external[1] || tx_pulse_mode == 8'hFF;
    wire external_rx_mode = sync_external[0] || rx_pulse_mode == 8'hFF;
    wire external_mode = external_tx_mode || external_rx_mode;
    (* ASYNC_REG = "TRUE" *) logic [1:0] external_t_q, external_r_q;
    logic external_tx_active, external_rx_active;
    logic [3:0] tr_guard_q;
    always_ff @(posedge sys_clk_i) begin
        if (rst) begin
            external_t_q <= 0;
            external_r_q <= 0;
            external_tx_active <= 0;
            external_rx_active <= 0;
            tr_guard_q <= 0;
        end else begin
            external_t_q <= {external_t_q[0], external_t_i};
            external_r_q <= {external_r_q[0], external_r_i};
            if (external_tx_active || external_rx_active) begin
                if (sync_tr_hold || !external_mode ||
                    (external_tx_active && (!external_t_q[1] || external_r_q[1])) ||
                    (external_rx_active && (!external_r_q[1] || external_t_q[1]))) begin
                    external_tx_active <= 0;
                    external_rx_active <= 0;
                    tr_guard_q <= 10;
                end
            end else if (tr_guard_q != 0) tr_guard_q <= tr_guard_q - 1'b1;
            else if (external_mode && !sync_tr_hold) begin
                external_tx_active <= external_t_q[1] && !external_r_q[1];
                external_rx_active <= external_r_q[1] && !external_t_q[1];
            end
        end
    end
    wire tx_window = external_mode ?
        (external_tx_mode && sync_applied[1] && external_tx_active) : pulse_tx_active;
    wire rx_window = external_mode ?
        (external_rx_mode && sync_applied[0] && external_rx_active) : pulse_rx_active;
    pulse_gate_110 u_rx_pulse_gate (
        .clk_i(sys_clk_i), .rst_i(rst), .mode_i(rx_pulse_mode),
        .tx_active_o(), .rx_active_o(pulse_rx_active)
    );
    pulse_gate_110 u_tx_pulse_gate (
        .clk_i(sys_clk_i), .rst_i(rst), .mode_i(tx_pulse_mode),
        .tx_active_o(pulse_tx_active), .rx_active_o()
    );
    wire [3:0] dispatcher_state;
    protocol_v03_dispatcher u_dispatcher (
        .clk_i(sys_clk_i), .rst_i(rst), .frame_valid_i(frame_valid),
        .enable_config_allowed_i(!tx_window && !rx_window &&
                                 !external_t_q[1] && !external_r_q[1]),
        .channel_enable_only_o(channel_enable_only),
        .frame_error_i(frame_error || sync_apply_rejected), .command_i(frame_command),
        .array_i(frame_array), .payload_len_i(payload_len),
        .payload_i(frame_payload), .init_done_i(core_init),
        .chip_reset_done_i(core_reset_done), .init_fault_i(core_init_fault),
        .core_ready_i(core_ready), .channel_busy_i(channel_busy),
        .channel_done_i(channel_done), .channel_error_i(channel_error),
        .beam_calc_busy_i(beam_calc_busy), .beam_calc_done_i(beam_calc_done),
        .batch_busy_i(channel_busy), .batch_done_i(beam_batch_done),
        .batch_error_i(beam_batch_error),
        .rx_enable_i(channel_rx_enable), .tx_enable_i(channel_tx_enable),
        .reset_busy_i(target_reset_busy), .reset_done_i(target_reset_done),
        .response_ready_i(response_ready), .response_done_i(response_done),
        .flash_probe_done_i(flash_probe_done),
        .flash_probe_valid_i(flash_probe_valid),
        .flash_busy_i(flash_busy), .flash_done_i(flash_done),
        .flash_error_i(flash_error),
        .flash_loaded_count_i(flash_loaded_count),
        .flash_cache_sample_i(flash_cache_sample),
        .read_done_i(read_done), .read_error_i(read_error),
        .read_value_i(read_value), .read_start_o(read_start),
        .read_array_o(read_array), .read_line_o(read_line),
        .read_chip_o(read_chip), .read_function_o(read_function),
        .read_address_o(read_address),
        .channel_start_o(channel_start), .channel_array_o(channel_array),
        .channel_line_o(channel_line), .channel_chip_o(channel_chip),
        .channel_index_o(channel_index), .channel_enable_o(channel_enable),
        .channel_phase_o(channel_phase), .channel_atten_o(channel_atten),
        .beam_calc_start_o(beam_calc_start), .beam_batch_start_o(beam_batch_start),
        .beam_array_o(beam_array), .beam_frequency_o(beam_frequency),
        .beam_azimuth_o(beam_azimuth), .beam_elevation_o(beam_elevation),
        .beam_lines_o(beam_lines), .beam_chips_o(beam_chips),
        .beam_channels_o(beam_channels),
        .clear_valid_o(clear_valid), .clear_array_o(clear_array),
        .clear_lines_o(clear_lines), .reset_start_o(reset_start),
        .reset_array_o(reset_array), .reset_lines_o(reset_lines),
        .rx_gate_o(rx_gate), .tx_gate_o(tx_gate),
        .rx_pulse_mode_o(rx_pulse_mode),
        .tx_pulse_mode_o(tx_pulse_mode),
        .flash_start_o(flash_start), .flash_command_o(flash_command),
        .flash_array_o(flash_array), .flash_payload_o(flash_payload),
        .response_start_o(response_start), .response_array_o(response_array),
        .response_command_o(response_command), .response_status_o(response_status),
        .response_extra_valid_o(response_extra_valid),
        .response_extra_o(response_extra), .busy_o(dispatcher_busy),
        .state_probe_o(dispatcher_state)
    );

    wire [31:0] core_rx_sdi, core_tx_sdi;
    wire [7:0] core_rx_clk, core_rx_csb, core_rx_ldb, core_rx_rstn;
    wire [7:0] core_tx_clk, core_tx_csb, core_tx_ldb, core_tx_rstn;
    sync_ap_batch #(
        .CID_MAP(CHIP_CID_MAP), .PRELOAD_GUARD(CSB_TO_LDB_CYCLES),
        .SETTLE_CYCLES(SYNC_SETTLE_CYCLES)
    ) u_sync (
        .clk_i(sys_clk_i), .rst_i(rst), .sclk_i(sync_clk_i),
        .wave_i(wavefront_i), .data_i(rs422_rx_i), .data_o(rs422_tx_o),
        .apply_i(beam_apply_i),
        .available_i(core_init && !core_init_fault && !dispatcher_busy &&
                     !target_reset_busy && core_ready),
        .core_ready_i(core_ready), .write_done_i(core_write_done),
        .load_done_i(core_load_done), .core_error_i(core_error),
        .tr_active_i(external_t_q[1] || external_r_q[1] ||
                     tx_window || rx_window),
        .invalidate_i(reset_start || (channel_start && !channel_enable_only) || beam_batch_start),
        .enable_done_i(channel_done), .enable_error_i(channel_error),
        .enable_start_o(sync_enable_start), .enable_target_o(sync_enable_target),
        .external_configured_o(sync_external),
        .owns_core_o(sync_owns), .write_o(sync_write), .load_o(sync_load),
        .array_o(sync_array), .lines_o(sync_lines), .frames_o(sync_frames),
        .applied_o(sync_applied), .tr_hold_o(sync_tr_hold),
        .apply_rejected_o(sync_apply_rejected)
    );
    beam_ctrl_core #(
        .ENABLE_CHIP_INIT(ENABLE_CHIP_INIT), .CID_MAP(CHIP_CID_MAP),
        .SERIAL_HALF_PERIOD_CYCLES(SERIAL_HALF_PERIOD_CYCLES),
        .POST_FRAME_CLOCKS(POST_FRAME_CLOCKS),
        .RESET_CLK_CYCLES(RESET_CLK_CYCLES),
        .POST_RESET_CYCLES(POST_RESET_CYCLES),
        .CSB_TO_LDB_CYCLES(CSB_TO_LDB_CYCLES),
        .LDB_LOW_CYCLES(LDB_LOW_CYCLES)
    ) u_core (
        .clk_i(sys_clk_i), .rst_i(rst),
        .reinit_start_i(target_reset_done),
        .reinit_array_i(active_reset_array), .reinit_lines_i(active_reset_lines),
        .cmd_valid_i((sync_write || sync_load || channel_core_valid || read_core_valid) && !target_reset_busy),
        .cmd_ready_o(core_ready),
        .cmd_array_sel_i((sync_write || sync_load) ? sync_array :
                         read_core_valid ? read_core_array : channel_core_array),
        .cmd_line_mask_i((sync_write || sync_load) ? sync_lines :
                         read_core_valid ? read_core_lines : channel_core_lines),
        .cmd_rx_frames_i(sync_write ? sync_frames :
                         read_core_valid ? read_core_frames : channel_rx_frames),
        .cmd_tx_frames_i(sync_write ? sync_frames :
                         read_core_valid ? read_core_frames : channel_tx_frames),
        .cmd_write_i(sync_write || read_core_valid || channel_core_write),
        .cmd_load_i(sync_load || (!read_core_valid && channel_core_load)),
        .busy_o(core_busy), .write_done_o(core_write_done),
        .load_done_o(core_load_done), .error_o(core_error),
        .init_done_o(core_init), .reset_done_o(core_reset_done),
        .init_fault_o(core_init_fault),
        .rx_sdo_i(rx_sdo_i), .tx_sdo_i(tx_sdo_i),
        .rx_sdo_last_o(core_rx_sdo_last), .tx_sdo_last_o(core_tx_sdo_last),
        .rx_sdi_o(core_rx_sdi),
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
        assign rx_clk_o[line] = por_done_q && core_rx_clk[line];
        assign rx_csb_o[line] = !por_done_q || reset_rx ? 1'b1 : core_rx_csb[line];
        assign rx_ldb_o[line] = !por_done_q || reset_rx ? 1'b1 : core_rx_ldb[line];
        assign rx_rstn_o[line] = por_done_q ? (reset_rx ? target_reset_rstn[line] : core_rx_rstn[line]) : 1'b0;
        assign rx_t_o[line] = 1'b0;
        assign rx_r_o[line] = por_done_q && core_init && !reset_rx &&
                              (rx_gate[line] || sync_external[0]) &&
                              channel_rx_enable[line] && rx_window && !sync_tr_hold &&
                              !(channel_busy && channel_enable_only);
        assign tx_clk_o[line] = por_done_q && core_tx_clk[line];
        assign tx_csb_o[line] = !por_done_q || reset_tx ? 1'b1 : core_tx_csb[line];
        assign tx_ldb_o[line] = !por_done_q || reset_tx ? 1'b1 : core_tx_ldb[line];
        assign tx_rstn_o[line] = por_done_q ? (reset_tx ? target_reset_rstn[line] : core_tx_rstn[line]) : 1'b0;
        assign tx_t_o[line] = por_done_q && core_init && !reset_tx &&
                              (tx_gate[line] || sync_external[1]) &&
                              channel_tx_enable[line] && tx_window && !sync_tr_hold &&
                              !(channel_busy && channel_enable_only);
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
            .clk(sys_clk_i), .probe0(rx_byte[0]), .probe1(rx_byte_valid[0]),
            .probe2(rx_index), .probe3(frame_command), .probe4(dispatcher_state),
            .probe5(response_status), .probe6(response_byte),
            .probe7(response_byte_valid), .probe8({frame_valid,frame_error,channel_done,channel_error}),
            .probe9(read_value), .probe10({read_busy,read_done,read_error})
        );
        ila_v03_array u_ila_array (
            .clk(sys_clk_i), .probe0(rx_sdi_o[3:0]), .probe1(rx_clk_o[0]),
            .probe2(rx_csb_o[0]), .probe3(rx_ldb_o[0]), .probe4(rx_rstn_o[0]),
            .probe5(rx_r_o[0]), .probe6(channel_rx_frames[23:0]),
            .probe7({channel_start,channel_busy,core_write_done,core_load_done,
                     reset_start,target_reset_busy,target_reset_done,core_error}),
            .probe8(rx_sdo_i[0])
        );
    end endgenerate
endmodule
