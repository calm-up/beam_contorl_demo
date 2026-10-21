`timescale 1ns/1ps

module tb_array_write_engine;
    import beam_cmd_pkg::*;

    localparam int unsigned HALF_CYCLES = 2;
    localparam int unsigned POST_CLOCKS = 2;

    logic clk_i = 1'b0;
    logic rst_i = 1'b1;
    logic start_i = 1'b0;
    logic [LINE_COUNT-1:0] line_mask_i = '0;
    logic [ARRAY_FRAME_BITS-1:0] frames_i = '0;
    logic ready_o;
    logic busy_o;
    logic write_done_o;
    logic [LINE_COUNT*CHIPS_PER_LINE-1:0] sdi_o;
    logic [LINE_COUNT-1:0] serial_clk_o;
    logic [LINE_COUNT-1:0] csb_o;

    logic [23:0] captured [0:LINE_COUNT-1][0:CHIPS_PER_LINE-1];
    integer sample_count = 0;
    integer post_rise_count = 0;
    integer line_index;
    integer chip_index;

    always #10 clk_i = ~clk_i;

    array_write_engine #(
        .SERIAL_HALF_PERIOD_CYCLES(HALF_CYCLES),
        .POST_FRAME_CLOCKS(POST_CLOCKS)
    ) dut (
        .*
    );

    // All selected lines share the same clock, so line 0 is the monitor clock.
    always @(posedge serial_clk_o[0]) begin
        if (!csb_o[0]) begin
            sample_count = sample_count + 1;
            for (line_index = 0; line_index < LINE_COUNT; line_index = line_index + 1) begin
                if (line_mask_i[line_index]) begin
                    if (csb_o[line_index] !== 1'b0) begin
                        $fatal(1, "Selected line %0d CSB is not active", line_index);
                    end
                    for (chip_index = 0; chip_index < CHIPS_PER_LINE; chip_index = chip_index + 1) begin
                        captured[line_index][chip_index] = {
                            captured[line_index][chip_index][22:0],
                            sdi_o[line_index*CHIPS_PER_LINE + chip_index]
                        };
                    end
                end
            end
        end else begin
            post_rise_count = post_rise_count + 1;
        end
    end

    // Lines outside the mask must never see an active CSB or serial clock.
    always @(posedge clk_i) begin
        if (!rst_i) begin
            for (line_index = 0; line_index < LINE_COUNT; line_index = line_index + 1) begin
                if (!line_mask_i[line_index] &&
                    ((csb_o[line_index] !== 1'b1) ||
                     (serial_clk_o[line_index] !== 1'b0))) begin
                    $fatal(1, "Unselected line %0d left its safe state", line_index);
                end
            end
        end
    end

    initial begin
        for (line_index = 0; line_index < LINE_COUNT; line_index = line_index + 1) begin
            for (chip_index = 0; chip_index < CHIPS_PER_LINE; chip_index = chip_index + 1) begin
                frames_i[frame_lsb(line_index, chip_index) +: FRAME_BITS] =
                    24'h800000 | (line_index << 8) | chip_index;
                captured[line_index][chip_index] = '0;
            end
        end
        line_mask_i = 8'b10100101;

        repeat (3) @(posedge clk_i);
        @(negedge clk_i);
        rst_i = 1'b0;
        @(posedge clk_i);
        if (!ready_o || busy_o) begin
            $fatal(1, "Engine did not enter idle state after reset");
        end

        @(negedge clk_i);
        start_i = 1'b1;
        @(negedge clk_i);
        start_i = 1'b0;

        // A start request while busy must not restart or replace the transaction.
        repeat (4) @(posedge clk_i);
        @(negedge clk_i);
        start_i = 1'b1;
        @(negedge clk_i);
        start_i = 1'b0;

        wait (write_done_o);
        #1;
        if (sample_count != FRAME_BITS) begin
            $fatal(1, "Expected 24 sampling edges, got %0d", sample_count);
        end
        if (post_rise_count != POST_CLOCKS) begin
            $fatal(1, "Expected %0d post-frame rising edges, got %0d",
                   POST_CLOCKS, post_rise_count);
        end
        for (line_index = 0; line_index < LINE_COUNT; line_index = line_index + 1) begin
            if (line_mask_i[line_index]) begin
                for (chip_index = 0; chip_index < CHIPS_PER_LINE; chip_index = chip_index + 1) begin
                    if (captured[line_index][chip_index] !==
                        frames_i[frame_lsb(line_index, chip_index) +: FRAME_BITS]) begin
                        $fatal(1, "Frame mismatch at line %0d chip %0d",
                               line_index, chip_index);
                    end
                end
            end
        end
        if (!ready_o || busy_o || serial_clk_o !== '0 ||
            csb_o !== {LINE_COUNT{1'b1}} || sdi_o !== '0) begin
            $fatal(1, "Engine outputs are not safe after completion");
        end

        // Second transaction selects all eight lines and verifies all 32 SDIs.
        sample_count = 0;
        post_rise_count = 0;
        for (line_index = 0; line_index < LINE_COUNT; line_index = line_index + 1) begin
            for (chip_index = 0; chip_index < CHIPS_PER_LINE; chip_index = chip_index + 1) begin
                captured[line_index][chip_index] = '0;
            end
        end
        @(negedge clk_i);
        line_mask_i = 8'hff;
        start_i = 1'b1;
        @(negedge clk_i);
        start_i = 1'b0;

        wait (write_done_o);
        #1;
        if (sample_count != FRAME_BITS || post_rise_count != POST_CLOCKS) begin
            $fatal(1, "Full-array clock count mismatch: samples=%0d post=%0d",
                   sample_count, post_rise_count);
        end
        for (line_index = 0; line_index < LINE_COUNT; line_index = line_index + 1) begin
            for (chip_index = 0; chip_index < CHIPS_PER_LINE; chip_index = chip_index + 1) begin
                if (captured[line_index][chip_index] !==
                    frames_i[frame_lsb(line_index, chip_index) +: FRAME_BITS]) begin
                    $fatal(1, "Full-array mismatch at line %0d chip %0d",
                           line_index, chip_index);
                end
            end
        end

        $display("STEP5_ARRAY_WRITE_ENGINE_PASS");
        $finish;
    end

endmodule
