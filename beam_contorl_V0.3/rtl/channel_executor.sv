`timescale 1ns/1ps

import beam_cmd_pkg::*;

// Executes one validated channel command as two writes followed by one LDB pulse.
// Non-target SDI lanes transmit an ID-correct read/no-effect frame because the
// four lanes of a line share CLK, CSB and LDB.
module channel_executor #(
    parameter logic [15:0] CID_MAP = 16'h3210
) (
    input  logic                        clk_i,
    input  logic                        rst_i,
    input  logic                        command_valid_i,
    input  logic                        command_error_i,
    input  logic                        clear_valid_i,
    input  logic [1:0]                  clear_array_i,
    input  logic [7:0]                  clear_lines_i,
    input  logic                        array_i,
    input  logic [2:0]                  line_i,
    input  logic [1:0]                  chip_i,
    input  logic [1:0]                  channel_i,
    input  logic                        enable_i,
    input  logic [5:0]                  phase_i,
    input  logic [5:0]                  attenuation_i,
    input  logic                        core_init_done_i,
    output logic                        core_cmd_valid_o,
    input  logic                        core_cmd_ready_i,
    output logic [1:0]                  core_array_sel_o,
    output logic [7:0]                  core_line_mask_o,
    output logic [ARRAY_FRAME_BITS-1:0] core_rx_frames_o,
    output logic [ARRAY_FRAME_BITS-1:0] core_tx_frames_o,
    output logic                        core_cmd_write_o,
    output logic                        core_cmd_load_o,
    input  logic                        core_write_done_i,
    input  logic                        core_load_done_i,
    input  logic                        core_error_i,
    output logic [7:0]                  rx_line_enable_o,
    output logic [7:0]                  tx_line_enable_o,
    output logic                        busy_o,
    output logic                        done_o,
    output logic                        error_o,
    output logic [15:0]                 accepted_count_o,
    output logic [15:0]                 completed_count_o,
    output logic [15:0]                 rejected_count_o
);

    typedef enum logic [2:0] {
        ST_IDLE, ST_SEND_WRITE, ST_WAIT_WRITE, ST_SEND_LOAD, ST_WAIT_LOAD
    } state_t;

    state_t state_q;
    logic array_q;
    logic [2:0] line_q;
    logic [1:0] chip_q, channel_q;
    logic enable_q;
    logic [5:0] phase_q, attenuation_q;
    logic round_q;
    // The bit index is exactly {array,line,chip,channel}.
    logic [255:0] enable_mem_q;
    logic [ARRAY_FRAME_BITS-1:0] frames_q;
    logic [ARRAY_FRAME_BITS-1:0] enable_frames_d, ap_frames_d;
    logic [3:0] target_enable_mask;
    logic [23:0] enable_target_frame, ap_target_frame;
    logic [23:0] en_f0, en_f1, en_f2, en_f3;
    logic [23:0] ap_f0, ap_f1, ap_f2, ap_f3;
    logic [7:0] rx_line_enable_d, tx_line_enable_d;
    integer line_index;
    integer clear_line_index, clear_channel_index;

    function automatic [ARRAY_FRAME_BITS-1:0] place_line_frames(
        input logic [2:0] line,
        input logic [23:0] f0,
        input logic [23:0] f1,
        input logic [23:0] f2,
        input logic [23:0] f3
    );
        logic [ARRAY_FRAME_BITS-1:0] result;
        begin
            result = '0;
            case (line)
                3'd0: result[  0 +: 96] = {f3, f2, f1, f0};
                3'd1: result[ 96 +: 96] = {f3, f2, f1, f0};
                3'd2: result[192 +: 96] = {f3, f2, f1, f0};
                3'd3: result[288 +: 96] = {f3, f2, f1, f0};
                3'd4: result[384 +: 96] = {f3, f2, f1, f0};
                3'd5: result[480 +: 96] = {f3, f2, f1, f0};
                3'd6: result[576 +: 96] = {f3, f2, f1, f0};
                default: result[672 +: 96] = {f3, f2, f1, f0};
            endcase
            place_line_frames = result;
        end
    endfunction

    function automatic [3:0] channel_mask(
        input logic array_sel,
        input logic [2:0] line,
        input logic [1:0] chip
    );
        begin
            channel_mask = {
                enable_mem_q[{array_sel, line, chip, 2'd3}],
                enable_mem_q[{array_sel, line, chip, 2'd2}],
                enable_mem_q[{array_sel, line, chip, 2'd1}],
                enable_mem_q[{array_sel, line, chip, 2'd0}]
            };
        end
    endfunction

    assign busy_o = (state_q != ST_IDLE);
    assign core_cmd_valid_o = (state_q == ST_SEND_WRITE) ||
                              (state_q == ST_SEND_LOAD);
    assign core_array_sel_o = array_q ? ARRAY_TX : ARRAY_RX;
    assign core_line_mask_o = 8'b1 << line_q;
    assign core_cmd_write_o = (state_q == ST_SEND_WRITE);
    assign core_cmd_load_o  = (state_q == ST_SEND_LOAD);
    assign core_rx_frames_o = array_q ? '0 : frames_q;
    assign core_tx_frames_o = array_q ? frames_q : '0;

    always_comb begin
        target_enable_mask = channel_mask(array_i, line_i, chip_i);
        target_enable_mask[channel_i] = enable_i;

        case (chip_i)
            2'd0: enable_target_frame = {CID_MAP[3:0], 4'b0000, 12'b0,
                                         target_enable_mask};
            2'd1: enable_target_frame = {CID_MAP[7:4], 4'b0000, 12'b0,
                                         target_enable_mask};
            2'd2: enable_target_frame = {CID_MAP[11:8], 4'b0000, 12'b0,
                                         target_enable_mask};
            default: enable_target_frame = {CID_MAP[15:12], 4'b0000, 12'b0,
                                             target_enable_mask};
        endcase

        en_f0 = (chip_i == 2'd0) ? enable_target_frame :
                {CID_MAP[3:0], 1'b1, 19'b0};
        en_f1 = (chip_i == 2'd1) ? enable_target_frame :
                {CID_MAP[7:4], 1'b1, 19'b0};
        en_f2 = (chip_i == 2'd2) ? enable_target_frame :
                {CID_MAP[11:8], 1'b1, 19'b0};
        en_f3 = (chip_i == 2'd3) ? enable_target_frame :
                {CID_MAP[15:12], 1'b1, 19'b0};
        enable_frames_d = place_line_frames(line_i, en_f0, en_f1, en_f2, en_f3);

        case (chip_q)
            2'd0: ap_target_frame = {CID_MAP[3:0], 1'b0,
                                     (array_q ? 3'b001 : 3'b010), 2'b00,
                                     channel_q, attenuation_q, phase_q};
            2'd1: ap_target_frame = {CID_MAP[7:4], 1'b0,
                                     (array_q ? 3'b001 : 3'b010), 2'b00,
                                     channel_q, attenuation_q, phase_q};
            2'd2: ap_target_frame = {CID_MAP[11:8], 1'b0,
                                     (array_q ? 3'b001 : 3'b010), 2'b00,
                                     channel_q, attenuation_q, phase_q};
            default: ap_target_frame = {CID_MAP[15:12], 1'b0,
                                         (array_q ? 3'b001 : 3'b010), 2'b00,
                                         channel_q, attenuation_q, phase_q};
        endcase

        ap_f0 = (chip_q == 2'd0) ? ap_target_frame :
                {CID_MAP[3:0], 1'b1, 19'b0};
        ap_f1 = (chip_q == 2'd1) ? ap_target_frame :
                {CID_MAP[7:4], 1'b1, 19'b0};
        ap_f2 = (chip_q == 2'd2) ? ap_target_frame :
                {CID_MAP[11:8], 1'b1, 19'b0};
        ap_f3 = (chip_q == 2'd3) ? ap_target_frame :
                {CID_MAP[15:12], 1'b1, 19'b0};
        ap_frames_d = place_line_frames(line_q, ap_f0, ap_f1, ap_f2, ap_f3);
    end

    always_comb begin
        rx_line_enable_d = '0;
        tx_line_enable_d = '0;
        for (line_index = 0; line_index < 8; line_index = line_index + 1) begin
            rx_line_enable_d[line_index] =
                |enable_mem_q[line_index*16 +: 16];
            tx_line_enable_d[line_index] =
                |enable_mem_q[128 + line_index*16 +: 16];
        end
        if (busy_o) begin
            if (array_q) tx_line_enable_d[line_q] = 1'b0;
            else         rx_line_enable_d[line_q] = 1'b0;
        end
    end

    assign rx_line_enable_o = rx_line_enable_d;
    assign tx_line_enable_o = tx_line_enable_d;

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            state_q           <= ST_IDLE;
            array_q           <= 1'b0;
            line_q            <= '0;
            chip_q            <= '0;
            channel_q         <= '0;
            phase_q           <= '0;
            attenuation_q     <= '0;
            enable_q          <= 1'b0;
            round_q           <= 1'b0;
            enable_mem_q      <= '0;
            frames_q          <= '0;
            done_o            <= 1'b0;
            error_o           <= 1'b0;
            accepted_count_o  <= '0;
            completed_count_o <= '0;
            rejected_count_o  <= '0;
        end else begin
            done_o  <= 1'b0;
            error_o <= 1'b0;

            if (clear_valid_i) begin
                for (clear_line_index = 0; clear_line_index < 8; clear_line_index = clear_line_index + 1)
                    if (clear_lines_i[clear_line_index])
                        for (clear_channel_index = 0; clear_channel_index < 16;
                             clear_channel_index = clear_channel_index + 1) begin
                            if (clear_array_i[0])
                                enable_mem_q[clear_line_index*16 + clear_channel_index] <= 1'b0;
                            if (clear_array_i[1])
                                enable_mem_q[128 + clear_line_index*16 + clear_channel_index] <= 1'b0;
                        end
            end

            if (command_error_i) begin
                rejected_count_o <= rejected_count_o + 1'b1;
                error_o <= 1'b1;
            end

            if (command_valid_i) begin
                if ((state_q != ST_IDLE) || !core_init_done_i) begin
                    rejected_count_o <= rejected_count_o + 1'b1;
                    error_o <= 1'b1;
                end else begin
                    array_q       <= array_i;
                    line_q        <= line_i;
                    chip_q        <= chip_i;
                    channel_q     <= channel_i;
                    phase_q       <= phase_i;
                    attenuation_q <= attenuation_i;
                    enable_q      <= enable_i;
                    round_q       <= 1'b0;
                    frames_q      <= enable_frames_d;
                    accepted_count_o <= accepted_count_o + 1'b1;
                    state_q       <= ST_SEND_WRITE;
                end
            end

            case (state_q)
                ST_IDLE: ;
                ST_SEND_WRITE: begin
                    if (core_cmd_ready_i) state_q <= ST_WAIT_WRITE;
                end
                ST_WAIT_WRITE: begin
                    if (core_error_i) begin
                        rejected_count_o <= rejected_count_o + 1'b1;
                        error_o <= 1'b1;
                        state_q <= ST_IDLE;
                    end else if (core_write_done_i) begin
                        if (round_q) begin
                            state_q <= ST_SEND_LOAD;
                        end else begin
                            round_q  <= 1'b1;
                            frames_q <= ap_frames_d;
                            state_q  <= ST_SEND_WRITE;
                        end
                    end
                end
                ST_SEND_LOAD: begin
                    if (core_cmd_ready_i) state_q <= ST_WAIT_LOAD;
                end
                ST_WAIT_LOAD: begin
                    if (core_error_i) begin
                        rejected_count_o <= rejected_count_o + 1'b1;
                        error_o <= 1'b1;
                        state_q <= ST_IDLE;
                    end else if (core_load_done_i) begin
                        enable_mem_q[{array_q, line_q, chip_q, channel_q}] <= enable_q;
                        completed_count_o <= completed_count_o + 1'b1;
                        done_o <= 1'b1;
                        state_q <= ST_IDLE;
                    end
                end
                default: state_q <= ST_IDLE;
            endcase
        end
    end

endmodule
