`timescale 1ns/1ps

module tb_array_load_ctrl;
    import beam_cmd_pkg::*;

    localparam int unsigned GUARD_CYCLES = 4;
    localparam int unsigned LOW_CYCLES   = 3;

    logic clk_i = 1'b0;
    logic rst_i = 1'b1;
    logic start_i = 1'b0;
    logic [LINE_COUNT-1:0] line_mask_i = 8'b10100101;
    logic write_busy_i = 1'b0;
    logic [LINE_COUNT-1:0] csb_i = 8'hff;
    logic ready_o;
    logic busy_o;
    logic write_inhibit_o;
    logic load_done_o;
    logic [LINE_COUNT-1:0] ldb_o;

    time ldb_fall_time;
    integer index;

    always #10 clk_i = ~clk_i;

    array_load_ctrl #(
        .CSB_TO_LDB_CYCLES(GUARD_CYCLES),
        .LDB_LOW_CYCLES(LOW_CYCLES)
    ) dut (
        .*
    );

    task automatic pulse_start;
        begin
            @(negedge clk_i);
            start_i = 1'b1;
            @(negedge clk_i);
            start_i = 1'b0;
        end
    endtask

    task automatic check_load_pulse(input logic [LINE_COUNT-1:0] expected_mask);
        begin
            @(negedge ldb_o[0]);
            ldb_fall_time = $time;
            #1;
            if (ldb_o !== ~expected_mask || !busy_o || !write_inhibit_o) begin
                $fatal(1, "LDB target mask or load interlock is incorrect");
            end
            @(posedge ldb_o[0]);
            if (($time - ldb_fall_time) != LOW_CYCLES * 20ns) begin
                $fatal(1, "LDB low width is %0t, expected %0t",
                       $time - ldb_fall_time, LOW_CYCLES * 20ns);
            end
            #1;
            if (!load_done_o || busy_o || write_inhibit_o || ldb_o !== 8'hff) begin
                $fatal(1, "Load completion state is incorrect");
            end
        end
    endtask

    initial begin
        repeat (3) @(posedge clk_i);
        @(negedge clk_i);
        rst_i = 1'b0;
        @(posedge clk_i);
        #1;
        if (!ready_o || busy_o || ldb_o !== 8'hff) begin
            $fatal(1, "Load controller did not enter its safe idle state");
        end

        // A load request while the writer is busy must not be accepted.
        @(negedge clk_i);
        write_busy_i = 1'b1;
        pulse_start();
        repeat (2) @(posedge clk_i);
        #1;
        if (busy_o || ready_o || ldb_o !== 8'hff) begin
            $fatal(1, "Load request was accepted while write was busy");
        end

        // First completed write: LDB must remain inactive.
        repeat (3) @(posedge clk_i);
        @(negedge clk_i);
        write_busy_i = 1'b0;
        repeat (2) @(posedge clk_i);
        #1;
        if (ldb_o !== 8'hff) begin
            $fatal(1, "A completed write caused an automatic load");
        end

        // A second write also must not cause an automatic load.
        @(negedge clk_i);
        write_busy_i = 1'b1;
        repeat (3) @(posedge clk_i);
        #1;
        if (ldb_o !== 8'hff || busy_o) begin
            $fatal(1, "Repeated write activity changed LDB");
        end
        @(negedge clk_i);
        write_busy_i = 1'b0;
        @(posedge clk_i);
        #1;
        if (!ready_o || ldb_o !== 8'hff) begin
            $fatal(1, "Controller not ready after writer became idle");
        end

        // Write-then-load flow. Disturbing a selected CSB restarts the guard.
        pulse_start();
        repeat (2) @(posedge clk_i);
        @(negedge clk_i);
        csb_i[0] = 1'b0;
        repeat (2) @(posedge clk_i);
        #1;
        if (ldb_o !== 8'hff) begin
            $fatal(1, "LDB asserted while selected CSB was active");
        end
        @(negedge clk_i);
        csb_i = 8'hff;

        fork
            begin
                // LDB must stay high for the first GUARD_CYCLES-1 edges.
                for (index = 0; index < GUARD_CYCLES - 1; index = index + 1) begin
                    @(posedge clk_i);
                    #1;
                    if (ldb_o !== 8'hff) begin
                        $fatal(1, "LDB guard interval was too short");
                    end
                end
            end
            check_load_pulse(8'b10100101);
        join

        // Standalone load with a different mask, without a preceding write.
        @(negedge clk_i);
        line_mask_i = 8'b01011010;
        pulse_start();
        // Monitor a selected bit in this mask (line 1).
        @(negedge ldb_o[1]);
        ldb_fall_time = $time;
        #1;
        if (ldb_o !== ~8'b01011010 || !write_inhibit_o) begin
            $fatal(1, "Standalone load mask is incorrect");
        end
        @(posedge ldb_o[1]);
        if (($time - ldb_fall_time) != LOW_CYCLES * 20ns) begin
            $fatal(1, "Standalone LDB width is incorrect");
        end
        #1;
        if (!load_done_o || !ready_o || busy_o || ldb_o !== 8'hff) begin
            $fatal(1, "Standalone load did not complete correctly");
        end

        $display("STEP6_ARRAY_LOAD_CTRL_PASS");
        $finish;
    end

endmodule
