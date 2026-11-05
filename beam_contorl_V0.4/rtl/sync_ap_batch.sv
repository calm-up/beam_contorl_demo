`timescale 1ns/1ps

module sync_ap_batch #(
    parameter logic [15:0] CID_MAP = 16'h3210,
    parameter int unsigned PRELOAD_GUARD = 10,
    parameter int unsigned SETTLE_CYCLES = 50
) (
    input wire clk_i, rst_i, sclk_i, wave_i, data_i, apply_i,
    output wire data_o,
    input wire available_i, core_ready_i, write_done_i, load_done_i, core_error_i,
    input wire tr_active_i, invalidate_i,
    input wire enable_done_i, enable_error_i,
    output wire enable_start_o,
    output logic [7:0] enable_target_o,
    output logic [1:0] external_configured_o,
    output wire owns_core_o, write_o, load_o,
    output wire [1:0] array_o,
    output wire [7:0] lines_o,
    output logic [767:0] frames_o,
    output logic [1:0] applied_o,
    output wire tr_hold_o, apply_rejected_o
);
    localparam logic [7:0] BEGIN_CMD = 8'h44, CHIP_CMD = 8'h45;
    localparam logic [7:0] OK = 0, FORMAT = 2, PARAMETER = 3, BUSY = 4,
                           SPI_ERROR = 6, COUNT_ERROR = 7, DUPLICATE = 8;
    typedef enum logic [3:0] {IDLE, RECEIVE, CHECK, ISSUE, WRITE_WAIT,
        GUARD, REPLY, REPLY_WAIT, ARMED, LOAD_WAIT, SETTLE, FAULT,
        ENABLE_ISSUE, ENABLE_WAIT} state_t;
    state_t state_q;
    (* ASYNC_REG = "TRUE" *) logic [1:0] wave_q, apply_q;
    logic wave_previous_q, apply_previous_q;
    wire wave_rise = wave_q[1] && !wave_previous_q;
    wire apply_rise = apply_q[1] && !apply_previous_q;
    wire byte_valid, seal, partial, reply_done;
    wire [7:0] rx_byte;
    logic [7:0] status_q;
    logic [15:0] batch_id_q;
    logic side_q, begin_seen_q;
    logic enable_request_q;
    logic [5:0] expected_q, received_q;
    logic [31:0] seen_q;
    logic [3:0] masks_q [0:31];
    logic [47:0] codes_q [0:31];
    logic [7:0] target_lines_q;
    logic [1:0] round_q;
    logic [31:0] timer_q;
    logic [7:0] round_lines;
    wire [7:0] side_byte = {7'b0, side_q};
    wire [7:0] count_byte = {2'b0, received_q};
    wire [7:0] reply_command = enable_request_q ? 8'h47 : BEGIN_CMD;
    wire [7:0] reply_sum = 8'h01 + 8'd13 + 8'h7F + side_byte + reply_command +
        status_q + batch_id_q[15:8] + batch_id_q[7:0] + count_byte;
    wire [103:0] response = {16'hAADD, 8'h01, 8'd13, 8'h7F, side_byte,
        reply_command, status_q, batch_id_q, count_byte, reply_sum, 8'h55};
    sync_serial_phy u_phy (
        .clk_i(clk_i), .rst_i(rst_i), .sclk_i(sclk_i), .wave_i(wave_i),
        .data_i(data_i), .data_o(data_o), .byte_valid_o(byte_valid),
        .seal_o(seal), .partial_o(partial), .byte_o(rx_byte),
        .response_start_i(state_q == REPLY), .response_i(response),
        .response_done_o(reply_done)
    );

    wire frame_valid, frame_error;
    wire [7:0] parser_status, command, side, length;
    wire [447:0] payload;
    wire [5:0] parser_index;
    protocol_v03_parser u_parser (
        .clk_i(clk_i), .rst_i(rst_i || state_q != RECEIVE),
        .byte_valid_i(byte_valid), .byte_i(rx_byte), .uart_error_i(1'b0),
        .frame_valid_o(frame_valid), .frame_error_o(frame_error),
        .error_status_o(parser_status), .command_o(command), .array_o(side),
        .payload_len_o(length), .payload_o(payload), .rx_index_o(parser_index)
    );

    wire [7:0] line_byte = payload[7:0];
    wire [7:0] chip_byte = payload[15:8];
    wire [7:0] mask_byte = payload[23:16];
    wire [4:0] target = {line_byte[2:0], chip_byte[1:0]};
    logic codes_legal;
    logic [47:0] packed_codes;
    always_comb begin
        codes_legal = 1;
        for (int c = 0; c < 4; c++) begin
            packed_codes[c*12 +: 12] =
                {payload[32+c*16 +: 6], payload[24+c*16 +: 6]};
            if (payload[30+c*16 +: 2] != 0 || payload[38+c*16 +: 2] != 0 ||
                (!mask_byte[c] && payload[24+c*16 +: 16] != 0))
                codes_legal = 0;
        end
    end

    always_comb begin
        round_lines = 0;
        for (int n = 0; n < 32; n++) begin
            frames_o[n*24 +: 24] = 24'hF80000;
            if (seen_q[n] && masks_q[n][round_q]) begin
                round_lines[n/4] = 1;
                frames_o[n*24 +: 24] = {CID_MAP[(n%4)*4 +: 4], 1'b0,
                    (side_q ? 3'b001 : 3'b010), 2'b00, round_q,
                    codes_q[n][round_q*12 +: 12]};
            end
        end
    end

    assign owns_core_o = state_q != IDLE || wave_rise;
    assign write_o = state_q == ISSUE && round_lines != 0;
    assign load_o = state_q == ARMED && apply_rise && !tr_active_i;
    assign apply_rejected_o = apply_rise && !(load_o && core_ready_i);
    assign array_o = side_q ? 2'b10 : 2'b01;
    assign lines_o = state_q == ISSUE ? round_lines : target_lines_q;
    assign enable_start_o = state_q == ENABLE_ISSUE;
    assign tr_hold_o = load_o || state_q == LOAD_WAIT || state_q == SETTLE ||
                       state_q == FAULT || state_q == ENABLE_ISSUE || state_q == ENABLE_WAIT;

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            wave_q <= 0;
            wave_previous_q <= 0;
            apply_q <= 0;
            apply_previous_q <= 0;
            state_q <= IDLE;
            status_q <= OK;
            batch_id_q <= 0;
            side_q <= 0;
            begin_seen_q <= 0;
            enable_request_q <= 0;
            enable_target_o <= 0;
            external_configured_o <= 0;
            expected_q <= 0;
            received_q <= 0;
            seen_q <= 0;
            target_lines_q <= 0;
            round_q <= 0;
            timer_q <= 0;
            applied_o <= 0;
        end else begin
            wave_q <= {wave_q[0], wave_i};
            wave_previous_q <= wave_q[1];
            apply_q <= {apply_q[0], apply_i};
            apply_previous_q <= apply_q[1];
            if (invalidate_i) begin
                applied_o <= 0;
                external_configured_o <= 0;
            end
            case (state_q)
                IDLE: if (wave_rise) begin
                    state_q <= RECEIVE;
                    status_q <= available_i ? OK : BUSY;
                    batch_id_q <= 0;
                    side_q <= 0;
                    begin_seen_q <= 0;
                    enable_request_q <= 0;
                    expected_q <= 0;
                    received_q <= 0;
                    seen_q <= 0;
                    target_lines_q <= 0;
                    round_q <= 0;
                end
                RECEIVE: begin
                    if (status_q == OK) begin
                        if (frame_error) status_q <= parser_status;
                        else if (byte_valid && ((parser_index == 0 && rx_byte != 8'hAA) ||
                                                (parser_index == 1 && rx_byte != 8'hDD)))
                            status_q <= FORMAT;
                        else if (frame_valid) begin
                            if (enable_request_q) status_q <= COUNT_ERROR;
                            else if (!begin_seen_q && command == 8'h47) begin
                                enable_request_q <= 1;
                                side_q <= side[0];
                                if (side > 1 || length != 4 || line_byte > 7 ||
                                    chip_byte > 3 || mask_byte > 3 || payload[31:24] > 1)
                                    status_q <= PARAMETER;
                                else enable_target_o <= {line_byte[2:0], chip_byte[1:0],
                                                          mask_byte[1:0], payload[24]};
                            end else if (!begin_seen_q) begin
                                if (command != BEGIN_CMD || length != 3 || side > 1 ||
                                    payload[23:16] == 0 || payload[23:16] > 32)
                                    status_q <= PARAMETER;
                                else begin
                                    begin_seen_q <= 1;
                                    side_q <= side[0];
                                    batch_id_q <= {payload[7:0], payload[15:8]};
                                    expected_q <= payload[21:16];
                                end
                            end else if (command != CHIP_CMD || side != side_byte ||
                                         length != 11 || line_byte > 7 || chip_byte > 3 ||
                                         mask_byte == 0 || mask_byte > 15 || !codes_legal)
                                status_q <= PARAMETER;
                            else if (seen_q[target]) status_q <= DUPLICATE;
                            else if (received_q == expected_q) status_q <= COUNT_ERROR;
                            else begin
                                seen_q[target] <= 1;
                                masks_q[target] <= mask_byte[3:0];
                                codes_q[target] <= packed_codes;
                                target_lines_q[line_byte[2:0]] <= 1;
                                received_q <= received_q + 1'b1;
                            end
                        end
                        if (seal && (partial || parser_index != 0)) status_q <= FORMAT;
                    end
                    if (seal) state_q <= CHECK;
                end
                CHECK: begin
                    if (status_q != OK) state_q <= REPLY;
                    else if (enable_request_q) begin
                        if (tr_active_i) begin
                            status_q <= BUSY;
                            state_q <= REPLY;
                        end else state_q <= ENABLE_ISSUE;
                    end
                    else if (!begin_seen_q || received_q != expected_q) begin
                        status_q <= COUNT_ERROR;
                        state_q <= REPLY;
                    end else state_q <= ISSUE;
                end
                ISSUE: begin
                    if (round_lines == 0) begin
                        if (round_q == 3) begin
                            timer_q <= PRELOAD_GUARD;
                            state_q <= GUARD;
                        end else round_q <= round_q + 1'b1;
                    end else if (core_ready_i) state_q <= WRITE_WAIT;
                end
                WRITE_WAIT: begin
                    if (core_error_i) begin
                        status_q <= SPI_ERROR;
                        state_q <= REPLY;
                    end else if (write_done_i) begin
                        if (round_q == 3) begin
                            timer_q <= PRELOAD_GUARD;
                            state_q <= GUARD;
                        end else begin
                            round_q <= round_q + 1'b1;
                            state_q <= ISSUE;
                        end
                    end
                end
                GUARD: if (timer_q == 0) state_q <= REPLY;
                       else timer_q <= timer_q - 1'b1;
                ENABLE_ISSUE: state_q <= ENABLE_WAIT;
                ENABLE_WAIT: begin
                    if (enable_error_i) begin
                        status_q <= SPI_ERROR;
                        state_q <= REPLY;
                    end else if (enable_done_i) begin
                        external_configured_o[side_q] <= 1;
                        received_q <= 1;
                        state_q <= REPLY;
                    end
                end
                REPLY: state_q <= REPLY_WAIT;
                REPLY_WAIT: if (reply_done) begin
                    if (status_q == OK && !enable_request_q) state_q <= ARMED;
                    else if (status_q == SPI_ERROR) state_q <= FAULT;
                    else state_q <= IDLE;
                end
                ARMED: if (load_o && core_ready_i) state_q <= LOAD_WAIT;
                LOAD_WAIT: if (core_error_i) state_q <= FAULT;
                           else if (load_done_i) begin
                               timer_q <= SETTLE_CYCLES;
                               state_q <= SETTLE;
                           end
                SETTLE: if (timer_q == 0) begin
                            applied_o[side_q] <= 1;
                            state_q <= IDLE;
                        end else timer_q <= timer_q - 1'b1;
                FAULT: state_q <= FAULT;
                default: state_q <= FAULT;
            endcase
        end
    end
endmodule
