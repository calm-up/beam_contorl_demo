`timescale 1ns/1ps

// One half-duplex reply path. Busy requests are queued while another reply is
// on the wire; the dispatcher reply always returns to its ingress port.
module protocol_v03_rs485_port #(
    parameter int unsigned CLK_HZ = 50_000_000,
    parameter int unsigned BAUD_RATE = 115_200
) (
    input  logic        clk_i,
    input  logic        rst_i,
    input  logic        main_start_i,
    input  logic [7:0]  main_array_i,
    input  logic [7:0]  main_command_i,
    input  logic [7:0]  main_status_i,
    input  logic        main_extra_valid_i,
    input  logic [39:0] main_extra_i,
    output logic        main_ready_o,
    output logic        main_done_o,
    input  logic        busy_request_i,
    input  logic [7:0]  busy_array_i,
    input  logic [7:0]  busy_command_i,
    output logic        tx_o,
    output logic        dir_o,
    output logic        tx_byte_valid_o,
    output logic [7:0]  tx_byte_o
);
    logic pending_q, sending_main_q;
    logic [7:0] pending_array_q, pending_command_q;
    logic response_ready, response_done, response_active;
    logic send_busy;
    assign send_busy = response_ready && pending_q && !main_start_i;
    assign main_ready_o = response_ready && !pending_q;
    assign dir_o = response_active;
    assign main_done_o = response_done && sending_main_q;

    protocol_v03_response #(.CLK_HZ(CLK_HZ), .BAUD_RATE(BAUD_RATE)) u_response (
        .clk_i(clk_i), .rst_i(rst_i),
        .start_i(main_start_i || send_busy),
        .array_i(send_busy ? pending_array_q : main_array_i),
        .original_command_i(send_busy ? pending_command_q : main_command_i),
        .status_i(send_busy ? 8'h04 : main_status_i),
        .extra_valid_i(!send_busy && main_extra_valid_i),
        .extra_i(main_extra_i),
        .ready_o(response_ready), .done_o(response_done),
        .tx_byte_valid_o(tx_byte_valid_o), .tx_byte_o(tx_byte_o),
        .tx_active_o(response_active), .serial_o(tx_o)
    );

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            pending_q <= 1'b0;
            pending_array_q <= '0;
            pending_command_q <= '0;
            sending_main_q <= 1'b0;
        end else begin
            if (send_busy) pending_q <= 1'b0;
            if (busy_request_i && (!pending_q || send_busy)) begin
                pending_q <= 1'b1;
                pending_array_q <= busy_array_i;
                pending_command_q <= busy_command_i;
            end
            if (main_start_i) sending_main_q <= 1'b1;
            else if (send_busy) sending_main_q <= 1'b0;
            else if (response_done) sending_main_q <= 1'b0;
        end
    end
endmodule
