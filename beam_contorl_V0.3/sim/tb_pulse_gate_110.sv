`timescale 1ns/1ps
module tb_pulse_gate_110;
    logic clk = 0, rst = 1;
    always #10 clk = ~clk;
    logic [7:0] mode = 0;
    wire tx_active, rx_active;
    integer tx_count, rx_count;
    pulse_gate_110 dut (.clk_i(clk), .rst_i(rst), .mode_i(mode),
                        .tx_active_o(tx_active), .rx_active_o(rx_active));
    task automatic count_period(input [7:0] code, input integer period,
                                input integer expected_tx, input integer expected_rx);
        integer i;
        begin
            @(negedge clk); mode = code;
            @(posedge clk);
            tx_count = 0; rx_count = 0;
            for (i=0;i<period;i=i+1) begin
                @(negedge clk);
                if (tx_active) tx_count = tx_count + 1;
                if (rx_active) rx_count = rx_count + 1;
                if (tx_active && rx_active) $fatal(1,"TX/RX overlap for %h",code);
            end
            if (tx_count != expected_tx || rx_count != expected_rx)
                $fatal(1,"pulse %h TX=%0d RX=%0d expected %0d/%0d",
                       code,tx_count,rx_count,expected_tx,expected_rx);
        end
    endtask
    initial begin
        repeat (2) @(posedge clk); @(negedge clk); rst = 0;
        count_period(8'h11,40020,4000,0);
        count_period(8'h21,20020,4000,0);
        count_period(8'h31,33333,4000,0);
        count_period(8'h41,18181,4000,0);
        count_period(8'h51,28571,4000,0);
        count_period(8'h61,26667,4000,0);
        count_period(8'h12,5000,0,1250);
        count_period(8'h00,100,0,0);
        $display("TB_PULSE_PASS source-cycle branches and TX/RX exclusion");
        $finish;
    end
endmodule
