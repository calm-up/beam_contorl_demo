`timescale 1ns/1ps

// Read-only power-up probe. A valid non-floating response is recorded, but no
// erase/program operation is authorized by this module.
module u22_flash_probe (
    input  logic         clk_i,
    input  logic         rst_i,
    input  logic         spi_busy_i,
    input  logic         spi_done_i,
    input  logic [255:0] spi_rx_i,
    output logic         spi_start_o,
    output logic [5:0]   spi_tx_count_o,
    output logic [5:0]   spi_rx_count_o,
    output logic [255:0] spi_tx_o,
    output logic [23:0]  jedec_id_o,
    output logic         probe_done_o,
    output logic         probe_valid_o
);
    typedef enum logic [1:0] {WAIT_START, WAIT_BUSY, WAIT_DONE, DONE} state_t;
    state_t state_q;
    assign spi_start_o = state_q == WAIT_START && !spi_busy_i;
    assign spi_tx_count_o = 6'd1;
    assign spi_rx_count_o = 6'd3;
    assign spi_tx_o = {248'b0,8'h9F};
    assign probe_done_o = state_q == DONE;
    assign probe_valid_o = probe_done_o && jedec_id_o != 24'h000000 &&
                           jedec_id_o != 24'hFFFFFF;
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            state_q <= WAIT_START;
            jedec_id_o <= '0;
        end else case (state_q)
            WAIT_START: if (!spi_busy_i) state_q <= WAIT_BUSY;
            WAIT_BUSY: if (spi_busy_i) state_q <= WAIT_DONE;
            WAIT_DONE: if (spi_done_i) begin
                jedec_id_o <= {spi_rx_i[7:0],spi_rx_i[15:8],spi_rx_i[23:16]};
                state_q <= DONE;
            end
            default: state_q <= DONE;
        endcase
    end
endmodule
