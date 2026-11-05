`timescale 1ns/1ps
module tb_bjn110_math;
    reg clk=0, slow_clk=0, rst_n=0, start=0;
    always #10 clk=~clk;
    integer offset=0;
    initial begin
        offset=$test$plusargs("SLOW_OFFSET_10") ? 10 : 0;
        #(offset);
        forever #20 slow_clk=~slow_clk;
    end
    reg [15:0] frequency;
    reg signed [15:0] fw,fy,tx_fw,tx_fy;
    reg [7:0] wave;
    wire [191:0] rx,tx;
    wire [7:0] group_no;
    wire valid;
    cal_phase #(.X_DIS(167),.Y_DIS(167),.GROUP(32)) dut(
        .i_clk(clk),.i_clk_25m(slow_clk),.i_rst_n(rst_n),
        .i_cal_start(start),.i_wave_form(wave),.i_fre_value(frequency),
        .i_cal_fwrecv_phase(fw),.i_cal_fyrecv_phase(fy),
        .i_cal_fwtran_phase(tx_fw),.i_cal_fytran_phase(tx_fy),
        .o_cal_recvdata(rx),.o_cal_trandata(tx),
        .o_cal_group(group_no),.o_cal_valide(valid));

    reg trig_start=0;
    reg signed [15:0] trig_fw,trig_fy;
    wire signed [21:0] sin_fw,cos_fw,sin_fy,cos_fy;
    wire trig_valid;
    tri_fun trig_dut(.i_clk(clk),.i_rst_n(rst_n),
        .i_phase_fw(trig_fw),.i_phase_fy(trig_fy),.i_valide(trig_start),
        .o_sin_fw(sin_fw),.o_cos_fw(cos_fw),.o_sin_fy(sin_fy),
        .o_cos_fy(cos_fy),.o_tri_valide(trig_valid));

    reg [191:0] expected_rx[0:5887],expected_tx[0:5887];
    integer f,tf,scan,fi,ai,bi,ta,tb,wi;
    integer i,case_no=0,row=0,samples=0,errors=0,tag_errors=0;
    integer trig_errors=0,trig_cases=0,s1,c1,s2,c2,cycles;
    integer log_file;
    function automatic integer abs(input integer a);
        abs=a<0?-a:a;
    endfunction
    initial begin
        $readmemh("expected_rx.mem",expected_rx);
        $readmemh("expected_tx.mem",expected_tx);
        log_file=$fopen("rtl_results.csv","w");
        $fdisplay(log_file,"case,row,tag,rx,expected_rx,tx,expected_tx");
        frequency=980;fw=0;fy=0;tx_fw=0;tx_fy=0;wave=0;
        trig_fw=0;trig_fy=0;
        repeat(6) @(negedge clk);
        rst_n=1;
        tf=$fopen("trig_vectors.txt","r");
        if(tf==0) $fatal(1,"cannot open trig vectors");
        while (!$feof(tf)) begin
            scan=$fscanf(tf,"%d %d %d %d %d %d\n",ai,bi,s1,c1,s2,c2);
            if(scan==6) begin
                @(negedge clk);trig_fw=ai;trig_fy=bi;trig_start=1;
                @(negedge clk);trig_start=0;
                cycles=0;
                while(!trig_valid && cycles<20) begin @(negedge clk);cycles=cycles+1;end
                if(!trig_valid || $isunknown({sin_fw,cos_fw,sin_fy,cos_fy}) ||
                   abs(sin_fw-s1)>1 || abs(cos_fw-c1)>1 ||
                   abs(sin_fy-s2)>1 || abs(cos_fy-c2)>1) trig_errors=trig_errors+1;
                while(trig_valid) @(negedge clk);
                trig_cases=trig_cases+1;
            end
        end
        $fclose(tf);
        $display("TRIG_RESULT cases=%0d errors=%0d",trig_cases,trig_errors);
        f=$fopen("cases.txt","r");
        if(f==0) $fatal(1,"cannot open phase vectors");
        while (!$feof(f)) begin
            scan=$fscanf(f,"%d %d %d %d %d %d\n",fi,ai,bi,ta,tb,wi);
            if(scan==6) begin
                @(negedge clk);
                frequency=fi;fw=ai;fy=bi;tx_fw=ta;tx_fy=tb;wave=wi;start=1;
                @(negedge clk);start=0;
                row=0;
                for(i=0;i<400;i=i+1) begin
                    @(posedge clk);
                    // Observe exactly what the original downstream posedge FF sees.
                    if(valid) begin
                        samples=samples+1;
                        if(row>=32) begin errors=errors+1;end
                        else begin
                            if(rx !== expected_rx[case_no*32+row] ||
                               tx !== expected_tx[case_no*32+row]) begin
                                errors=errors+1;
                                if(errors<8) $display("PHASE_MISMATCH case=%0d row=%0d tag=%0d rx=%h expected=%h",case_no,row,group_no,rx,expected_rx[case_no*32+row]);
                            end
                            if(group_no !== row+1) tag_errors=tag_errors+1;
                            $fdisplay(log_file,"%0d,%0d,%0d,%048h,%048h,%048h,%048h",case_no,row,group_no,rx,expected_rx[case_no*32+row],tx,expected_tx[case_no*32+row]);
                        end
                        row=row+1;
                    end
                end
                if(row!=32) begin
                    $display("COUNT_MISMATCH case=%0d samples=%0d",case_no,row);
                    errors=errors+1;
                end
                case_no=case_no+1;
            end
        end
        $fclose(f);$fclose(log_file);
        $display("BJN110_RESULT offset=%0d cases=%0d samples=%0d data_errors=%0d tag_errors=%0d trig_errors=%0d",offset,case_no,samples,errors,tag_errors,trig_errors);
        if(errors || tag_errors || trig_errors || case_no!=184 || trig_cases!=18001 || samples!=5888)
            $fatal(1,"BJN110 original numerical behavior failed");
        $display("BJN110_NUMERIC_PASS");
        $finish;
    end
    initial begin #20_000_000;$fatal(1,"timeout");end
endmodule
