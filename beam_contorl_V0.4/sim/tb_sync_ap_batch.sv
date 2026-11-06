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
                             input logic [7:0] command = 8'h45);
        logic [87:0] reply;
        logic [7:0] sum;
        do @(negedge sclk); while (serial_out !== 1'b0);
        reply = 2'b10;
        repeat (86) begin
            @(negedge sclk);
            reply = {reply[86:0], serial_out};
        end
        sum = 0;
        for (int k=2; k<=8; k++) sum += reply[(10-k)*8 +: 8];
        if (reply !== {16'hAADD, 8'h01, 8'd11, 8'h7F, array_sel,
                       command, status, count, sum, 8'h55})
            $fatal(1, "Unexpected response %026h", reply);
    endtask


    int rounds = 0, loads = 0;
    logic [23:0] captured [0:3];
    // RX line 0, CID 0, RF0. Model the SPI staging register and LDAC latch.
    logic [11:0] rx_staged_code = 0, rx_live_code = 0;
    logic check_rx_overlap = 0, switch_ready = 0;
    time load_start;
    always @(negedge csb[0]) if (monitor_spi) begin
        for (int c=0; c<4; c++) captured[c] = 0;
        repeat (24) begin
            @(posedge spi_clk[0]);
            for (int c=0; c<4; c++)
                captured[c] = {captured[c][22:0], sdi[c]};
        end
        if (captured[0][23:12] == 12'h020)
            rx_staged_code = captured[0][11:0];
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
        rx_live_code = rx_staged_code;
        loads++;
        #1;
        if (ldb !== (loads == 2 ? 8'h00 : 8'hFE)) $fatal(1, "Wrong load lines");
        @(posedge ldb[0]);
        if ($time-load_start != 600) $fatal(1, "LDAC width %0t", $time-load_start);
    end

    always @(negedge clk) if (check_rx_overlap) begin
        if (rx_active !== 8'h01 || tx_active !== 0 || ldb !== 8'hFF ||
            rx_live_code !== 12'h081)
            $fatal(1, "Old RX window or live code changed during next-batch preparation");
    end

    task automatic open_window;
        wavefront = 1;
        #2000;
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
            get_reply(0,1,8'h47);
            #200;
        end
        array_sel = 0;
        if (!dut.channel_rx_enable[0] || !dut.channel_tx_enable[0] ||
            dut.sync_external != 2'b11 || loads != 0)
            $fatal(1, "Separate enable/mode config failed");
        monitor_spi = 1;
        open_window();
        close_window();
        get_reply(7,0);
        #200;
        open_window();
        send_frame(8'h44, 3, 24'h013412);
        close_window();
        get_reply(3,0);
        #200;

        open_window();
        send_frame(8'h45, 11, 88'h0000000002050200000000, 1);
        close_window();
        get_reply(1,0);
        #200;
        if (rounds != 0 || loads != 0) $fatal(1, "Bad checksum executed");

        open_window();
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

        open_window();
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
        open_window();
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

        // Continue RX with the full-batch code, then switch RF0 in a gap.
        ext_t = 0;
        #500;
        ext_r = 1;
        #500;
        check_rx_overlap = 1;
        array_sel = 0;
        open_window();
        send_frame(8'h45, 11, 88'h000000000000030A010000);
        close_window();
        get_reply(0,1);
        switch_ready = 1;
        #200;
        if (rounds != 6 || loads != 2 || captured[0] !== 24'h0200CA ||
            rx_staged_code !== 12'h0CA)
            $fatal(1, "Next RX code was not staged while receiving");
        // A READY batch still cannot load while R is high.
        pulse_apply();
        #200;
        if (loads != 2) $fatal(1, "Apply accepted during RX");
        check_rx_overlap = 0;
        ext_r = 0;
        #500;
        if (rx_active != 0 || tx_active != 0) $fatal(1, "RX gap did not open");
        pulse_apply();
        #2500;
        if (loads != 3 || rx_live_code !== 12'h0CA)
            $fatal(1, "New RX code did not latch in the gap");
        ext_r = 1;
        #500;
        if (rx_active != 1 || tx_active != 0 || rx_live_code !== 12'h0CA)
            $fatal(1, "RX did not reopen with the new code");
        $display("TB_SYNC_AP_BATCH_PASS");
        $finish;
    end
    initial begin
        #1_000_000;
        $fatal(1, "timeout");
    end
endmodule
