`timescale 1ns/1ps

// BJN110 pluse_gen timing branches mapped to CCAR10405L active-high T/R.
// 12 is 1250/5000 cycles in the source (25%, despite the old document label).
module pulse_gate_110 #(
    parameter int unsigned EDGE_GUARD_CYCLES = 10
) (
    input  logic       clk_i,
    input  logic       rst_i,
    input  logic [7:0] mode_i,
    output logic       tx_active_o,
    output logic       rx_active_o
);
    localparam int unsigned CW = 16;
    logic [CW-1:0] cycle_q;
    logic [7:0] previous_mode_q;
    logic [15:0] period;
    logic tx_pulse;

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            cycle_q <= '0;
            previous_mode_q <= 8'h00;
        end else begin
            previous_mode_q <= mode_i;
            if (previous_mode_q != mode_i || cycle_q >= period - 1)
                cycle_q <= '0;
            else
                cycle_q <= cycle_q + 1'b1;
        end
    end

    always_comb begin
        case (mode_i)
            8'h11: period = 16'd40020;
            8'h21: period = 16'd20020;
            8'h31: period = 16'd33333;
            8'h41: period = 16'd18181;
            8'h51: period = 16'd28571;
            8'h61: period = 16'd26667;
            8'h12: period = 16'd5000;
            default: period = 16'd40020;
        endcase
    end
    assign tx_pulse = cycle_q >= EDGE_GUARD_CYCLES && cycle_q < 16'd4010;
    assign tx_active_o = mode_i == 8'h01 ||
                         ((mode_i == 8'h11 || mode_i == 8'h21 || mode_i == 8'h31 ||
                           mode_i == 8'h41 || mode_i == 8'h51 || mode_i == 8'h61) && tx_pulse);
    assign rx_active_o = mode_i == 8'h02 || (mode_i == 8'h12 && cycle_q < 16'd1250);
endmodule
