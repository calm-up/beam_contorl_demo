`timescale 1ns/1ps
module tb_s54_periodic_clock;
    import beam_cmd_pkg::*;
    logic clk_i=0, rst_i=1, start_i=0;
    logic [7:0] line_mask_i=0, sdo_i=0;
    logic [767:0] frames_i=0;
    wire [191:0] sdo_last_o;
    wire ready_o, busy_o, write_done_o;
    wire [31:0] sdi_o;
    wire [7:0] serial_clk_o, csb_o;
    wire [7:0] old_clk, old_csb;
    wire old_done;
    logic [23:0] expected[0:7];
    integer rises[0:7], post[0:7], totals[0:7];
    integer old_gaps=0, runs=0, csv;
    bit old_finished=0;
    bit completed[0:7];
    time edge_at[0:7];
    integer edge_count[0:7];
    always @(posedge old_done) old_finished=1;
    time last_rise[0:7], last_fall[0:7], cs_rise[0:7];
    time old_rise=0;
    bit measuring=0;
    always #10 clk_i=~clk_i;
    array_write_engine dut(.*);
    s53_reference_array_write_engine baseline(
        .clk_i(clk_i),.rst_i(rst_i),.start_i(start_i),.line_mask_i(line_mask_i),
        .frames_i(frames_i),.sdo_i(8'b0),.serial_clk_o(old_clk),
        .csb_o(old_csb),.write_done_o(old_done));
    always @(posedge old_clk[0]) if (measuring) begin
        if (old_rise != 0 && $time-old_rise != 200) begin
            if ($time-old_rise != 300) $fatal(1,"unexpected baseline interval");
            old_gaps++;
        end
        old_rise=$time;
    end
    for (genvar n=0;n<8;n++) begin : g_lane
        logic [23:0] incoming[0:3];
        initial begin edge_at[n]=0; edge_count[n]=0; completed[n]=0; end
        always @(serial_clk_o[n]) if (!rst_i) begin
            if (edge_at[n]!=0 && $time-edge_at[n]!=100)
                $fatal(1,"line%0d clock stopped/stretched, half=%0t",n,$time-edge_at[n]);
            edge_at[n]=$time;
            edge_count[n]++;
        end
        always @(posedge serial_clk_o[n]) if (measuring && line_mask_i[n]) begin

            last_rise[n]=$time;
            totals[n]++;
            if (!csb_o[n]) begin
                for (int c=0;c<4;c++) incoming[c]={incoming[c][22:0],sdi_o[n*4+c]};
                rises[n]++;
            end else if (completed[n]) begin
                if (post[n]==0 && $time-cs_rise[n]!=20)
                    $fatal(1,"CSB setup before post clock is not 20ns");
                post[n]++;
            end
            if (n==0) $fdisplay(csv,"%0t,s54_rise,%0b",$time,csb_o[n]);
        end
        always @(negedge serial_clk_o[n]) if (measuring && line_mask_i[n]) begin
            if (last_rise[n]!=0 && $time-last_rise[n]!=100) $fatal(1,"SCLK high width");
            last_fall[n]=$time;
            if (!csb_o[n] && rises[n]>0 && rises[n]<=24)
                sdo_i[n] <= #25 expected[n][24-rises[n]];
        end
        always @(negedge csb_o[n]) if (measuring) begin
            for (int c=0;c<4;c++) incoming[c]=0;
        end
        always @(posedge csb_o[n]) if (measuring && line_mask_i[n]) begin
            if (rises[n]!=24 || $time-last_fall[n]!=80)
                $fatal(1,"line%0d frame count / final hold invalid",n);
            for (int c=0;c<4;c++)
                if (incoming[c] !== frames_i[(n*4+c)*24+:24])
                    $fatal(1,"SDI data mismatch line%0d chip%0d",n,c);
            cs_rise[n]=$time;
            completed[n]=1;
            // Immediately lose the last bit after CSB, exposing late sampling.
            sdo_i[n] <= #1 ~expected[n][0];
        end
    end
    task automatic check_frame(input logic [7:0] mask, input logic [23:0] pattern);
        @(negedge clk_i);
        line_mask_i=mask;
        for (int n=0;n<8;n++) begin
            expected[n]=pattern ^ (n*24'h010101);
            rises[n]=0; post[n]=0; totals[n]=0; completed[n]=0;
            last_rise[n]=0; last_fall[n]=0; cs_rise[n]=0;
            for (int c=0;c<4;c++) frames_i[(n*4+c)*24+:24]=pattern ^ ((n*4+c)*24'h030507);
        end
        old_rise=0; old_finished=0; measuring=1; start_i=1;
        @(negedge clk_i); start_i=0;
        wait(write_done_o); #1;
        for (int n=0;n<8;n++) begin
            if (mask[n]) begin
                if (rises[n]!=24 || post[n]!=2 || sdo_last_o[n*24+:24]!==expected[n])
                    $fatal(1,"line%0d count or SDO mismatch %h/%h",n,sdo_last_o[n*24+:24],expected[n]);
            end else if (csb_o[n]!==1)
                $fatal(1,"unselected line was driven");
        end
        wait(old_finished); #1; measuring=0; runs++;
        #2000; // clock MUST keep running between independent requests
    endtask
    initial begin
        csv=$fopen("s54_periodic_edges.csv","w");
        $fdisplay(csv,"time_ps,event,csb");
        repeat(3) @(negedge clk_i); rst_i=0;
        check_frame(8'h01,24'hA5C37E);
        check_frame(8'h81,24'h5AC381);
        check_frame(8'hFF,24'h001001);
        for (int n=0;n<8;n++)
            if (edge_count[n]<200) $fatal(1,"idle/unselected-line clock absent");
        if (old_gaps!=3) $fatal(1,"baseline stretched-clock defect not reproduced");
        $fclose(csv);
        $display("S54_PERIODIC_CLOCK_PASS runs=%0d baseline_300ns_intervals=%0d s54_FREE_RUNNING_period=200ns high=100ns low=100ns idle_and_unselected_lines_checked CS_hold=80ns SDO_delay=25ns",runs,old_gaps);
        $finish;
    end
    initial begin #100000; $fatal(1,"periodic test timeout"); end
endmodule
