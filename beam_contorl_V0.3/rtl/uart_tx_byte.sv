`timescale 1ns/1ps

// One byte, 8N1, least-significant bit first. valid is accepted when ready.
module uart_tx_byte #(
    parameter int unsigned CLK_HZ = 50_000_000,
    parameter int unsigned BAUD_RATE = 115_200
) (
    input  logic       clk_i,
    input  logic       rst_i,
    input  logic       valid_i,
    input  logic [7:0] data_i,
    output logic       ready_o,
    output logic       done_o,
    output logic       serial_o
);
    localparam int unsigned CLKS_PER_BIT = CLK_HZ / BAUD_RATE;
    localparam int unsigned CW = (CLKS_PER_BIT < 2) ? 1 : $clog2(CLKS_PER_BIT);
    typedef enum logic [1:0] {IDLE, START, DATA, STOP} state_t;
    state_t state_q;
    logic [CW-1:0] count_q;
    logic [2:0] bit_q;
    logic [7:0] shift_q;
    assign ready_o = (state_q == IDLE);
    assign serial_o = (state_q == START) ? 1'b0 :
                      (state_q == DATA) ? shift_q[bit_q] : 1'b1;
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            state_q <= IDLE;
            count_q <= '0;
            bit_q <= '0;
            shift_q <= '0;
            done_o <= 1'b0;
        end else begin
            done_o <= 1'b0;
            case (state_q)
                IDLE: if (valid_i) begin
                    shift_q <= data_i;
                    count_q <= '0;
                    bit_q <= '0;
                    state_q <= START;
                end
                START: if (count_q == CLKS_PER_BIT - 1) begin
                    count_q <= '0;
                    state_q <= DATA;
                end else count_q <= count_q + 1'b1;
                DATA: if (count_q == CLKS_PER_BIT - 1) begin
                    count_q <= '0;
                    if (bit_q == 3'd7) state_q <= STOP;
                    else bit_q <= bit_q + 1'b1;
                end else count_q <= count_q + 1'b1;
                STOP: if (count_q == CLKS_PER_BIT - 1) begin
                    count_q <= '0;
                    state_q <= IDLE;
                    done_o <= 1'b1;
                end else count_q <= count_q + 1'b1;
                default: state_q <= IDLE;
            endcase
        end
    end
endmodule
