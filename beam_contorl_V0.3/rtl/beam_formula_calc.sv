`timescale 1ns/1ps

// Arithmetic equivalent to BJN110 cal_formula. The two /9375 operations
// use restoring division over 67 clocks so the 50 MHz path does not contain
// a large combinational divider. Signed division still truncates toward zero.
module beam_formula_calc #(
    parameter int signed X_DIS = 167,
    parameter int signed Y_DIS = 167
) (
    input  logic               clk_i,
    input  logic               rst_i,
    input  logic               start_i,
    input  logic [15:0]        frequency_i,
    input  logic signed [21:0] sin_az_i,
    input  logic signed [21:0] cos_el_i,
    input  logic signed [21:0] sin_el_i,
    output logic signed [60:0] left_o,
    output logic signed [60:0] right_o,
    output logic               done_o
);
    typedef enum logic [2:0] {IDLE, MUL2, MUL3, DIV_INIT, DIV_RUN} state_t;
    state_t state_q;
    logic [15:0] frequency_q;
    logic signed [43:0] left1_q, right1_q;
    logic signed [54:0] left2_q, right2_q;
    logic signed [66:0] left3_q, right3_q;
    logic [66:0] dividend_left_q, dividend_right_q;
    logic [66:0] quotient_left_q, quotient_right_q;
    logic [66:0] quotient_left_next, quotient_right_next;
    logic [13:0] remainder_left_q, remainder_right_q;
    logic [14:0] trial_left, trial_right;
    logic left_bit, right_bit;
    logic sign_left_q, sign_right_q;
    logic [6:0] bit_q;

    always_comb begin
        trial_left = {remainder_left_q, dividend_left_q[66]};
        trial_right = {remainder_right_q, dividend_right_q[66]};
        left_bit = trial_left >= 15'd9375;
        right_bit = trial_right >= 15'd9375;
        quotient_left_next = quotient_left_q;
        quotient_right_next = quotient_right_q;
        quotient_left_next[bit_q] = left_bit;
        quotient_right_next[bit_q] = right_bit;
    end

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            state_q <= IDLE;
            frequency_q <= '0;
            left1_q <= '0;
            right1_q <= '0;
            left2_q <= '0;
            right2_q <= '0;
            left3_q <= '0;
            right3_q <= '0;
            dividend_left_q <= '0;
            dividend_right_q <= '0;
            quotient_left_q <= '0;
            quotient_right_q <= '0;
            remainder_left_q <= '0;
            remainder_right_q <= '0;
            sign_left_q <= 1'b0;
            sign_right_q <= 1'b0;
            bit_q <= '0;
            left_o <= '0;
            right_o <= '0;
            done_o <= 1'b0;
        end else begin
            done_o <= 1'b0;
            case (state_q)
                IDLE: if (start_i) begin
                    frequency_q <= frequency_i;
                    left1_q <= $signed(sin_az_i) * $signed(cos_el_i);
                    right1_q <= $signed(sin_el_i) <<< 20;
                    state_q <= MUL2;
                end
                MUL2: begin
                    left2_q <= left1_q * X_DIS;
                    right2_q <= right1_q * Y_DIS;
                    state_q <= MUL3;
                end
                MUL3: begin
                    left3_q <= left2_q * $signed(frequency_q);
                    right3_q <= right2_q * $signed(frequency_q);
                    state_q <= DIV_INIT;
                end
                DIV_INIT: begin
                    sign_left_q <= left3_q < 0;
                    sign_right_q <= right3_q < 0;
                    dividend_left_q <= left3_q < 0 ? -left3_q : left3_q;
                    dividend_right_q <= right3_q < 0 ? -right3_q : right3_q;
                    quotient_left_q <= '0;
                    quotient_right_q <= '0;
                    remainder_left_q <= '0;
                    remainder_right_q <= '0;
                    bit_q <= 7'd66;
                    state_q <= DIV_RUN;
                end
                DIV_RUN: begin
                    remainder_left_q <= left_bit ? trial_left - 15'd9375 : trial_left;
                    remainder_right_q <= right_bit ? trial_right - 15'd9375 : trial_right;
                    dividend_left_q <= {dividend_left_q[65:0],1'b0};
                    dividend_right_q <= {dividend_right_q[65:0],1'b0};
                    quotient_left_q <= quotient_left_next;
                    quotient_right_q <= quotient_right_next;
                    if (bit_q == 0) begin
                        left_o <= sign_left_q ? -$signed(quotient_left_next) :
                                                 $signed(quotient_left_next);
                        right_o <= sign_right_q ? -$signed(quotient_right_next) :
                                                   $signed(quotient_right_next);
                        done_o <= 1'b1;
                        state_q <= IDLE;
                    end else bit_q <= bit_q - 1'b1;
                end
                default: state_q <= IDLE;
            endcase
        end
    end
endmodule
