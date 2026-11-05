`timescale 1ns/1ps

module tb_array_write_sdo;
    import beam_cmd_pkg::*;

    localparam logic [23:0] EXPECTED = 24'hA5C37E;
    logic clk_i = 1'b0;
    logic rst_i = 1'b1;
    logic start_i = 1'b0;
    logic [7:0] line_mask_i = 8'h01;
    logic [767:0] frames_i = '0;
    logic [7:0] sdo_i;
    logic [191:0] sdo_last_o;
    logic ready_o, busy_o, write_done_o;
    logic [31:0] sdi_o;
    logic [7:0] serial_clk_o, csb_o;
    integer frame_bit_count = 0;
    logic sdo_bit_q = 1'b0;

    always #10 clk_i = ~clk_i;

    always_comb begin
        sdo_i = '1;
        sdo_i[0] = sdo_bit_q;
    end

    always @(posedge serial_clk_o[0]) begin
        if (!csb_o[0]) frame_bit_count = frame_bit_count + 1;
    end
    always @(negedge serial_clk_o[0]) begin
        if (frame_bit_count >= 1 && frame_bit_count < 24)
            sdo_bit_q = EXPECTED[24-frame_bit_count];
        else if (frame_bit_count == 24)
            sdo_bit_q <= #25 EXPECTED[0];
    end

    array_write_engine #(
        .SERIAL_HALF_PERIOD_CYCLES(5),
        .POST_FRAME_CLOCKS(2)
    ) dut (.*);

    initial begin
        repeat (3) @(negedge clk_i);
        rst_i = 1'b0;
        @(negedge clk_i);
        start_i = 1'b1;
        @(negedge clk_i);
        start_i = 1'b0;
        wait (write_done_o);
        #1;
        if (frame_bit_count != 24 || sdo_last_o[23:0] !== EXPECTED)
            $fatal(1, "SDO frame corrupted: bits=%0d got=%h expected=%h",
                   frame_bit_count, sdo_last_o[23:0], EXPECTED);
        $display("ARRAY_WRITE_SDO_PASS frame=%h post_clocks=2", sdo_last_o[23:0]);
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "SDO capture timed out");
    end
endmodule
