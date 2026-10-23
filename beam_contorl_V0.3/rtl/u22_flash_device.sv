`timescale 1ns/1ps

// U22 low-level transactions, adapted from BJN110's WREN/PP/SE/RDID command
// sequence. Only a confirmed N25Q128A 3-V JEDEC ID permits modification.
// Record allocation and F1/F2/F3/F5 semantics belong to a separate service.
module u22_flash_device #(
    parameter logic [23:0] EXPECTED_JEDEC_ID = 24'h20BA18,
    parameter int unsigned MAX_STATUS_POLLS = 100_000
) (
    input  logic         clk_i,
    input  logic         rst_i,
    input  logic         probe_done_i,
    input  logic [23:0]  jedec_id_i,
    input  logic         request_i,
    input  logic [1:0]   operation_i, // 0=read, 1=program, 2=64-KiB erase
    input  logic [23:0]  address_i,
    input  logic [4:0]   length_i,    // 1..16 for read/program
    input  logic [127:0] write_data_i,
    input  logic         spi_busy_i,
    input  logic         spi_done_i,
    input  logic [255:0] spi_rx_i,
    output logic         spi_start_o,
    output logic [5:0]   spi_tx_count_o,
    output logic [5:0]   spi_rx_count_o,
    output logic [255:0] spi_tx_data_o,
    output logic         busy_o,
    output logic         done_o,
    output logic         error_o,
    output logic [127:0] read_data_o
);
    typedef enum logic [2:0] {IDLE, ISSUE, WAIT_BUSY, WAIT_DONE, EVALUATE} state_t;
    typedef enum logic [2:0] {CHECK_BLANK, WRITE_ENABLE, EXECUTE, POLL, VERIFY} phase_t;
    state_t state_q;
    phase_t phase_q;
    logic [1:0] op_q;
    logic [23:0] addr_q;
    logic [4:0] len_q;
    logic [127:0] data_q;
    logic [16:0] poll_count_q;
    logic compare_ok;

    assign busy_o = state_q != IDLE;
    assign spi_start_o = state_q == ISSUE && !spi_busy_i;
    always_comb begin
        spi_tx_count_o = 6'd0;
        spi_rx_count_o = 6'd0;
        spi_tx_data_o = '0;
        case (phase_q)
            CHECK_BLANK, VERIFY: begin
                spi_tx_count_o = 6'd5;
                spi_rx_count_o = {1'b0,len_q};
                spi_tx_data_o[7:0] = 8'h0B; // fast read, one dummy byte
                spi_tx_data_o[15:8] = addr_q[23:16];
                spi_tx_data_o[23:16] = addr_q[15:8];
                spi_tx_data_o[31:24] = addr_q[7:0];
            end
            WRITE_ENABLE: begin
                spi_tx_count_o = 6'd1;
                spi_tx_data_o[7:0] = 8'h06;
            end
            EXECUTE: begin
                spi_tx_data_o[15:8] = addr_q[23:16];
                spi_tx_data_o[23:16] = addr_q[15:8];
                spi_tx_data_o[31:24] = addr_q[7:0];
                if (op_q == 2'd0) begin
                    spi_tx_count_o = 6'd5;
                    spi_rx_count_o = {1'b0,len_q};
                    spi_tx_data_o[7:0] = 8'h0B;
                end else if (op_q == 2'd1) begin
                    spi_tx_count_o = 6'd4 + {1'b0,len_q};
                    spi_tx_data_o[7:0] = 8'h02;
                    for (integer b=0;b<16;b=b+1)
                        spi_tx_data_o[(b+4)*8 +: 8] = data_q[b*8 +: 8];
                end else begin
                    spi_tx_count_o = 6'd4;
                    spi_tx_data_o[7:0] = 8'hD8;
                end
            end
            POLL: begin
                spi_tx_count_o = 6'd1;
                spi_rx_count_o = 6'd1;
                spi_tx_data_o[7:0] = 8'h05;
            end
            default: begin end
        endcase
    end

    always_comb begin
        compare_ok = 1'b1;
        for (integer b=0;b<16;b=b+1)
            if (b < len_q &&
                ((phase_q == CHECK_BLANK && spi_rx_i[b*8 +: 8] != 8'hFF) ||
                 (phase_q == VERIFY && spi_rx_i[b*8 +: 8] !=
                  (op_q == 2'd1 ? data_q[b*8 +: 8] : 8'hFF))))
                compare_ok = 1'b0;
    end

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            state_q <= IDLE;
            phase_q <= EXECUTE;
            op_q <= '0;
            addr_q <= '0;
            len_q <= '0;
            data_q <= '0;
            poll_count_q <= '0;
            read_data_o <= '0;
            done_o <= 1'b0;
            error_o <= 1'b0;
        end else begin
            done_o <= 1'b0;
            case (state_q)
                IDLE: if (request_i) begin
                    op_q <= operation_i;
                    addr_q <= address_i;
                    len_q <= length_i;
                    data_q <= write_data_i;
                    poll_count_q <= '0;
                    read_data_o <= '0;
                    error_o <= 1'b0;
                    if (!probe_done_i || jedec_id_i != EXPECTED_JEDEC_ID ||
                        operation_i > 2 ||
                        (operation_i != 2 && (length_i == 0 || length_i > 16)) ||
                        (operation_i == 2 && (length_i != 0 || address_i[15:0] != 0)) ||
                        (operation_i == 1 &&
                         ({1'b0,address_i[7:0]} + {4'b0,length_i} > 9'd256))) begin
                        error_o <= 1'b1;
                        done_o <= 1'b1;
                    end else begin
                        phase_q <= operation_i == 2'd0 ? EXECUTE :
                                   operation_i == 2'd1 ? CHECK_BLANK : WRITE_ENABLE;
                        state_q <= ISSUE;
                    end
                end
                ISSUE: if (!spi_busy_i) state_q <= WAIT_BUSY;
                WAIT_BUSY: if (spi_busy_i) state_q <= WAIT_DONE;
                WAIT_DONE: if (spi_done_i) state_q <= EVALUATE;
                EVALUATE: begin
                    case (phase_q)
                        CHECK_BLANK: begin
                            if (!compare_ok) begin
                                error_o <= 1'b1;
                                done_o <= 1'b1;
                                state_q <= IDLE;
                            end else begin
                                phase_q <= WRITE_ENABLE;
                                state_q <= ISSUE;
                            end
                        end
                        WRITE_ENABLE: begin
                            phase_q <= EXECUTE;
                            state_q <= ISSUE;
                        end
                        EXECUTE: if (op_q == 2'd0) begin
                            read_data_o <= spi_rx_i[127:0];
                            done_o <= 1'b1;
                            state_q <= IDLE;
                        end else begin
                            phase_q <= POLL;
                            state_q <= ISSUE;
                        end
                        POLL: if (!spi_rx_i[0]) begin
                            phase_q <= VERIFY;
                            if (op_q == 2'd2) len_q <= 5'd16;
                            state_q <= ISSUE;
                        end else if (poll_count_q >= MAX_STATUS_POLLS) begin
                            error_o <= 1'b1;
                            done_o <= 1'b1;
                            state_q <= IDLE;
                        end else begin
                            poll_count_q <= poll_count_q + 1'b1;
                            state_q <= ISSUE;
                        end
                        VERIFY: begin
                            if (!compare_ok) error_o <= 1'b1;
                            read_data_o <= spi_rx_i[127:0];
                            done_o <= 1'b1;
                            state_q <= IDLE;
                        end
                        default: state_q <= IDLE;
                    endcase
                end
                default: state_q <= IDLE;
            endcase
        end
    end
endmodule
