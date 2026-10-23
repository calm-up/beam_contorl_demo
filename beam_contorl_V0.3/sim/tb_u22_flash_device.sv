`timescale 1ns/1ps
module tb_u22_flash_device;
    logic clk = 0, rst = 1;
    always #10 clk = ~clk;
    logic request = 0, spi_busy = 0, spi_done = 0;
    logic [1:0] operation = 0;
    logic [23:0] address = 0;
    logic [4:0] length = 0;
    logic [127:0] write_data = 0;
    logic [23:0] jedec_id = 24'h20BA18;
    logic [255:0] spi_rx = 0;
    wire spi_start, busy, done, error;
    wire [5:0] tx_count, rx_count;
    wire [255:0] spi_tx;
    wire [127:0] read_data;
    integer bus_state = 0, command_count = 0, read_count = 0;
    reg [7:0] commands [0:15];
    u22_flash_device #(.MAX_STATUS_POLLS(8)) dut (
        .clk_i(clk),.rst_i(rst),.probe_done_i(1'b1),.jedec_id_i(jedec_id),
        .request_i(request),.operation_i(operation),.address_i(address),
        .length_i(length),.write_data_i(write_data),
        .spi_busy_i(spi_busy),.spi_done_i(spi_done),.spi_rx_i(spi_rx),
        .spi_start_o(spi_start),.spi_tx_count_o(tx_count),
        .spi_rx_count_o(rx_count),.spi_tx_data_o(spi_tx),
        .busy_o(busy),.done_o(done),.error_o(error),.read_data_o(read_data)
    );
    always @(posedge clk) begin
        spi_done <= 0;
        if (rst) begin
            spi_busy <= 0;
            bus_state <= 0;
        end else case (bus_state)
            0: if (spi_start) begin
                commands[command_count] <= spi_tx[7:0];
                command_count <= command_count + 1;
                if (spi_tx[7:0] == 8'h0B) begin
                    if (read_count == 0) spi_rx <= {128'b0,128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF};
                    else spi_rx <= {248'b0,8'hAA};
                    read_count <= read_count + 1;
                end else spi_rx <= 0;
                bus_state <= 1;
            end
            1: begin spi_busy <= 1; bus_state <= 2; end
            2: begin spi_busy <= 0; spi_done <= 1; bus_state <= 0; end
        endcase
    end
    task automatic request_op(input [1:0] op, input [23:0] addr,
                              input [4:0] len, input [127:0] data);
        begin
            @(negedge clk);
            operation = op; address = addr; length = len; write_data = data;
            request = 1;
            @(negedge clk); request = 0;
            wait(done); @(negedge clk);
        end
    endtask
    initial begin
        repeat (3) @(negedge clk); rst = 0;
        jedec_id = 24'hFFFFFF;
        request_op(1,24'h001234,3,96'h00CC55AA);
        if (!error || command_count != 0) $fatal(1,"unknown JEDEC was not blocked");
        jedec_id = 24'h20BA18;
        request_op(1,24'h001234,1,96'hAA);
        if (error || command_count != 5 || commands[0] != 8'h0B ||
            commands[1] != 8'h06 || commands[2] != 8'h02 ||
            commands[3] != 8'h05 || commands[4] != 8'h0B)
            $fatal(1,"program command sequence/readback wrong count=%0d err=%b",
                   command_count,error);
        command_count = 0; read_count = 0;
        request_op(2,24'h010000,0,0);
        if (error || command_count != 4 || commands[0] != 8'h06 ||
            commands[1] != 8'hD8 || commands[2] != 8'h05 || commands[3] != 8'h0B)
            $fatal(1,"sector erase command sequence wrong");
        $display("TB_U22_DEVICE_PASS ID gate, blank check, WREN, PP, D8, WIP, readback");
        $finish;
    end
    initial begin #1000000; $fatal(1,"U22 device timeout"); end
endmodule
