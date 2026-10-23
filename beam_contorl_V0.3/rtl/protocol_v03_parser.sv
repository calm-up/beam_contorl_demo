`timescale 1ns/1ps

// AA DD 01 LEN CMD ARRAY PAYLOAD SUM 55; SUM covers version through payload.
// Payload byte zero occupies payload_o[7:0]. One complete frame per valid pulse.
module protocol_v03_parser #(
    parameter int unsigned INTERBYTE_TIMEOUT_CYCLES = 1_000_000
) (
    input  logic         clk_i,
    input  logic         rst_i,
    input  logic         byte_valid_i,
    input  logic [7:0]   byte_i,
    input  logic         uart_error_i,
    output logic         frame_valid_o,
    output logic         frame_error_o,
    output logic [7:0]   error_status_o,
    output logic [7:0]   command_o,
    output logic [7:0]   array_o,
    output logic [7:0]   payload_len_o,
    output logic [447:0] payload_o,
    output logic [5:0]   rx_index_o
);
    localparam int unsigned TIMEOUT_W = (INTERBYTE_TIMEOUT_CYCLES < 2) ?
                                       1 : $clog2(INTERBYTE_TIMEOUT_CYCLES);
    logic [TIMEOUT_W-1:0] timeout_q;
    logic [7:0] length_q, sum_q, received_sum_q;
    logic [5:0] index_q;
    assign rx_index_o = index_q;

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            index_q <= '0;
            timeout_q <= '0;
            length_q <= '0;
            sum_q <= '0;
            received_sum_q <= '0;
            command_o <= '0;
            array_o <= '0;
            payload_len_o <= '0;
            payload_o <= '0;
            error_status_o <= '0;
            frame_valid_o <= 1'b0;
            frame_error_o <= 1'b0;
        end else begin
            frame_valid_o <= 1'b0;
            frame_error_o <= 1'b0;
            if (uart_error_i) begin
                index_q <= '0;
                timeout_q <= '0;
                frame_error_o <= 1'b1;
                error_status_o <= 8'h02;
            end else if (byte_valid_i) begin
                timeout_q <= '0;
                case (index_q)
                    6'd0: if (byte_i == 8'hAA) index_q <= 6'd1;
                    6'd1: begin
                        if (byte_i == 8'hDD) index_q <= 6'd2;
                        else index_q <= (byte_i == 8'hAA) ? 6'd1 : 6'd0;
                    end
                    6'd2: begin
                        if (byte_i == 8'h01) begin
                            sum_q <= byte_i;
                            index_q <= 6'd3;
                        end else begin
                            index_q <= (byte_i == 8'hAA) ? 6'd1 : 6'd0;
                            frame_error_o <= 1'b1;
                            error_status_o <= 8'h02;
                        end
                    end
                    6'd3: begin
                        if (byte_i >= 8'd8 && byte_i <= 8'd64) begin
                            length_q <= byte_i;
                            payload_len_o <= byte_i - 8'd8;
                            sum_q <= sum_q + byte_i;
                            payload_o <= '0;
                            index_q <= 6'd4;
                        end else begin
                            index_q <= (byte_i == 8'hAA) ? 6'd1 : 6'd0;
                            frame_error_o <= 1'b1;
                            error_status_o <= 8'h02;
                        end
                    end
                    default: begin
                        if (index_q == 6'd4) command_o <= byte_i;
                        if (index_q == 6'd5) array_o <= byte_i;
                        if (index_q >= 6'd6 && index_q < length_q - 8'd2)
                            payload_o[(index_q - 6'd6)*8 +: 8] <= byte_i;
                        if (index_q >= 6'd4 && index_q < length_q - 8'd2)
                            sum_q <= sum_q + byte_i;
                        if (index_q == length_q - 8'd2) received_sum_q <= byte_i;
                        if (index_q == length_q - 8'd1) begin
                            index_q <= (byte_i == 8'hAA) ? 6'd1 : 6'd0;
                            if (byte_i != 8'h55) begin
                                frame_error_o <= 1'b1;
                                error_status_o <= 8'h02;
                            end else if (received_sum_q != sum_q) begin
                                frame_error_o <= 1'b1;
                                error_status_o <= 8'h01;
                            end else frame_valid_o <= 1'b1;
                        end else index_q <= index_q + 6'd1;
                    end
                endcase
            end else if (index_q != 0) begin
                if (timeout_q == INTERBYTE_TIMEOUT_CYCLES - 1) begin
                    index_q <= '0;
                    timeout_q <= '0;
                    frame_error_o <= 1'b1;
                    error_status_o <= 8'h02;
                end else timeout_q <= timeout_q + 1'b1;
            end
        end
    end
endmodule
