`timescale 1ns/1ps
module tb_tr_spi_timing;
    import beam_cmd_pkg::*;
    logic clk_i=0, rst_i=1, start_i=0, load_start=0;
    logic [7:0] line_mask_i=8'h01, sdo_i;
    logic [767:0] frames_i='0;
    logic [191:0] sdo_last_o;
    logic ready_o, busy_o, write_done_o, load_ready, load_busy, inhibit, load_done;
    logic [31:0] sdi_o;
    logic [7:0] serial_clk_o, csb_o, ldb_o;
    logic [23:0] frame_expected, sdo_expected;
    logic sdo_bit=0, measuring=0;
    integer frame_rises=0, post_rises=0;
    time last_fall=0, csb_rise=0, ldb_fall=0, csb_fall=0, last_rise=0;
    always #10 clk_i=~clk_i;
    assign sdo_i={7'b1,sdo_bit};
    array_write_engine #(.SERIAL_HALF_PERIOD_CYCLES(5), .POST_FRAME_CLOCKS(2)) writer (.*);
    array_load_ctrl #(.CSB_TO_LDB_CYCLES(10), .LDB_LOW_CYCLES(50)) loader (
        .clk_i(clk_i), .rst_i(rst_i), .start_i(load_start), .line_mask_i(line_mask_i),
        .write_busy_i(busy_o), .csb_i(csb_o), .ready_o(load_ready), .busy_o(load_busy),
        .write_inhibit_o(inhibit), .load_done_o(load_done), .ldb_o(ldb_o));
    always @(negedge csb_o[0]) if (measuring) csb_fall=$time;
    always @(posedge serial_clk_o[0]) if (measuring) begin
        if (!csb_o[0]) begin
            if ((frame_rises==0 && ($time-csb_fall)!=100) ||
                (frame_rises>0 && ($time-last_rise)!=200))
                $fatal(1,"frame clock spacing at bit %0d",frame_rises);
            if (frame_rises >= 24 || sdi_o[0] !== frame_expected[23-frame_rises])
                $fatal(1,"SDI mismatch at bit %0d",frame_rises);
            frame_rises=frame_rises+1;
        end else begin
            if ((post_rises==0 && ($time-csb_rise)!=100) ||
                (post_rises>0 && ($time-last_rise)!=200))
                $fatal(1,"post clock spacing at edge %0d",post_rises);
            post_rises=post_rises+1;
        end
        last_rise=$time;
    end
    always @(negedge serial_clk_o[0]) if (measuring && !csb_o[0] && frame_rises>0 && frame_rises<=24) begin
        if (($time-last_rise)!=100) $fatal(1,"SCLK high width=%0t",$time-last_rise);
        if (frame_rises==24) begin
            last_fall=$time;
            sdo_bit <= #25 sdo_expected[0];
        end else sdo_bit=sdo_expected[24-frame_rises];
    end
    always @(posedge csb_o[0]) if (measuring) begin
        csb_rise=$time;
        if (frame_rises != 24 || ($time-last_fall) != 100)
            $fatal(1,"CSB timing rises=%0d hold=%0t",frame_rises,$time-last_fall);
    end
    always @(negedge ldb_o[0]) if (measuring) begin
        ldb_fall=$time;
        if (($time-csb_rise)<200 || post_rises != 2 || !csb_o[0])
            $fatal(1,"LDB guard=%0t post_rises=%0d",$time-csb_rise,post_rises);
    end
    always @(posedge ldb_o[0]) if (measuring && ldb_fall != 0)
        if (($time-ldb_fall)!=1000) $fatal(1,"LDB width=%0t",$time-ldb_fall);
    task automatic one_frame(input logic [23:0] tx, input logic [23:0] rx);
        begin
            @(negedge clk_i); frame_expected=tx; sdo_expected=rx; frames_i[23:0]=tx;
            frame_rises=0; post_rises=0; last_fall=0; csb_rise=0; ldb_fall=0;
            csb_fall=0; last_rise=0; sdo_bit=0;
            measuring=1; start_i=1;
            @(negedge clk_i); start_i=0;
            wait(write_done_o); #1;
            if (post_rises != 2 || sdo_last_o[23:0] !== rx)
                $fatal(1,"read mismatch got=%h expected=%h post=%0d",sdo_last_o[23:0],rx,post_rises);
            @(negedge clk_i); load_start=1;
            @(negedge clk_i); load_start=0;
            wait(load_done); #1;
            measuring=0;
        end
    endtask
    initial begin
        repeat(3) @(negedge clk_i); rst_i=0;
        one_frame(24'h320041,24'hA5C37E);
        one_frame(24'h320040,24'h5AC381);
        $display("TR_SPI_TIMING_PASS 24 bits, 100ns CSB hold, 2 post clocks, LDB guard and 1us pulse");
        $finish;
    end
    initial begin #100000; $fatal(1,"timing test timeout"); end
endmodule
