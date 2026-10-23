`timescale 1ns/1ps

// Final 7F response; E0 carries five additional status bytes.
module protocol_v03_response #(
    parameter int unsigned CLK_HZ = 50_000_000,
    parameter int unsigned BAUD_RATE = 115_200
) (
    input  logic       clk_i,
    input  logic       rst_i,
    input  logic       start_i,
    input  logic [7:0] array_i,
    input  logic [7:0] original_command_i,
    input  logic [7:0] status_i,
    input  logic       extra_valid_i,
    input  logic [39:0] extra_i,
    output logic       ready_o,
    output logic       done_o,
    output logic       tx_byte_valid_o,
    output logic [7:0] tx_byte_o,
    output logic       serial_o
);
    typedef enum logic [1:0] {IDLE, ISSUE, WAIT_BYTE} state_t;
    state_t state_q;
    logic [3:0] index_q, length_q;
    logic [7:0] array_q, command_q, status_q, sum_q;
    logic [39:0] extra_q;
    logic byte_ready, byte_done;
    logic [7:0] byte_data;
    assign ready_o = state_q == IDLE;
    assign tx_byte_valid_o = (state_q == ISSUE);
    assign tx_byte_o = byte_data;
    always_comb begin
        case (index_q)
            4'd0: byte_data = 8'hAA;
            4'd1: byte_data = 8'hDD;
            4'd2: byte_data = 8'h01;
            4'd3: byte_data = {4'b0,length_q};
            4'd4: byte_data = 8'h7F;
            4'd5: byte_data = array_q;
            4'd6: byte_data = command_q;
            4'd7: byte_data = status_q;
            default: begin
                if (index_q == length_q - 2) byte_data = sum_q;
                else if (index_q == length_q - 1) byte_data = 8'h55;
                else byte_data = extra_q[(index_q - 4'd8)*8 +: 8];
            end
        endcase
    end
    uart_tx_byte #(.CLK_HZ(CLK_HZ), .BAUD_RATE(BAUD_RATE)) u_byte (
        .clk_i(clk_i), .rst_i(rst_i), .valid_i(tx_byte_valid_o),
        .data_i(byte_data), .ready_o(byte_ready), .done_o(byte_done), .serial_o(serial_o)
    );
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            state_q <= IDLE;
            index_q <= '0;
            length_q <= '0;
            array_q <= '0;
            command_q <= '0;
            status_q <= '0;
            extra_q <= '0;
            sum_q <= '0;
            done_o <= 1'b0;
        end else begin
            done_o <= 1'b0;
            case (state_q)
                IDLE: if (start_i) begin
                    array_q <= array_i;
                    command_q <= original_command_i;
                    status_q <= status_i;
                    extra_q <= extra_i;
                    length_q <= extra_valid_i ? 4'd15 : 4'd10;
                    sum_q <= 8'h01 + (extra_valid_i ? 8'd15 : 8'd10) +
                             8'h7F + array_i + original_command_i + status_i +
                             (extra_valid_i ? (extra_i[7:0] + extra_i[15:8] +
                              extra_i[23:16] + extra_i[31:24] + extra_i[39:32]) : 8'd0);
                    index_q <= '0;
                    state_q <= ISSUE;
                end
                ISSUE: if (byte_ready) state_q <= WAIT_BYTE;
                WAIT_BYTE: if (byte_done) begin
                    if (index_q == length_q - 1) begin
                        done_o <= 1'b1;
                        state_q <= IDLE;
                    end else begin
                        index_q <= index_q + 1'b1;
                        state_q <= ISSUE;
                    end
                end
                default: state_q <= IDLE;
            endcase
        end
    end
endmodule
