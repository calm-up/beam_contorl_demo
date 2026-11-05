`timescale 1ns/1ps

// One-byte mailbox. Consecutive bytes are 800 ns apart at 10 MHz.
// Each bundled bus stays stable until its receiving clock has consumed it.
module sync_serial_phy (
    input wire clk_i, rst_i, sclk_i, wave_i, data_i,
    output logic data_o,
    output logic byte_valid_o, seal_o, partial_o,
    output logic [7:0] byte_o,
    input wire response_start_i,
    input wire [103:0] response_i,
    output wire response_done_o
);
    // Assert even when the external clock is stopped. Release at a
    // positive edge, with a half period before the receive edge.
    (* ASYNC_REG = "TRUE" *) logic [1:0] serial_reset_q;
    always_ff @(posedge sclk_i or posedge rst_i)
        if (rst_i) serial_reset_q <= '1;
        else serial_reset_q <= {serial_reset_q[0], 1'b0};
    wire serial_reset = serial_reset_q[1];

    (* ASYNC_REG = "TRUE" *) logic [1:0] wave_q;
    logic wave_previous_q, rx_active_q, byte_toggle_q, seal_toggle_q, partial_q;
    logic [7:0] shift_q, rx_byte_q, length_q;
    logic [6:0] byte_index_q;
    logic [2:0] bit_count_q;
    wire [7:0] next_byte = {shift_q[6:0], data_i};
    always_ff @(negedge sclk_i or posedge serial_reset) begin
        if (serial_reset) begin
            wave_q <= 0;
            wave_previous_q <= 0;
            rx_active_q <= 0;
            byte_toggle_q <= 0;
            seal_toggle_q <= 0;
            partial_q <= 0;
            shift_q <= 0;
            rx_byte_q <= 0;
            length_q <= 0;
            byte_index_q <= 0;
            bit_count_q <= 0;
        end else begin
            wave_q <= {wave_q[0], wave_i};
            wave_previous_q <= wave_q[1];
            if (!wave_q[1]) begin
                if (wave_previous_q) begin
                    partial_q <= rx_active_q;
                    seal_toggle_q <= ~seal_toggle_q;
                end
                rx_active_q <= 0;
            end else if (!rx_active_q) begin
                // Idle is high. AA starts with 10, so the first zero
                // identifies bit 6 without needing clock/byte alignment.
                if (!data_i) begin
                    rx_active_q <= 1;
                    shift_q <= 8'h02;
                    bit_count_q <= 2;
                    byte_index_q <= 0;
                end
            end else begin
                shift_q <= next_byte;
                bit_count_q <= bit_count_q + 1'b1;
                if (bit_count_q == 7) begin
                    rx_byte_q <= next_byte;
                    byte_toggle_q <= ~byte_toggle_q;
                    byte_index_q <= byte_index_q + 1'b1;
                    if (byte_index_q == 3) begin
                        length_q <= next_byte;
                        if (next_byte < 8 || next_byte > 64)
                            rx_active_q <= 0;
                    end else if (byte_index_q > 3 && byte_index_q == length_q - 1)
                        rx_active_q <= 0;
                end
            end
        end
    end

    (* ASYNC_REG = "TRUE" *) logic [1:0] byte_sync_q, seal_sync_q, done_sync_q;
    logic byte_seen_q, seal_seen_q, done_seen_q;
    logic request_q;
    logic [103:0] response_q;
    logic tx_done_q;
    assign response_done_o = done_seen_q != done_sync_q[1];
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            byte_sync_q <= 0;
            seal_sync_q <= 0;
            done_sync_q <= 0;
            byte_seen_q <= 0;
            seal_seen_q <= 0;
            done_seen_q <= 0;
            byte_o <= 0;
            byte_valid_o <= 0;
            seal_o <= 0;
            partial_o <= 0;
            request_q <= 0;
            response_q <= 0;
        end else begin
            byte_sync_q <= {byte_sync_q[0], byte_toggle_q};
            seal_sync_q <= {seal_sync_q[0], seal_toggle_q};
            done_sync_q <= {done_sync_q[0], tx_done_q};
            byte_seen_q <= byte_sync_q[1];
            seal_seen_q <= seal_sync_q[1];
            done_seen_q <= done_sync_q[1];
            byte_valid_o <= byte_seen_q != byte_sync_q[1];
            seal_o <= seal_seen_q != seal_sync_q[1];
            if (byte_seen_q != byte_sync_q[1]) byte_o <= rx_byte_q;
            if (seal_seen_q != seal_sync_q[1]) partial_o <= partial_q;
            if (response_start_i) begin
                response_q <= response_i;
                request_q <= ~request_q;
            end
        end
    end

    (* ASYNC_REG = "TRUE" *) logic [1:0] request_sync_q;
    logic tx_seen_q, tx_last_q;
    logic [6:0] tx_left_q;
    logic [102:0] tx_shift_q;
    always_ff @(posedge sclk_i or posedge serial_reset) begin
        if (serial_reset) begin
            request_sync_q <= 0;
            tx_seen_q <= 0;
            tx_last_q <= 0;
            tx_left_q <= 0;
            tx_shift_q <= '1;
            data_o <= 1;
        end else begin
            request_sync_q <= {request_sync_q[0], request_q};
            tx_last_q <= 0;
            if (tx_left_q != 0) begin
                data_o <= tx_shift_q[102];
                tx_shift_q <= {tx_shift_q[101:0], 1'b1};
                tx_left_q <= tx_left_q - 1'b1;
                tx_last_q <= tx_left_q == 1;
            end else if (request_sync_q[1] != tx_seen_q) begin
                tx_seen_q <= request_sync_q[1];
                // Every response starts with AA, whose first bit is high.
                data_o <= 1'b1;
                tx_shift_q <= response_q[102:0];
                tx_left_q <= 103;
            end else data_o <= 1;
        end
    end
    always_ff @(negedge sclk_i or posedge serial_reset)
        if (serial_reset) tx_done_q <= 0;
        else if (tx_last_q) tx_done_q <= tx_seen_q;
endmodule
