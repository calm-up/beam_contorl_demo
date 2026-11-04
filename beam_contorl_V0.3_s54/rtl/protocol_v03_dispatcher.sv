`timescale 1ns/1ps

// One UART transaction at a time. C0 overwrites the selected position.
module protocol_v03_dispatcher (
    input  logic         clk_i,
    input  logic         rst_i,
    input  logic         frame_valid_i,
    input  logic         frame_error_i,
    input  logic [7:0]   command_i,
    input  logic [7:0]   array_i,
    input  logic [7:0]   payload_len_i,
    input  logic [447:0] payload_i,
    input  logic         init_done_i,
    input  logic         chip_reset_done_i,
    input  logic         init_fault_i,
    input  logic         core_ready_i,
    input  logic         channel_busy_i,
    input  logic         channel_done_i,
    input  logic         channel_error_i,
    input  logic         beam_calc_busy_i,
    input  logic         beam_calc_done_i,
    input  logic         batch_busy_i,
    input  logic         batch_done_i,
    input  logic         batch_error_i,
    input  logic [7:0]   rx_enable_i,
    input  logic [7:0]   tx_enable_i,
    input  logic         reset_busy_i,
    input  logic         reset_done_i,
    input  logic         response_ready_i,
    input  logic         response_done_i,
    input  logic         flash_probe_done_i,
    input  logic         flash_probe_valid_i,
    input  logic         flash_busy_i,
    input  logic         flash_done_i,
    input  logic         flash_error_i,
    input  logic [10:0]  flash_loaded_count_i,
    input  logic [23:0]  flash_cache_sample_i,
    input  logic         read_done_i,
    input  logic         read_error_i,
    input  logic [23:0]  read_value_i,
    output logic         read_start_o,
    output logic         read_array_o,
    output logic [2:0]   read_line_o,
    output logic [1:0]   read_chip_o,
    output logic [2:0]   read_function_o,
    output logic [7:0]   read_address_o,
    output logic         channel_start_o,
    output logic         channel_array_o,
    output logic [2:0]   channel_line_o,
    output logic [1:0]   channel_chip_o,
    output logic [1:0]   channel_index_o,
    output logic         channel_enable_o,
    output logic [5:0]   channel_phase_o,
    output logic [5:0]   channel_atten_o,
    output logic         beam_calc_start_o,
    output logic         beam_batch_start_o,
    output logic         beam_array_o,
    output logic [15:0]  beam_frequency_o,
    output logic signed [15:0] beam_azimuth_o,
    output logic signed [15:0] beam_elevation_o,
    output logic [7:0]   beam_lines_o,
    output logic [3:0]   beam_chips_o,
    output logic [3:0]   beam_channels_o,
    output logic         clear_valid_o,
    output logic [1:0]   clear_array_o,
    output logic [7:0]   clear_lines_o,
    output logic         reset_start_o,
    output logic [1:0]   reset_array_o,
    output logic [7:0]   reset_lines_o,
    output logic [7:0]   rx_gate_o,
    output logic [7:0]   tx_gate_o,
    output logic [7:0]   rx_pulse_mode_o,
    output logic [7:0]   tx_pulse_mode_o,
    output logic         flash_start_o,
    output logic [7:0]   flash_command_o,
    output logic         flash_array_o,
    output logic [95:0]  flash_payload_o,
    output logic         response_start_o,
    output logic [7:0]   response_array_o,
    output logic [7:0]   response_command_o,
    output logic [7:0]   response_status_o,
    output logic         response_extra_valid_o,
    output logic [39:0]  response_extra_o,
    output logic         busy_o,
    output logic [3:0]   state_probe_o
);
    typedef enum logic [4:0] {
        IDLE, CHANNEL_ISSUE, CHANNEL_WAIT, RESET_ISSUE, RESET_WAIT,
        CLEAR, FLASH_ISSUE, FLASH_WAIT, RESPONSE_ISSUE, RESPONSE_WAIT,
        BEAM_CALC_ISSUE, BEAM_CALC_WAIT, BEAM_BATCH_ISSUE, BEAM_BATCH_WAIT,
        READ_ISSUE, READ_WAIT, RESET_REINIT_WAIT
    } state_t;
    state_t state_q;
    logic [7:0] rx_gate_q, tx_gate_q;
    logic error_sticky_q;
    logic [7:0] command_q, array_q, pending_pulse_q;
    logic [95:0] flash_payload_q;
    logic [7:0] rx_pulse_q, tx_pulse_q;
    logic [1:0] reset_array_q;
    logic [7:0] reset_lines_q;
    logic channel_array_q, channel_enable_q;
    logic [2:0] channel_line_q;
    logic [1:0] channel_chip_q, channel_index_q;
    logic [5:0] channel_phase_q, channel_atten_q;
    logic beam_array_q;
    logic [15:0] beam_frequency_q;
    logic signed [15:0] beam_azimuth_q, beam_elevation_q;
    logic [7:0] beam_lines_q;
    logic [3:0] beam_chips_q, beam_channels_q;
    logic [7:0] response_status_q;
    logic read_array_q;
    logic [2:0] read_line_q, read_function_q;
    logic [1:0] read_chip_q;
    logic [7:0] read_address_q;
    logic response_extra_valid_q;
    logic [39:0] response_extra_q;
    logic [7:0] p [0:14];
    logic [7:0] array_result;
    logic [7:0] status_result;
    logic [7:0] req_phase, req_atten;
    logic [7:0] effective_phase, effective_atten;
    logic [7:0] requested_pulse;
    logic [15:0] beam_frequency_req;
    logic signed [15:0] beam_azimuth_req, beam_elevation_req;
    logic [7:0] beam_pulse_req;
    integer clear_index;
    genvar n;
    generate for (n=0;n<15;n=n+1) begin : g_payload
        assign p[n] = payload_i[n*8 +: 8];
    end endgenerate

    assign req_phase = array_i == 8'd0 ? p[5] : p[4];
    assign req_atten = array_i == 8'd0 ? p[7] : p[6];
    assign effective_phase = req_phase;
    assign effective_atten = req_atten;
    assign requested_pulse = command_i == 8'h40 ? p[10] : p[8];
    assign beam_frequency_req = command_i == 8'h20 ? {p[0],p[1]} : {p[3],p[4]};
    assign beam_azimuth_req = command_i == 8'h20 ?
                              $signed({p[2],p[3]}) : $signed({p[5],p[6]});
    assign beam_elevation_req = command_i == 8'h20 ?
                                $signed({p[4],p[5]}) : $signed({p[7],p[8]});
    assign beam_pulse_req = command_i == 8'h20 ? p[8] : p[9];

    // Validate exactly the fields the execution path consumes. All other modes
    // retain their wire format but cannot report physical success yet.
    always_comb begin
        status_result = 8'h05;
        if (array_i != 0 && array_i != 1 && array_i != 2 && array_i != 8'hFF)
            status_result = 8'h03;
        else case (command_i)
            8'hE0: begin
                if (payload_len_i != 0 || (array_i != 0 && array_i != 1 &&
                    array_i != 2 && array_i != 8'hFF)) status_result = 8'h03;
                else status_result = 8'h00;
            end
            8'h41: begin
                if (array_i > 1 || payload_len_i != 4 || p[0] > 7 ||
                    p[1] > 3 || p[2] == 0 || p[2] == 3 || p[2] > 7 ||
                    (p[2] <= 2 && p[3] > 3) ||
                    (p[2] >= 6 && p[3] > 63)) status_result = 8'h03;
                else if (init_fault_i) status_result = 8'h06;
                else if (!init_done_i || !core_ready_i || channel_busy_i ||
                         reset_busy_i || batch_busy_i || flash_busy_i)
                    status_result = 8'h04;
                else status_result = 8'h00;
            end
            8'h00: begin
                if (payload_len_i != 2 || array_i == 8'hFF || p[0] == 0 || p[1] != 0)
                    status_result = 8'h03;
                else if (!init_fault_i && (!init_done_i || !core_ready_i))
                    status_result = 8'h04;
                else status_result = 8'h00;
            end
            8'h40, 8'hC0: begin
                if (payload_len_i != (command_i == 8'h40 ? 15 : 9) || array_i > 1 ||
                    p[0] > 7 || p[1] > 3 || p[2] > 3 || p[3] > 1)
                    status_result = 8'h03;
                else if ((array_i == 0 && ((command_i == 8'h40 && (p[4] != 0 || p[6] != 0)) ||
                                               (command_i == 8'hC0 && (p[4] != 0 || p[6] != 0)))) ||
                         (array_i == 1 && (p[5] != 0 || p[7] != 0)) ||
                         (req_phase > 63 || req_atten > 63))
                    status_result = 8'h03;
                else if (command_i == 8'h40 && (p[8] != 0 || p[9] != 0 ||
                         p[11] != 0 || p[12] != 0 || p[13] != 0 || p[14] != 0))
                    status_result = 8'h05;
                else if (!((requested_pulse == 8'h00) ||
                           (array_i == 1 && (requested_pulse == 8'h01 ||
                            requested_pulse == 8'h11 || requested_pulse == 8'h21 ||
                            requested_pulse == 8'h31 || requested_pulse == 8'h41 ||
                            requested_pulse == 8'h51 || requested_pulse == 8'h61)) ||
                           (array_i == 0 && (requested_pulse == 8'h02 ||
                            requested_pulse == 8'h12))))
                    status_result = 8'h05;
                else if (init_fault_i) status_result = 8'h06;
                else if (!init_done_i || !core_ready_i || channel_busy_i || reset_busy_i)
                    status_result = 8'h04;
                else status_result = 8'h00;
            end
            8'h20,8'hA0: begin
                if (array_i > 1 || payload_len_i != 10 ||
                    beam_frequency_req == 0 || beam_frequency_req > 16'd32767 ||
                    beam_azimuth_req < -16'sd9000 || beam_azimuth_req > 16'sd9000 ||
                    beam_elevation_req < -16'sd9000 || beam_elevation_req > 16'sd9000 ||
                    (command_i == 8'hA0 && (p[1][7:4] != 0 || p[2][7:4] != 0)))
                    status_result = 8'h03;
                else if ((command_i == 8'h20 &&
                          (p[6] != 0 || p[7] != 0 || p[9] != 0)) ||
                         !((beam_pulse_req == 8'h00) ||
                           (array_i == 1 && (beam_pulse_req == 8'h01 ||
                            beam_pulse_req == 8'h11 || beam_pulse_req == 8'h21 ||
                            beam_pulse_req == 8'h31 || beam_pulse_req == 8'h41 ||
                            beam_pulse_req == 8'h51 || beam_pulse_req == 8'h61)) ||
                           (array_i == 0 && (beam_pulse_req == 8'h02 ||
                            beam_pulse_req == 8'h12))))
                    status_result = 8'h05;
                else if (init_fault_i) status_result = 8'h06;
                else if (!init_done_i || !core_ready_i || channel_busy_i ||
                         beam_calc_busy_i || batch_busy_i || reset_busy_i || flash_busy_i)
                    status_result = 8'h04;
                else status_result = 8'h00;
            end
            8'hF1,8'hF2,8'hF3,8'hF5: begin
                if (array_i > 1) status_result = 8'h03;
                else if (command_i == 8'hF3 &&
                         (payload_len_i != 1 ||
                          !(p[0] <= 7 || p[0] == 8'h11 || p[0] == 8'h12 || p[0] == 8'h13)))
                    status_result = 8'h03;
                else if (command_i == 8'hF5 &&
                         (payload_len_i != 2 || p[0] != 8'hA5 || p[1] != 8'h5A))
                    status_result = 8'h03;
                else if ((command_i == 8'hF1 || command_i == 8'hF2) &&
                         (payload_len_i != 12 ||
                          !(p[0] <= 7 || p[0] == 8'h11 || p[0] == 8'h12 || p[0] == 8'h13) ||
                          (command_i == 8'hF1 && (p[10] != 8'hA5 || p[11] != 8'h5A)) ||
                          ((p[0] == 8'h11 || p[0] == 8'h12) && (p[1] != 0 || p[2] > 31)) ||
                          (p[0] == 8'h13 && p[1] > 128) ||
                          ((p[0] <= 7 || p[0] == 8'h11) && (p[3] > 3 || p[4] > 3))))
                    status_result = 8'h03;
                else if (!flash_probe_done_i || flash_busy_i || channel_busy_i || reset_busy_i)
                    status_result = 8'h04;
                else status_result = 8'h00;
            end
            default: status_result = 8'h05;
        endcase
    end

    assign channel_start_o = state_q == CHANNEL_ISSUE;
    assign read_start_o = state_q == READ_ISSUE;
    assign read_array_o = read_array_q;
    assign read_line_o = read_line_q;
    assign read_chip_o = read_chip_q;
    assign read_function_o = read_function_q;
    assign read_address_o = read_address_q;
    assign channel_array_o = channel_array_q;
    assign channel_line_o = channel_line_q;
    assign channel_chip_o = channel_chip_q;
    assign channel_index_o = channel_index_q;
    assign channel_enable_o = channel_enable_q;
    assign channel_phase_o = channel_phase_q;
    assign channel_atten_o = channel_atten_q;
    assign beam_calc_start_o = state_q == BEAM_CALC_ISSUE;
    assign beam_batch_start_o = state_q == BEAM_BATCH_ISSUE;
    assign beam_array_o = beam_array_q;
    assign beam_frequency_o = beam_frequency_q;
    assign beam_azimuth_o = beam_azimuth_q;
    assign beam_elevation_o = beam_elevation_q;
    assign beam_lines_o = beam_lines_q;
    assign beam_chips_o = beam_chips_q;
    assign beam_channels_o = beam_channels_q;
    assign reset_start_o = state_q == RESET_ISSUE;
    assign reset_array_o = reset_array_q;
    assign reset_lines_o = reset_lines_q;
    assign clear_valid_o = state_q == CLEAR;
    assign clear_array_o = reset_array_q;
    assign clear_lines_o = reset_lines_q;
    assign rx_gate_o = rx_gate_q;
    assign tx_gate_o = tx_gate_q;
    assign rx_pulse_mode_o = rx_pulse_q;
    assign tx_pulse_mode_o = tx_pulse_q;
    assign flash_start_o = state_q == FLASH_ISSUE;
    assign flash_command_o = command_q;
    assign flash_array_o = array_q[0];
    assign flash_payload_o = flash_payload_q;
    assign response_start_o = state_q == RESPONSE_ISSUE && response_ready_i;
    assign response_command_o = command_q;
    assign response_array_o = array_q;
    assign response_status_o = response_status_q;
    assign response_extra_valid_o = response_extra_valid_q;
    assign response_extra_o = response_extra_q;
    assign busy_o = state_q != IDLE;
    assign state_probe_o = state_q[3:0];

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            state_q <= IDLE;
            rx_gate_q <= '0;
            tx_gate_q <= '0;
            error_sticky_q <= 1'b0;
            command_q <= '0;
            flash_payload_q <= '0;
            array_q <= '0;
            pending_pulse_q <= '0;
            rx_pulse_q <= '0;
            tx_pulse_q <= '0;
            reset_array_q <= '0;
            reset_lines_q <= '0;
            channel_array_q <= '0;
            channel_line_q <= '0;
            channel_chip_q <= '0;
            channel_index_q <= '0;
            channel_enable_q <= '0;
            channel_phase_q <= '0;
            channel_atten_q <= '0;
            beam_array_q <= 1'b0;
            beam_frequency_q <= '0;
            beam_azimuth_q <= '0;
            beam_elevation_q <= '0;
            beam_lines_q <= '0;
            beam_chips_q <= '0;
            beam_channels_q <= '0;
            response_status_q <= '0;
            read_array_q <= 1'b0;
            read_line_q <= '0;
            read_chip_q <= '0;
            read_function_q <= '0;
            read_address_q <= '0;
            response_extra_valid_q <= 1'b0;
            response_extra_q <= '0;
        end else begin
            if (frame_error_i) error_sticky_q <= 1'b1;
            case (state_q)
                IDLE: if (frame_valid_i) begin
                    command_q <= command_i;
                    array_q <= array_i;
                    flash_payload_q <= payload_i[95:0];
                    response_status_q <= status_result;
                    response_extra_valid_q <= command_i == 8'hE0 && status_result == 0;
                    response_extra_q <= {tx_enable_i & tx_gate_q,
                                         rx_enable_i & rx_gate_q,
                                         {5'b0,init_fault_i,flash_probe_valid_i,error_sticky_q},
                                         {6'b0,flash_probe_done_i,channel_busy_i | reset_busy_i},
                                         {6'b0,init_done_i,chip_reset_done_i}};
                    if (status_result != 0) begin
                        error_sticky_q <= 1'b1;
                        state_q <= RESPONSE_ISSUE;
                    end else if (command_i == 8'h00) begin
                        reset_array_q <= init_fault_i ? 2'b11 :
                                         array_i == 0 ? 2'b01 :
                                         array_i == 1 ? 2'b10 : 2'b11;
                        reset_lines_q <= init_fault_i ? 8'hFF : p[0];
                        state_q <= RESET_ISSUE;
                    end else if (command_i == 8'h41) begin
                        read_array_q <= array_i[0];
                        read_line_q <= p[0][2:0];
                        read_chip_q <= p[1][1:0];
                        read_function_q <= p[2][2:0];
                        read_address_q <= p[3];
                        state_q <= READ_ISSUE;
                    end else if (command_i == 8'h40 || command_i == 8'hC0) begin
                        channel_array_q <= array_i[0];
                        channel_line_q <= p[0][2:0];
                        channel_chip_q <= p[1][1:0];
                        channel_index_q <= p[2][1:0];
                        channel_enable_q <= p[3][0];
                        channel_phase_q <= effective_phase[5:0];
                        channel_atten_q <= effective_atten[5:0];
                        pending_pulse_q <= requested_pulse;
                        state_q <= CHANNEL_ISSUE;
                    end else if (command_i == 8'h20 || command_i == 8'hA0) begin
                        beam_array_q <= array_i[0];
                        beam_frequency_q <= beam_frequency_req;
                        beam_azimuth_q <= beam_azimuth_req;
                        beam_elevation_q <= beam_elevation_req;
                        beam_lines_q <= command_i == 8'h20 ? 8'hFF : p[0];
                        beam_chips_q <= command_i == 8'h20 ? 4'hF : p[1][3:0];
                        beam_channels_q <= command_i == 8'h20 ? 4'hF : p[2][3:0];
                        pending_pulse_q <= beam_pulse_req;
                        state_q <= BEAM_CALC_ISSUE;
                    end else if (command_i == 8'hF1 || command_i == 8'hF2 ||
                                 command_i == 8'hF3 || command_i == 8'hF5)
                        state_q <= FLASH_ISSUE;
                    else state_q <= RESPONSE_ISSUE;
                end
                CHANNEL_ISSUE: state_q <= CHANNEL_WAIT;
                READ_ISSUE: state_q <= READ_WAIT;
                READ_WAIT: if (read_done_i || read_error_i) begin
                    response_status_q <= read_error_i ? 8'h06 : 8'h00;
                    response_extra_valid_q <= !read_error_i;
                    response_extra_q <= {read_value_i, 6'b0, read_chip_q,
                                         5'b0, read_line_q};
                    if (read_error_i) error_sticky_q <= 1'b1;
                    state_q <= RESPONSE_ISSUE;
                end
                CHANNEL_WAIT: begin
                    if (channel_error_i) begin
                        response_status_q <= 8'h06;
                        error_sticky_q <= 1'b1;
                        if (channel_array_q) tx_gate_q[channel_line_q] <= 1'b0;
                        else                 rx_gate_q[channel_line_q] <= 1'b0;
                        state_q <= RESPONSE_ISSUE;
                    end else if (channel_done_i) begin
                        if (channel_array_q) begin
                            tx_gate_q[channel_line_q] <= 1'b1;
                            tx_pulse_q <= pending_pulse_q;
                        end else begin
                            rx_gate_q[channel_line_q] <= 1'b1;
                            rx_pulse_q <= pending_pulse_q;
                        end
                        response_status_q <= 8'h00;
                        state_q <= RESPONSE_ISSUE;
                    end
                end
                BEAM_CALC_ISSUE: state_q <= BEAM_CALC_WAIT;
                BEAM_CALC_WAIT: if (beam_calc_done_i) state_q <= BEAM_BATCH_ISSUE;
                BEAM_BATCH_ISSUE: state_q <= BEAM_BATCH_WAIT;
                BEAM_BATCH_WAIT: begin
                    if (batch_error_i) begin
                        response_status_q <= 8'h06;
                        error_sticky_q <= 1'b1;
                        if (beam_array_q) tx_gate_q <= '0;
                        else rx_gate_q <= '0;
                        state_q <= RESPONSE_ISSUE;
                    end else if (batch_done_i) begin
                        if (beam_array_q) begin
                            tx_gate_q <= 8'hFF;
                            tx_pulse_q <= pending_pulse_q;
                        end else begin
                            rx_gate_q <= 8'hFF;
                            rx_pulse_q <= pending_pulse_q;
                        end
                        response_status_q <= 8'h00;
                        state_q <= RESPONSE_ISSUE;
                    end
                end
                RESET_ISSUE: state_q <= RESET_WAIT;
                RESET_WAIT: if (reset_done_i) state_q <= CLEAR;
                CLEAR: begin
                    for (clear_index=0;clear_index<8;clear_index=clear_index+1)
                        if (reset_lines_q[clear_index]) begin
                            if (reset_array_q[0]) begin
                                rx_gate_q[clear_index] <= 1'b0;
                            end
                            if (reset_array_q[1]) begin
                                tx_gate_q[clear_index] <= 1'b0;
                            end
                        end
                    response_status_q <= 8'h00;
                    state_q <= RESET_REINIT_WAIT;
                end
                RESET_REINIT_WAIT: begin
                    if (init_fault_i) begin
                        response_status_q <= 8'h06;
                        error_sticky_q <= 1'b1;
                        state_q <= RESPONSE_ISSUE;
                    end else if (init_done_i) begin
                        response_status_q <= 8'h00;
                        state_q <= RESPONSE_ISSUE;
                    end
                end
                FLASH_ISSUE: state_q <= FLASH_WAIT;
                FLASH_WAIT: if (flash_done_i) begin
                    response_status_q <= flash_error_i ? 8'h06 : 8'h00;
                    if (command_q == 8'hF3 && !flash_error_i) begin
                        response_extra_valid_q <= 1'b1;
                        response_extra_q <= {flash_cache_sample_i,5'b0,flash_loaded_count_i};
                    end
                    if (flash_error_i) error_sticky_q <= 1'b1;
                    state_q <= RESPONSE_ISSUE;
                end
                RESPONSE_ISSUE: if (response_ready_i) state_q <= RESPONSE_WAIT;
                RESPONSE_WAIT: if (response_done_i) state_q <= IDLE;
                default: state_q <= IDLE;
            endcase
        end
    end
endmodule
