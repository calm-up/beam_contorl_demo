`timescale 1ns/1ps

// Step-3 smoke test only. The self-checking protocol testbench is step 9.
module tb_beam_ctrl_top;
    import beam_cmd_pkg::*;

    reg sys_clk_i = 1'b0;
    reg [7:0] rx_sdo_i = 8'b0;
    reg [7:0] tx_sdo_i = 8'b0;
    reg rs422_rx_i = 1'b1;
    reg debug_rs485_rx_i = 1'b0;
    reg spare_rs485_rx_i = 1'b0;
    wire rs422_tx_o;
    wire debug_rs485_tx_o, debug_rs485_dir_o;
    wire spare_rs485_tx_o, spare_rs485_dir_o;
    wire [31:0] rx_sdi_o, tx_sdi_o;
    wire [7:0] rx_clk_o, rx_csb_o, rx_ldb_o, rx_rstn_o, rx_t_o, rx_r_o;
    wire [7:0] tx_clk_o, tx_csb_o, tx_ldb_o, tx_rstn_o, tx_t_o, tx_r_o;
    reg [ARRAY_FRAME_BITS-1:0] frame_layout_check = '0;

    always #10 sys_clk_i = ~sys_clk_i;

    beam_ctrl_top dut (.*);

    initial begin
        if (ARRAY_FRAME_BITS != 768 ||
            frame_lsb(0, 0) != 0 || frame_lsb(0, 3) != 72 ||
            frame_lsb(1, 0) != 96 || frame_lsb(7, 3) != 744) begin
            $fatal(1, "Internal command frame layout constants are invalid");
        end
        frame_layout_check[frame_lsb(7, 3) +: FRAME_BITS] = 24'hA5_5A_C3;
        if (frame_layout_check[767:744] !== 24'hA5_5A_C3) begin
            $fatal(1, "Internal command frame slice mapping is invalid");
        end
        if (!command_is_legal(ARRAY_RX, 8'h01, 1'b1, 1'b0) ||
            !command_is_legal(ARRAY_BOTH, 8'h80, 1'b0, 1'b1) ||
            command_is_legal(ARRAY_NONE, 8'h01, 1'b1, 1'b0) ||
            command_is_legal(ARRAY_TX, 8'h00, 1'b1, 1'b0) ||
            command_is_legal(ARRAY_TX, 8'h01, 1'b1, 1'b1) ||
            command_is_legal(ARRAY_TX, 8'h01, 1'b0, 1'b0)) begin
            $fatal(1, "Internal command legality rules are invalid");
        end
        $display("STEP4_COMMAND_INTERFACE_PASS");
        #25;
        if (rx_sdi_o !== 32'b0 || tx_sdi_o !== 32'b0 ||
            rx_clk_o !== 8'b0 || tx_clk_o !== 8'b0 ||
            rx_csb_o !== 8'hff || tx_csb_o !== 8'hff ||
            rx_ldb_o !== 8'hff || tx_ldb_o !== 8'hff ||
            rx_rstn_o !== 8'b0 || tx_rstn_o !== 8'b0 ||
            rx_t_o !== 8'b0 || tx_t_o !== 8'b0 ||
            rx_r_o !== 8'b0 || tx_r_o !== 8'b0 ||
            rs422_tx_o !== 1'b1 ||
            debug_rs485_tx_o !== 1'b0 || debug_rs485_dir_o !== 1'b0 ||
            spare_rs485_tx_o !== 1'b0 || spare_rs485_dir_o !== 1'b0) begin
            $fatal(1, "Step-3 safe-state smoke test failed");
        end
        $display("STEP3_SMOKE_PASS");
        $finish;
    end
endmodule
