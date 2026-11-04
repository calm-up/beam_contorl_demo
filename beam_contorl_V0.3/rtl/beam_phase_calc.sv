`timescale 1ns/1ps

// BJN110 trigonometric table and fixed-point formula, evaluated on this
// project's 8 x 16 geometry. The measured 9.6 mm pitch maps to coefficient
// 96 in the BJN110 0.1 mm distance convention. Chip 0 is at the right end
// when viewed as in the user-supplied array photo. DXF mid4 RF traces give
// left-to-right RF4, RF3, RF1, RF2 for each chip.
module beam_phase_calc #(
    parameter int signed X_DIS = 96,
    parameter int signed Y_DIS = 96
) (
    input  logic               clk_i,
    input  logic               rst_i,
    input  logic               start_i,
    input  logic [15:0]        frequency_i, // 10 MHz units, as in BJN110
    input  logic signed [15:0] azimuth_i,   // 0.01 degree units
    input  logic signed [15:0] elevation_i,
    input  logic [7:0]         line_mask_i,
    input  logic [3:0]         chip_mask_i,
    input  logic [3:0]         channel_mask_i,
    output logic [767:0]       phase_codes_o,
    output logic [127:0]       enable_bits_o,
    output logic               busy_o,
    output logic               done_o
);
    typedef enum logic [1:0] {ST_IDLE, ST_TRI, ST_FORMULA, ST_POINTS} state_t;
    state_t state_q;
    logic [6:0] point_q;
    logic [15:0] frequency_q;
    logic signed [15:0] azimuth_q, elevation_q;
    logic [7:0] line_mask_q;
    logic [3:0] chip_mask_q, channel_mask_q;
    wire signed [21:0] sin_az, cos_az, sin_el, cos_el;
    wire tri_valid, formula_valid;
    wire signed [60:0] formula_left, formula_right;
    logic signed [60:0] left_q, right_q;
    logic signed [7:0] x_coord, y_coord;
    logic [3:0] x_position;
    logic [1:0] rf_position;
    logic signed [63:0] phase_sum;
    logic [5:0] phase_code;

    // The original 110 tri_fun defines the Q20 lookup. beam_formula_calc
    // preserves cal_formula arithmetic with a clocked exact divide by 9375.
    tri_fun u_tri (
        .i_clk(clk_i), .i_rst_n(!rst_i), .i_phase_fw(azimuth_q),
        .i_phase_fy(elevation_q), .i_valide(state_q == ST_IDLE && start_i),
        .o_sin_fw(sin_az), .o_cos_fw(cos_az),
        .o_sin_fy(sin_el), .o_cos_fy(cos_el), .o_tri_valide(tri_valid)
    );
    beam_formula_calc #(.X_DIS(X_DIS), .Y_DIS(Y_DIS)) u_formula (
        .clk_i(clk_i), .rst_i(rst_i), .start_i(state_q == ST_TRI && tri_valid),
        .frequency_i(frequency_q), .sin_az_i(sin_az),
        .cos_el_i(cos_el), .sin_el_i(sin_el),
        .left_o(formula_left), .right_o(formula_right), .done_o(formula_valid)
    );

    // The 110 coordinate sequence is odd integers centered on the array.
    // Connector J1..J8 maps to RX line 0..7. Chip 0 occupies the rightmost
    // four positions in the array photo. Channel indices 0..3 (RF1..RF4)
    // occupy offsets 2,3,1,0 in each chip's four-element block.
    // Vertical line direction remains the configured line-index convention.
    // One coordinate step is half the element pitch.
    always_comb begin
        case (point_q[1:0])
            2'd0: rf_position = 2'd2; // RF1: third from left
            2'd1: rf_position = 2'd3; // RF2: rightmost
            2'd2: rf_position = 2'd1; // RF3: second from left
            2'd3: rf_position = 2'd0; // RF4: leftmost
        endcase
        x_position = {~point_q[3:2], rf_position};
        x_coord = -8'sd15 + $signed({3'b000, x_position, 1'b0});
        y_coord = -8'sd7 + $signed({4'b0000, point_q[6:4], 1'b0});
        phase_sum = -($signed(left_q) * $signed(x_coord)) +
                    ($signed(right_q) * $signed(y_coord));
        phase_code = phase_sum[45:40] + {5'b0, phase_sum[39]};
    end

    assign busy_o = state_q != ST_IDLE;

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            state_q <= ST_IDLE;
            point_q <= '0;
            frequency_q <= '0;
            azimuth_q <= '0;
            elevation_q <= '0;
            line_mask_q <= '0;
            chip_mask_q <= '0;
            channel_mask_q <= '0;
            left_q <= '0;
            right_q <= '0;
            phase_codes_o <= '0;
            enable_bits_o <= '0;
            done_o <= 1'b0;
        end else begin
            done_o <= 1'b0;
            case (state_q)
                ST_IDLE: if (start_i) begin
                    frequency_q <= frequency_i;
                    azimuth_q <= azimuth_i;
                    elevation_q <= elevation_i;
                    line_mask_q <= line_mask_i;
                    chip_mask_q <= chip_mask_i;
                    channel_mask_q <= channel_mask_i;
                    state_q <= ST_TRI;
                end
                ST_TRI: if (tri_valid) state_q <= ST_FORMULA;
                ST_FORMULA: if (formula_valid) begin
                    left_q <= formula_left;
                    right_q <= formula_right;
                    point_q <= '0;
                    state_q <= ST_POINTS;
                end
                ST_POINTS: begin
                    phase_codes_o[point_q*6 +: 6] <= phase_code;
                    enable_bits_o[point_q] <=
                        line_mask_q[point_q[6:4]] &&
                        chip_mask_q[point_q[3:2]] &&
                        channel_mask_q[point_q[1:0]];
                    if (point_q == 7'd127) begin
                        done_o <= 1'b1;
                        state_q <= ST_IDLE;
                    end else point_q <= point_q + 1'b1;
                end
                default: state_q <= ST_IDLE;
            endcase
        end
    end
endmodule
