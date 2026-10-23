`timescale 1ns/1ps

// SPI mode 0, x1, MSB first. All timing is derived from the system clock;
// no fabric-generated clock drives sequential logic. Bytes are little-indexed
// in tx_data_i/rx_data_o: byte zero occupies bits [7:0].
module u22_spi_master #(
    parameter int unsigned HALF_CYCLES = 25
) (
    input  logic         clk_i,
    input  logic         rst_i,
    input  logic         start_i,
    input  logic [5:0]   tx_count_i,
    input  logic [5:0]   rx_count_i,
    input  logic [255:0] tx_data_i,
    input  logic         miso_i,
    output logic         cs_n_o,
    output logic         sck_o,
    output logic         mosi_o,
    output logic         busy_o,
    output logic         done_o,
    output logic [255:0] rx_data_o
);
    localparam int unsigned DW = (HALF_CYCLES < 2) ? 1 : $clog2(HALF_CYCLES);
    typedef enum logic [1:0] {IDLE, SETUP, LOW, HIGH} state_t;
    state_t state_q;
    logic [DW-1:0] div_q;
    logic [5:0] tx_count_q, rx_count_q;
    logic [255:0] tx_data_q;
    logic [6:0] byte_q;
    logic [2:0] bit_q;

    assign busy_o = state_q != IDLE;
    assign cs_n_o = state_q == IDLE;
    assign sck_o = state_q == HIGH;
    assign mosi_o = byte_q < tx_count_q ?
                    tx_data_q[byte_q*8 + (7-bit_q)] : 1'b0;

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            state_q <= IDLE;
            div_q <= '0;
            tx_count_q <= '0;
            rx_count_q <= '0;
            tx_data_q <= '0;
            byte_q <= '0;
            bit_q <= '0;
            rx_data_o <= '0;
            done_o <= 1'b0;
        end else begin
            done_o <= 1'b0;
            case (state_q)
                IDLE: if (start_i && tx_count_i + rx_count_i != 0 &&
                          tx_count_i + rx_count_i <= 32) begin
                    tx_count_q <= tx_count_i;
                    rx_count_q <= rx_count_i;
                    tx_data_q <= tx_data_i;
                    rx_data_o <= '0;
                    byte_q <= '0;
                    bit_q <= '0;
                    div_q <= '0;
                    state_q <= SETUP;
                end
                SETUP: begin
                    if (div_q == HALF_CYCLES - 1) begin
                        div_q <= '0;
                        state_q <= LOW;
                    end else div_q <= div_q + 1'b1;
                end
                LOW: begin
                    if (div_q == HALF_CYCLES - 1) begin
                        div_q <= '0;
                        if (byte_q >= tx_count_q)
                            rx_data_o[(byte_q-tx_count_q)*8 + (7-bit_q)] <= miso_i;
                        state_q <= HIGH;
                    end else div_q <= div_q + 1'b1;
                end
                HIGH: begin
                    if (div_q == HALF_CYCLES - 1) begin
                        div_q <= '0;
                        if (bit_q == 3'd7) begin
                            bit_q <= '0;
                            if (byte_q == tx_count_q + rx_count_q - 1) begin
                                state_q <= IDLE;
                                done_o <= 1'b1;
                            end else begin
                                byte_q <= byte_q + 1'b1;
                                state_q <= LOW;
                            end
                        end else begin
                            bit_q <= bit_q + 1'b1;
                            state_q <= LOW;
                        end
                    end else div_q <= div_q + 1'b1;
                end
                default: state_q <= IDLE;
            endcase
        end
    end
endmodule
