`timescale 1ns/1ps

// Fixed 10-byte V0.2 parser:
// AA ARRAY LINE CHIP CHANNEL ENABLE PHASE ATT SUM 55
module protocol_v02_parser #(
    parameter int unsigned INTERBYTE_TIMEOUT_CYCLES = 1_000_000
) (
    input  logic       clk_i,
    input  logic       rst_i,
    input  logic       byte_valid_i,
    input  logic [7:0] byte_i,
    input  logic       uart_error_i,
    output logic       command_valid_o,
    output logic       command_error_o,
    output logic       array_o,
    output logic [2:0] line_o,
    output logic [1:0] chip_o,
    output logic [1:0] channel_o,
    output logic       enable_o,
    output logic [5:0] phase_o,
    output logic [5:0] attenuation_o
);

    localparam int unsigned TIMEOUT_W =
        (INTERBYTE_TIMEOUT_CYCLES <= 2) ? 1 : $clog2(INTERBYTE_TIMEOUT_CYCLES);
    logic [3:0] index_q;
    logic [7:0] sum_q, received_sum_q;
    logic [TIMEOUT_W-1:0] timeout_q;
    logic [7:0] array_q, line_q, chip_q, channel_q;
    logic [7:0] enable_q, phase_q, attenuation_q;
    logic fields_legal;

    assign fields_legal =
        (array_q <= 8'd1) && (line_q <= 8'd7) &&
        (chip_q <= 8'd3) && (channel_q <= 8'd3) &&
        (enable_q <= 8'd1) && (phase_q <= 8'd63) &&
        (attenuation_q <= 8'd63);

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            index_q          <= '0;
            sum_q            <= '0;
            received_sum_q   <= '0;
            timeout_q        <= '0;
            command_valid_o  <= 1'b0;
            command_error_o  <= 1'b0;
            array_o          <= 1'b0;
            line_o           <= '0;
            chip_o           <= '0;
            channel_o        <= '0;
            enable_o         <= 1'b0;
            phase_o          <= '0;
            attenuation_o    <= '0;
        end else begin
            command_valid_o <= 1'b0;
            command_error_o <= 1'b0;

            if (uart_error_i) begin
                index_q         <= '0;
                timeout_q       <= '0;
                command_error_o <= 1'b1;
            end else if (byte_valid_i) begin
                timeout_q <= '0;
                if (index_q == 0) begin
                    if (byte_i == 8'hAA) begin
                        index_q <= 4'd1;
                        sum_q   <= '0;
                    end
                end else begin
                    case (index_q)
                        4'd1: begin array_q       <= byte_i; sum_q <= sum_q + byte_i; index_q <= 4'd2; end
                        4'd2: begin line_q        <= byte_i; sum_q <= sum_q + byte_i; index_q <= 4'd3; end
                        4'd3: begin chip_q        <= byte_i; sum_q <= sum_q + byte_i; index_q <= 4'd4; end
                        4'd4: begin channel_q     <= byte_i; sum_q <= sum_q + byte_i; index_q <= 4'd5; end
                        4'd5: begin enable_q      <= byte_i; sum_q <= sum_q + byte_i; index_q <= 4'd6; end
                        4'd6: begin phase_q       <= byte_i; sum_q <= sum_q + byte_i; index_q <= 4'd7; end
                        4'd7: begin attenuation_q <= byte_i; sum_q <= sum_q + byte_i; index_q <= 4'd8; end
                        4'd8: begin received_sum_q <= byte_i; index_q <= 4'd9; end
                        4'd9: begin
                            if ((byte_i == 8'h55) && (received_sum_q == sum_q) && fields_legal) begin
                                array_o       <= array_q[0];
                                line_o        <= line_q[2:0];
                                chip_o        <= chip_q[1:0];
                                channel_o     <= channel_q[1:0];
                                enable_o      <= enable_q[0];
                                phase_o       <= phase_q[5:0];
                                attenuation_o <= attenuation_q[5:0];
                                command_valid_o <= 1'b1;
                            end else begin
                                command_error_o <= 1'b1;
                            end
                            if (byte_i == 8'hAA) begin
                                index_q <= 4'd1;
                                sum_q   <= '0;
                            end else begin
                                index_q <= '0;
                            end
                        end
                        default: index_q <= '0;
                    endcase
                end
            end else if (index_q != 0) begin
                if (timeout_q == INTERBYTE_TIMEOUT_CYCLES - 1) begin
                    index_q         <= '0;
                    timeout_q       <= '0;
                    command_error_o <= 1'b1;
                end else begin
                    timeout_q <= timeout_q + 1'b1;
                end
            end
        end
    end
endmodule
