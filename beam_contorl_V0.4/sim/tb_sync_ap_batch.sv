`timescale 1ns/1ps

module tb_sync_ap_batch;
    logic clk = 0, sclk = 0;
    always #10 clk = ~clk;
    always #50 sclk = ~sclk;
    logic wavefront = 0, apply = 0, serial_in = 1;
    logic ext_t = 0, ext_r = 0, monitor_spi = 0;
    logic [7:0] array_sel = 0;
    wire serial_out;
    wire [7:0] csb, ldb, spi_clk;
    wire [7:0] rx_active, tx_active;
    wire [31:0] sdi;
    beam_ctrl_top #(.ENABLE_CHIP_INIT(0)) dut (
        .sys_clk_i(clk), .sync_clk_i(sclk), .wavefront_i(wavefront),
        .beam_apply_i(apply), .rs422_rx_i(serial_in), .rs422_tx_o(serial_out),
        .external_t_i(ext_t), .external_r_i(ext_r), .rx_sdo_i(8'b0),
        .tx_sdo_i(8'b0), .debug_rs485_rx_i(1'b1), .spare_rs485_rx_i(1'b1),
        .u22_miso_i(1'b1), .rx_csb_o(csb), .rx_ldb_o(ldb), .rx_clk_o(spi_clk),
        .rx_sdi_o(sdi), .rx_r_o(rx_active), .tx_t_o(tx_active)
    );

    task automatic send_frame(input logic [7:0] command, input int size,
                              input logic [87:0] data, input bit corrupt = 0);
        logic [7:0] sum;
        logic [7:0] bytes [0:18];
        bytes[0]=8'hAA; bytes[1]=8'hDD; bytes[2]=1;
        bytes[3]=size+8; bytes[4]=command; bytes[5]=array_sel;
        sum = 1 + size + 8 + command + array_sel;
        for (int k=0; k<size; k++) begin
            bytes[k+6]=data[k*8 +: 8];
            sum += bytes[k+6];
        end
        bytes[size+6]=sum ^ {7'b0,corrupt};
        bytes[size+7]=8'h55;
        for (int k=0; k<size+8; k++)
            for (int b=7; b>=0; b--) begin
                @(posedge sclk);
                serial_in <= bytes[k][b];
            end
    endtask

    task automatic get_reply(input logic [7:0] status, count,
                             input logic [7:0] command = 8'h44,
                             input logic [15:0] batch_id = 16'h1234);
        logic [103:0] reply;
        logic [7:0] sum;
        do @(negedge sclk); while (serial_out !== 1'b0);
        reply = 2'b10;
        repeat (102) begin
            @(negedge sclk);
            reply = {reply[102:0], serial_out};
        end
        sum = 0;
        for (int k=2; k<=10; k++) sum += reply[(12-k)*8 +: 8];
        if (reply !== {16'hAADD, 8'h01, 8'd13, 8'h7F, array_sel,
                       command, status, batch_id, count, sum, 8'h55})
            $fatal(1, "Unexpected response %026h", reply);
    endtask


    int rounds = 0, loads = 0;
    logic [23:0] captured [0:3];
    time load_start;
    always @(negedge csb[0]) if (monitor_spi) begin
        for (int c=0; c<4; c++) captured[c] = 0;
        repeat (24) begin
            @(posedge spi_clk[0]);
            for (int c=0; c<4; c++)
                captured[c] = {captured[c][22:0], sdi[c]};
        end
        rounds++;
        if (rounds == 1) begin
            if (captured[0] !== 24'h021085 || captured[1] !== 24'hF80000 ||
                captured[2] !== 24'h221107 || captured[3] !== 24'hF80000)
                $fatal(1, "Wrong parallel SDI %h %h %h %h",
                       captured[0],captured[1],captured[2],captured[3]);
        end else if (rounds >= 2 && rounds <= 5) begin
            for (int c=0; c<4; c++)
                if (captured[c] !== ((c << 20) | 24'h020081 | ((rounds-2)<<12)))
                    $fatal(1, "Wrong full-batch SDI lane %0d frame %h", c,captured[c]);
        end
    end
    always @(negedge ldb[0]) begin
        load_start = $time;
        loads++;
        #1;
        if (ldb !== (loads == 1 ? 8'hFE : 8'h00)) $fatal(1, "Wrong load lines");
        @(posedge ldb[0]);
        if ($time-load_start != 600) $fatal(1, "LDAC width %0t", $time-load_start);
    end

    task automatic open_window(input logic [7:0] count);
        wavefront = 1;
        #2000;
        send_frame(8'h44, 3, {count, 16'h3412});
    endtask
    task automatic close_window;
        @(posedge sclk);
        serial_in <= 1;
        #250;
        wavefront = 0;
    endtask
    task automatic pulse_apply;
        apply = 1;
        #500;
        apply = 0;
    endtask

    initial begin
        wait (dut.core_init);
        #2000;
        for (int side=0; side<2; side++) begin
            array_sel = 8'(side);
            wavefront = 1;
            #2000;
            send_frame(8'h47, 4, 32'h01000000);
            close_window();
            get_reply(0,1,8'h47,0);
            #200;
        end
        array_sel = 0;
        if (!dut.channel_rx_enable[0] || !dut.channel_tx_enable[0] ||
            dut.sync_external != 2'b11 || loads != 0)
            $fatal(1, "Separate enable/mode config failed");
        monitor_spi = 1;
        open_window(1);
        send_frame(8'h45, 11, 88'h0000000002050200000000, 1);
        close_window();
        get_reply(1,0);
        #200;
        if (rounds != 0 || loads != 0) $fatal(1, "Bad checksum executed");

        open_window(2);
        send_frame(8'h45, 11, 88'h0000000002050000020000);
        send_frame(8'h45, 11, 88'h0000000004070000020200);
        close_window();
        pulse_apply(); // too early, must not be queued
        get_reply(0,2);
        #200;
        if (rounds != 1 || loads != 0 || csb != 8'hFF)
            $fatal(1, "Preload did not produce one round without LDAC");
        pulse_apply();
        #3000;
        pulse_apply(); // duplicate, must not reload
        if (loads != 1 || !dut.sync_applied[0]) $fatal(1, "Expected one commit");
        #2000;

        open_window(32);
        for (int line=0; line<8; line++)
            for (int chip=0; chip<4; chip++)
                send_frame(8'h45, 11, {64'h0201020102010201, 8'h0F, 8'(chip), 8'(line)});
        close_window();
        get_reply(0,32);
        #200;
        if (rounds != 5 || loads != 1) $fatal(1, "Full batch did not produce four rounds");
        pulse_apply();
        #3000;
        if (loads != 2) $fatal(1, "Full batch did not commit");

        array_sel = 1;
        open_window(1);
        send_frame(8'h45, 11, {64'h0000000000000201, 8'h01, 8'h00, 8'h00});
        close_window();
        get_reply(0,1);
        #200;
        pulse_apply();
        #3000;
        if (!dut.sync_applied[1]) $fatal(1, "TX batch did not commit");

        ext_r = 1;
        #300;
        if (rx_active != 1 || tx_active != 0) $fatal(1, "External RX did not open");
        ext_t = 1;
        #100;
        if (rx_active != 0 || tx_active != 0) $fatal(1, "T/R overlap was not blocked");
        ext_r = 0;
        #80;
        if (tx_active != 0) $fatal(1, "TX opened inside the guard");
        #300;
        if (tx_active != 1 || rx_active != 0) $fatal(1, "External TX did not open");
        $display("TB_SYNC_AP_BATCH_PASS");
        $finish;
    end
    initial begin
        #1_000_000;
        $fatal(1, "timeout");
    end
endmodule
