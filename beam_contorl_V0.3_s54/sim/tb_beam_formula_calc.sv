`timescale 1ns/1ps

module tb_beam_formula_calc;
    logic clk = 1'b0;
    always #10 clk = ~clk;
    logic rst = 1'b1, start = 1'b0;
    logic [15:0] frequency;
    logic signed [21:0] sin_az, cos_el, sin_el;
    wire signed [60:0] left, right;
    wire done;
    beam_formula_calc dut (
        .clk_i(clk), .rst_i(rst), .start_i(start),
        .frequency_i(frequency), .sin_az_i(sin_az),
        .cos_el_i(cos_el), .sin_el_i(sin_el),
        .left_o(left), .right_o(right), .done_o(done)
    );

    task automatic check_case(
        input logic [15:0] f,
        input logic signed [21:0] sa, ce, se,
        input logic signed [60:0] expected_left, expected_right
    );
        begin
            @(negedge clk);
            frequency = f;
            sin_az = sa;
            cos_el = ce;
            sin_el = se;
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            wait(done);
            #1;
            if (left !== expected_left || right !== expected_right)
                $fatal(1,"formula mismatch f=%0d got=%0d/%0d expected=%0d/%0d",
                       f,left,right,expected_left,expected_right);
        end
    endtask

    initial begin
        frequency = '0;
        sin_az = '0;
        cos_el = '0;
        sin_el = '0;
        repeat (3) @(negedge clk);
        rst = 1'b0;
        check_case(1600, 524288, 1012847, 271391,
                   61'sd15134878577546, 61'sd8110740974774);
        check_case(1600, -524288, 1012847, 271391,
                   -61'sd15134878577546, 61'sd8110740974774);
        check_case(890, 0, 1048576, 0, 0, 0);
        check_case(1650, 1048576, 0, -1048576,
                   0, -61'sd32316845763592);
        check_case(32767, 1048576, 183, -1048576,
                   61'sd112003831331, -61'sd641773384930682);
        check_case(980, -183, 1048576, -183,
                   -61'sd3349826188, -61'sd3349826188);
        $display("TB_BEAM_FORMULA_PASS signed truncating /9375 vectors");
        $finish;
    end
    initial begin
        #200_000;
        $fatal(1,"formula timeout");
    end
endmodule
