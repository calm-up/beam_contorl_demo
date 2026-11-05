`timescale 1ns/1ps
import beam_cmd_pkg::*;

// One chip on one line: read request, followed by the required dummy read.
// Other SDI lanes carry an unmatched CID (F); this requires the board's
// verified CID set 0..3 and shared SDO tri-state behavior.
module chip_sdo_reader #(
    parameter logic [15:0] CID_MAP = 16'h3210,
    parameter int unsigned TIMEOUT_CYCLES = 5_000_000
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic start_i,
    input  logic array_i,
    input  logic [2:0] line_i,
    input  logic [1:0] chip_i,
    input  logic [2:0] function_i,
    input  logic [7:0] address_i,
    input  logic core_ready_i,
    input  logic core_write_done_i,
    input  logic core_error_i,
    input  logic [191:0] rx_sdo_last_i,
    input  logic [191:0] tx_sdo_last_i,
    output logic core_valid_o,
    output logic [1:0] core_array_o,
    output logic [7:0] core_lines_o,
    output logic [767:0] core_frames_o,
    output logic busy_o,
    output logic done_o,
    output logic error_o,
    output logic [23:0] value_o
);
    typedef enum logic [2:0] {IDLE, ISSUE_READ, WAIT_READ,
                              ISSUE_DUMMY, WAIT_DUMMY} state_t;
    state_t state_q;
    logic array_q;
    logic [2:0] line_q, function_q;
    logic [1:0] chip_q;
    logic [7:0] address_q;
    logic [3:0] cid;
    localparam int unsigned TIMER_W = $clog2(TIMEOUT_CYCLES + 1);
    logic [TIMER_W-1:0] timer_q;
    logic [23:0] request_frame, dummy_frame;
    logic [23:0] observed_frame;
    assign cid = CID_MAP[chip_q*4 +: 4];
    assign request_frame = function_q <= 3'd2 ?
        {cid, 1'b1, function_q, address_q[3:0], 12'b0} : function_q <= 3'd5 ?
        {cid, 1'b1, function_q, address_q, 8'b0} :
        {cid, 1'b1, function_q, address_q[5:0], 10'b0};
    assign dummy_frame = {cid, 4'b1000, 16'b0};
    assign observed_frame = array_q ? tx_sdo_last_i[line_q*24 +: 24] :
                                      rx_sdo_last_i[line_q*24 +: 24];
    assign core_valid_o = ((state_q == ISSUE_READ) ||
                           (state_q == ISSUE_DUMMY)) && core_ready_i;
    assign core_array_o = array_q ? ARRAY_TX : ARRAY_RX;
    assign core_lines_o = 8'b1 << line_q;
    assign busy_o = state_q != IDLE;

    always_comb begin
        core_frames_o = '0;
        for (int lane = 0; lane < 8; lane++)
            for (int chip = 0; chip < 4; chip++)
                core_frames_o[(lane*4+chip)*24 +: 24] =
                    lane == line_q && chip == chip_q ?
                        (state_q == ISSUE_DUMMY ? dummy_frame : request_frame) :
                        24'hF80000;
    end

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            state_q <= IDLE;
            array_q <= 1'b0;
            line_q <= '0;
            chip_q <= '0;
            function_q <= '0;
            address_q <= '0;
            value_o <= '0;
            timer_q <= '0;
            done_o <= 1'b0;
            error_o <= 1'b0;
        end else begin
            done_o <= 1'b0;
            error_o <= 1'b0;
            if (state_q == IDLE) timer_q <= '0;
            else if (timer_q < TIMEOUT_CYCLES) timer_q <= timer_q + 1'b1;
            if (state_q != IDLE && timer_q == TIMEOUT_CYCLES) begin
                error_o <= 1'b1;
                state_q <= IDLE;
            end else
            case (state_q)
                IDLE: if (start_i) begin
                    array_q <= array_i;
                    line_q <= line_i;
                    chip_q <= chip_i;
                    function_q <= function_i;
                    address_q <= address_i;
                    state_q <= ISSUE_READ;
                end
                ISSUE_READ: if (core_ready_i) state_q <= WAIT_READ;
                WAIT_READ: begin
                    // SDO captured during this request belongs to the preceding
                    // frame. Do not publish it as this request's register value.
                    if (core_error_i) begin error_o <= 1'b1; state_q <= IDLE; end
                    else if (core_write_done_i) state_q <= ISSUE_DUMMY;
                end
                ISSUE_DUMMY: if (core_ready_i) state_q <= WAIT_DUMMY;
                WAIT_DUMMY: begin
                    if (core_error_i) begin error_o <= 1'b1; state_q <= IDLE; end
                    else if (core_write_done_i) begin
                        // The completed dummy frame carries the preceding read
                        // request's answer. Header/address validation below is
                        // transport validation, NOT a write-data comparison.
                        if (observed_frame[23:16] !=
                            {cid, 1'b1, function_q} ||
                            (function_q <= 3'd2 &&
                             observed_frame[15:12] != address_q[3:0]) ||
                            (function_q >= 3'd4 && function_q <= 3'd5 &&
                             observed_frame[15:8] != address_q) ||
                            (function_q >= 3'd6 &&
                             observed_frame[15:10] != address_q[5:0]))
                            error_o <= 1'b1;
                        else begin
                            value_o <= observed_frame;
                            done_o <= 1'b1;
                        end
                        state_q <= IDLE;
                    end
                end
                default: state_q <= IDLE;
            endcase
        end
    end
endmodule
