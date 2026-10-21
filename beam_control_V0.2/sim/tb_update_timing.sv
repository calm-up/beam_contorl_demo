`timescale 1ns/1ps

import beam_cmd_pkg::*;

module tb_update_timing;
    localparam time SYS_PERIOD_NS = 20ns;

    logic clk_i = 1'b0;
    logic rst_i = 1'b1;
    logic cmd_valid_i = 1'b0;
    logic [1:0] cmd_array_sel_i = ARRAY_NONE;
    logic [7:0] cmd_line_mask_i = 8'h00;
    logic [ARRAY_FRAME_BITS-1:0] cmd_rx_frames_i = '0;
    logic [ARRAY_FRAME_BITS-1:0] cmd_tx_frames_i = '0;
    logic cmd_write_i = 1'b0;
    logic cmd_load_i = 1'b0;
    logic cmd_ready_o, busy_o, write_done_o, load_done_o, error_o, init_done_o;
    logic [31:0] rx_sdi_o, tx_sdi_o;
    logic [7:0] rx_clk_o, rx_csb_o, rx_ldb_o, rx_rstn_o;
    logic [7:0] tx_clk_o, tx_csb_o, tx_ldb_o, tx_rstn_o;

    logic measure_rx, measure_tx, measure_load;
    integer rx_sample_edges, tx_sample_edges;
    time rx_csb_low_time, tx_csb_low_time;
    time rx_last_bit_time, tx_last_bit_time;
    time rx_csb_high_time, tx_csb_high_time;
    time write_done_time, load_done_time;
    time ldb_low_time, ldb_high_time;
    time command_accept_time;

    always #(SYS_PERIOD_NS/2) clk_i = ~clk_i;

    beam_ctrl_core dut (
        .clk_i(clk_i), .rst_i(rst_i),
        .cmd_valid_i(cmd_valid_i), .cmd_ready_o(cmd_ready_o),
        .cmd_array_sel_i(cmd_array_sel_i), .cmd_line_mask_i(cmd_line_mask_i),
        .cmd_rx_frames_i(cmd_rx_frames_i), .cmd_tx_frames_i(cmd_tx_frames_i),
        .cmd_write_i(cmd_write_i), .cmd_load_i(cmd_load_i),
        .busy_o(busy_o), .write_done_o(write_done_o),
        .load_done_o(load_done_o), .error_o(error_o), .init_done_o(init_done_o),
        .rx_sdi_o(rx_sdi_o), .rx_clk_o(rx_clk_o), .rx_csb_o(rx_csb_o),
        .rx_ldb_o(rx_ldb_o), .rx_rstn_o(rx_rstn_o),
        .tx_sdi_o(tx_sdi_o), .tx_clk_o(tx_clk_o), .tx_csb_o(tx_csb_o),
        .tx_ldb_o(tx_ldb_o), .tx_rstn_o(tx_rstn_o)
    );

    always @(negedge rx_csb_o[0])
        if (measure_rx && rx_csb_low_time == 0) rx_csb_low_time = $time;
    always @(negedge tx_csb_o[0])
        if (measure_tx && tx_csb_low_time == 0) tx_csb_low_time = $time;

    always @(posedge rx_clk_o[0]) begin
        if (measure_rx && !rx_csb_o[0]) begin
            rx_sample_edges = rx_sample_edges + 1;
            if (rx_sample_edges == 24) rx_last_bit_time = $time;
        end
    end

    always @(posedge tx_clk_o[0]) begin
        if (measure_tx && !tx_csb_o[0]) begin
            tx_sample_edges = tx_sample_edges + 1;
            if (tx_sample_edges == 24) tx_last_bit_time = $time;
        end
    end

    always @(posedge rx_csb_o[0]) if (measure_rx) rx_csb_high_time = $time;
    always @(posedge tx_csb_o[0]) if (measure_tx) tx_csb_high_time = $time;
    always @(posedge write_done_o) write_done_time = $time;
    always @(negedge rx_ldb_o[0]) if (measure_load) ldb_low_time = $time;
    always @(posedge rx_ldb_o[0]) if (measure_load) ldb_high_time = $time;
    always @(posedge load_done_o) load_done_time = $time;

    task automatic submit_command(
        input logic [1:0] array_sel,
        input logic do_write,
        input logic do_load
    );
        begin
            @(negedge clk_i);
            while (!cmd_ready_o) @(negedge clk_i);
            cmd_array_sel_i = array_sel;
            cmd_line_mask_i = 8'hff;
            cmd_write_i = do_write;
            cmd_load_i = do_load;
            cmd_valid_i = 1'b1;
            @(posedge clk_i);
            command_accept_time = $time;
            @(negedge clk_i);
            cmd_valid_i = 1'b0;
        end
    endtask

    task automatic measure_write(input logic [1:0] array_sel, input string label_text);
        time accepted;
        time completed;
        begin
            rx_sample_edges = 0;
            tx_sample_edges = 0;
            rx_csb_low_time = 0;
            tx_csb_low_time = 0;
            rx_last_bit_time = 0;
            tx_last_bit_time = 0;
            rx_csb_high_time = 0;
            tx_csb_high_time = 0;
            measure_rx = array_sel[0];
            measure_tx = array_sel[1];
            submit_command(array_sel, 1'b1, 1'b0);
            accepted = command_accept_time;
            @(posedge write_done_o);
            completed = $time;
            #1;

            if ((array_sel[0] && rx_sample_edges != 24) ||
                (array_sel[1] && tx_sample_edges != 24) || error_o) begin
                $fatal(1, "Timing measurement write failed: %s", label_text);
            end

            if (array_sel[0]) begin
                $display("STEP11_%s accept_ns=%0d csb_low_ns=%0d last_bit_ns=%0d csb_high_ns=%0d done_ns=%0d total_ns=%0d",
                    label_text, accepted/1ns, rx_csb_low_time/1ns,
                    rx_last_bit_time/1ns, rx_csb_high_time/1ns,
                    completed/1ns, (completed-accepted)/1ns);
            end else begin
                $display("STEP11_%s accept_ns=%0d csb_low_ns=%0d last_bit_ns=%0d csb_high_ns=%0d done_ns=%0d total_ns=%0d",
                    label_text, accepted/1ns, tx_csb_low_time/1ns,
                    tx_last_bit_time/1ns, tx_csb_high_time/1ns,
                    completed/1ns, (completed-accepted)/1ns);
            end
            measure_rx = 1'b0;
            measure_tx = 1'b0;
        end
    endtask

    time rx_sequence_start;
    time sequential_end;
    time both_start;
    time both_end;
    time write_complete_before_load;
    time csb_high_before_load;

    initial begin
        measure_rx = 1'b0;
        measure_tx = 1'b0;
        measure_load = 1'b0;
        for (int index = 0; index < ARRAY_FRAME_BITS; index++) begin
            cmd_rx_frames_i[index] = index[0];
            cmd_tx_frames_i[index] = ~index[0];
        end

        repeat (4) @(posedge clk_i);
        @(negedge clk_i);
        rst_i = 1'b0;
        wait (init_done_o && cmd_ready_o);

        measure_write(ARRAY_RX, "RX_FULL");
        measure_write(ARRAY_TX, "TX_FULL");

        // Sequential total includes the earliest next accepted command.
        measure_rx = 1'b1;
        rx_sample_edges = 0;
        submit_command(ARRAY_RX, 1'b1, 1'b0);
        rx_sequence_start = command_accept_time;
        @(posedge write_done_o);
        measure_rx = 1'b0;
        measure_tx = 1'b1;
        tx_sample_edges = 0;
        submit_command(ARRAY_TX, 1'b1, 1'b0);
        @(posedge write_done_o);
        sequential_end = $time;
        measure_tx = 1'b0;
        $display("STEP11_RX_TX_SEQUENTIAL start_ns=%0d end_ns=%0d total_ns=%0d",
                 rx_sequence_start/1ns, sequential_end/1ns,
                 (sequential_end-rx_sequence_start)/1ns);

        measure_rx = 1'b1;
        measure_tx = 1'b1;
        rx_sample_edges = 0;
        tx_sample_edges = 0;
        submit_command(ARRAY_BOTH, 1'b1, 1'b0);
        both_start = command_accept_time;
        @(posedge write_done_o);
        both_end = $time;
        if (rx_sample_edges != 24 || tx_sample_edges != 24)
            $fatal(1, "Simultaneous RX/TX edge count mismatch");
        measure_rx = 1'b0;
        measure_tx = 1'b0;
        $display("STEP11_RX_TX_SIMULTANEOUS start_ns=%0d end_ns=%0d total_ns=%0d",
                 both_start/1ns, both_end/1ns, (both_end-both_start)/1ns);

        // Measure the current two-command write-then-load path.
        measure_rx = 1'b1;
        rx_sample_edges = 0;
        submit_command(ARRAY_RX, 1'b1, 1'b0);
        @(posedge write_done_o);
        write_complete_before_load = $time;
        csb_high_before_load = rx_csb_high_time;
        measure_rx = 1'b0;
        measure_load = 1'b1;
        ldb_low_time = 0;
        ldb_high_time = 0;
        submit_command(ARRAY_RX, 1'b0, 1'b1);
        @(posedge load_done_o);
        #1;
        if (ldb_low_time == 0 || ldb_high_time == 0 || error_o)
            $fatal(1, "LDB timing measurement failed");
        $display("STEP11_RX_LOAD csb_high_ns=%0d write_done_ns=%0d load_accept_ns=%0d ldb_low_ns=%0d ldb_high_ns=%0d load_done_ns=%0d csb_high_to_ldb_ns=%0d write_done_to_ldb_ns=%0d",
                 csb_high_before_load/1ns, write_complete_before_load/1ns,
                 command_accept_time/1ns,
                 ldb_low_time/1ns, ldb_high_time/1ns, load_done_time/1ns,
                 (ldb_low_time-csb_high_before_load)/1ns,
                 (ldb_low_time-write_complete_before_load)/1ns);
        measure_load = 1'b0;

        $display("STEP11_TIMING_MEASUREMENT_PASS");
        $finish;
    end
endmodule
