`timescale 1ns/1ps
// Exercise the real reader + core + serializer. The chip model deliberately
// drives the PREVIOUS request's result, never a combinational SDI echo.
module tb_chip_sdo_pipeline;
    import beam_cmd_pkg::*;
    logic clk=0, rst=1, start=0, manual_valid=0;
    logic [1:0] chip=0;
    logic [767:0] manual_frames='0, read_frames;
    logic read_valid, ready, write_done, core_error, busy, done, error;
    logic [1:0] read_array;
    logic [7:0] read_lines;
    logic [23:0] value;
    logic [191:0] rx_last, tx_last;
    wire [31:0] sdi;
    wire [7:0] sclk, csb, rstn;
    wire [31:0] raw_sdi;
    wire [7:0] raw_sclk, raw_csb, raw_rstn;
    // Filter delta-cycle procedural defaults in the combinational pin router.
    // These are model-side delays, not changes to the synthesized DUT.
    assign #1 sdi=raw_sdi;
    assign #1 sclk=raw_sclk;
    assign #1 csb=raw_csb;
    assign #1 rstn=raw_rstn;
    logic sdo=0;
    logic [11:0] stored[0:3];
    logic [23:0] incoming[0:3];
    logic [23:0] buffered=24'hDEAD55;
    integer bit_count=0, frame_count=0, read_begin=0;
    always #10 clk=~clk;
    chip_sdo_reader #(.TIMEOUT_CYCLES(100000)) reader (
        .clk_i(clk),.rst_i(rst),.start_i(start),.array_i(1'b0),
        .line_i(3'd0),.chip_i(chip),.function_i(3'd2),.address_i(8'd0),
        .core_ready_i(ready),.core_write_done_i(write_done),.core_error_i(core_error),
        .rx_sdo_last_i(rx_last),.tx_sdo_last_i(tx_last),
        .core_valid_o(read_valid),.core_array_o(read_array),.core_lines_o(read_lines),
        .core_frames_o(read_frames),.busy_o(busy),.done_o(done),.error_o(error),.value_o(value)
    );
    beam_ctrl_core #(.ENABLE_CHIP_INIT(0)) core (
        .clk_i(clk),.rst_i(rst),.reinit_start_i(1'b0),
        .reinit_array_i(ARRAY_RX),.reinit_lines_i(8'h01),
        .cmd_valid_i(read_valid || manual_valid),.cmd_ready_o(ready),
        .cmd_array_sel_i(read_valid ? read_array : ARRAY_RX),
        .cmd_line_mask_i(read_valid ? read_lines : 8'h01),
        .cmd_rx_frames_i(read_valid ? read_frames : manual_frames),
        .cmd_tx_frames_i('0),.cmd_write_i(1'b1),.cmd_load_i(1'b0),
        .write_done_o(write_done),.error_o(core_error),
        .rx_sdo_i({7'b1,sdo}),.tx_sdo_i(8'hFF),
        .rx_sdo_last_o(rx_last),.tx_sdo_last_o(tx_last),
        .rx_sdi_o(raw_sdi),.rx_clk_o(raw_sclk),.rx_csb_o(raw_csb),.rx_rstn_o(raw_rstn)
    );
    always @(negedge csb[0]) begin
        bit_count=0;
        for (int c=0;c<4;c++) incoming[c]=0;
        sdo=0;
    end
    always @(posedge sclk[0]) if (rstn[0] && !csb[0]) begin
        for (int c=0;c<4;c++) incoming[c]={incoming[c][22:0],sdi[c]};
        bit_count++;
    end
    always @(negedge sclk[0]) if (rstn[0] && !csb[0] && bit_count>0 && bit_count<=24)
        sdo <= #25 buffered[24-bit_count];
    always @(posedge csb[0]) if (rstn[0] && bit_count==24) begin
        frame_count++;
        $display("MODEL frame=%0d SDI=%h/%h/%h/%h captured=%h buffer=%h",frame_count,
                 incoming[0],incoming[1],incoming[2],incoming[3],rx_last[23:0],buffered);
        // Preserve the buffer during the frame; only prepare the NEXT frame.
        for (int c=0;c<4;c++) begin
            if (incoming[c][23:20]==c && incoming[c][18:16]==2 && incoming[c][15:12]==0) begin
                if (!incoming[c][19]) stored[c]=incoming[c][11:0];
                else buffered={incoming[c][23:12],stored[c]};
            end
        end
    end
    always @(posedge clk) if (done && frame_count!=read_begin+2)
        $fatal(1,"reader returned before/after wrong response frame");
    task automatic write_and_read(input logic [1:0] c,input logic [11:0] data);
        logic [23:0] expected;
        begin
            wait(ready); @(negedge clk);
            for (int lane=0;lane<32;lane++) manual_frames[lane*24+:24]=24'hF80000;
            manual_frames[c*24+:24]={2'b0,c,4'h2,4'h0,data};
            manual_valid=1;
            @(negedge clk); manual_valid=0;
            wait(write_done); @(negedge clk);
            // First read frame has a plausible but deliberately wrong OLD value.
            // Catch both first-frame capture and shifted/cached data reuse.
            buffered={2'b0,c,4'hA,4'h0,~data};
            expected={2'b0,c,4'hA,4'h0,data};
            chip=c; read_begin=frame_count; start=1;
            @(negedge clk); start=0;
            wait(done || error); #1;
            if (error || value!==expected || value=={2'b0,c,20'hA0000})
                $fatal(1,"CID %d returned %h expected %h error=%b",c,value,expected,error);
            if (incoming[c]!=={2'b0,c,20'h80000}) $fatal(1,"wrong dummy CID");
            $display("CID=%0d request=%h first_frame_old=%h dummy=%h returned=%h",
                     c,{2'b0,c,20'hA0000},{2'b0,c,4'hA,4'h0,~data},incoming[c],value);
            @(negedge clk);
        end
    endtask
    initial begin
        for (int c=0;c<4;c++) stored[c]=0;
        repeat(3) @(negedge clk); rst=0;
        write_and_read(3,12'h040);
        write_and_read(0,12'hA53);
        write_and_read(2,12'h581);
        write_and_read(1,12'hC2A);
        write_and_read(3,12'h7C1);
        $display("CHIP_SDO_PIPELINE_PASS real reader/core, distinct old/request/dummy/data, CID 3/0/2/1/3");
        $finish;
    end
    initial begin #1000000; $fatal(1,"pipeline timeout"); end
endmodule
