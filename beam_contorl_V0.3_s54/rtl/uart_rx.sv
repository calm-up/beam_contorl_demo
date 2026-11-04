`timescale 1ns/1ps

// 8-N-1 UART receiver. The RS422 transceiver presents a single-ended logic
// signal to this block. The integer divider gives 115207 baud at 50 MHz when
// BAUD_RATE is 115200 (0.006% error).
module uart_rx #(
    parameter int unsigned CLK_HZ    = 50_000_000,
    parameter int unsigned BAUD_RATE = 115_200
) (
    input  logic       clk_i,
    input  logic       rst_i,
    input  logic       serial_i,
    output logic       data_valid_o,
    output logic [7:0] data_o,
    output logic       frame_error_o
);

    localparam int unsigned CLKS_PER_BIT = CLK_HZ / BAUD_RATE;
    localparam int unsigned HALF_CLKS    = CLKS_PER_BIT / 2;
    localparam int unsigned COUNT_W      =
        (CLKS_PER_BIT <= 2) ? 1 : $clog2(CLKS_PER_BIT);

    typedef enum logic [1:0] {ST_IDLE, ST_START, ST_DATA, ST_STOP} state_t;
    state_t state_q;
    logic serial_meta_q, serial_sync_q;
    logic [COUNT_W-1:0] count_q;
    logic [2:0] bit_q;
    logic [7:0] shift_q;

    initial begin
        if (CLKS_PER_BIT < 4) $error("UART clock divider is too small");
    end

    always_ff @(posedge clk_i) begin
        serial_meta_q <= serial_i;
        serial_sync_q <= serial_meta_q;
    end

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            state_q       <= ST_IDLE;
            count_q       <= '0;
            bit_q         <= '0;
            shift_q       <= '0;
            data_o        <= '0;
            data_valid_o  <= 1'b0;
            frame_error_o <= 1'b0;
        end else begin
            data_valid_o  <= 1'b0;
            frame_error_o <= 1'b0;
            case (state_q)
                ST_IDLE: begin
                    count_q <= '0;
                    bit_q   <= '0;
                    if (!serial_sync_q) state_q <= ST_START;
                end

                ST_START: begin
                    if (count_q == HALF_CLKS - 1) begin
                        count_q <= '0;
                        if (!serial_sync_q) state_q <= ST_DATA;
                        else state_q <= ST_IDLE;
                    end else begin
                        count_q <= count_q + 1'b1;
                    end
                end

                ST_DATA: begin
                    if (count_q == CLKS_PER_BIT - 1) begin
                        count_q      <= '0;
                        shift_q[bit_q] <= serial_sync_q;
                        if (bit_q == 3'd7) begin
                            bit_q   <= '0;
                            state_q <= ST_STOP;
                        end else begin
                            bit_q <= bit_q + 1'b1;
                        end
                    end else begin
                        count_q <= count_q + 1'b1;
                    end
                end

                ST_STOP: begin
                    if (count_q == CLKS_PER_BIT - 1) begin
                        count_q <= '0;
                        if (serial_sync_q) begin
                            data_o       <= shift_q;
                            data_valid_o <= 1'b1;
                        end else begin
                            frame_error_o <= 1'b1;
                        end
                        state_q <= ST_IDLE;
                    end else begin
                        count_q <= count_q + 1'b1;
                    end
                end

                default: state_q <= ST_IDLE;
            endcase
        end
    end
endmodule
