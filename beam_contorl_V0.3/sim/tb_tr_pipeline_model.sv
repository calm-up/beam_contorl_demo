`timescale 1ns/1ps
// Behavioral interpretation of the manual: SDI shifts on rising SCLK,
// CS rising prepares a read, and a subsequent CS-low frame shifts SDO.
module tb_tr_pipeline_model;
    import beam_cmd_pkg::*;
    logic clk_i=0,rst_i=1,start_i=0,ldb=1;
    logic [7:0] line_mask_i=1,sdo_i;
    logic [767:0] frames_i=0;
    logic [191:0] sdo_last_o;
    logic ready_o,busy_o,write_done_o;
    logic [31:0] sdi_o;
    logic [7:0] serial_clk_o,csb_o;
    logic [23:0] input_shift=0, pending=0, answer=0;
    logic [11:0] first_stage=0, second_stage=0;
    logic pending_write=0, sdo_bit=0;
    integer bits=0;
    always #10 clk_i=~clk_i;
    assign sdo_i={7'b1,sdo_bit};
    array_write_engine #(.SERIAL_HALF_PERIOD_CYCLES(5),.POST_FRAME_CLOCKS(2)) dut (.*);
    always @(negedge csb_o[0]) begin bits=0;input_shift=0;sdo_bit=0;end
    always @(posedge serial_clk_o[0]) begin
        if (!csb_o[0]) begin
            input_shift={input_shift[22:0],sdi_o[0]};
            bits=bits+1;
        end else if (pending_write) begin
            if (pending[23:20]==3 && pending[19:16]==4'h2 && pending[15:12]==0)
                first_stage=pending[11:0];
            pending_write=0;
        end
    end
    always @(negedge serial_clk_o[0]) if (!csb_o[0] && bits>0 && bits<=24)
        sdo_bit <= #25 answer[24-bits];
    always @(posedge csb_o[0]) if (bits==24) begin
        if (input_shift[23:20]==3 && input_shift[19:16]==4'hA && input_shift[15:12]==0)
            answer={input_shift[23:12],first_stage};
        else answer=0;
        pending=input_shift;
        pending_write=!input_shift[19];
    end
    always @(negedge ldb) second_stage=first_stage;
    task automatic send_frame(input logic [23:0] f);
        begin
            @(negedge clk_i);frames_i[23:0]=f;start_i=1;
            @(negedge clk_i);start_i=0;
            wait(write_done_o);#1;
        end
    endtask
    initial begin
        repeat(3) @(negedge clk_i);rst_i=0;
        send_frame(24'h320040);
        if (first_stage!==12'h040 || second_stage!==0) $fatal(1,"write/load isolation failed");
        send_frame(24'h3A0000);
        send_frame(24'h380000);
        if (sdo_last_o[23:0]!==24'h3A0040) $fatal(1,"pipeline got %h",sdo_last_o[23:0]);
        @(negedge clk_i);ldb=0;#20;ldb=1;
        if (second_stage!==12'h040) $fatal(1,"LDB did not load");
        $display("TR_PIPELINE_MODEL_PASS write 320040 -> read 3A0040, LDB copies stage 1");
        $finish;
    end
    initial begin #100000; $fatal(1,"pipeline timeout"); end
endmodule
