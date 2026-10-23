`timescale 1ns/1ps

// V0.3 logical records on U22. Address high bits follow BJN110: [23] array,
// [22:21] category, [20:16] line/frequency slot. F1 erases a whole 64-KiB
// sector, as the original flash_ctrl/SECE path does; this is not a per-channel
// erase. F2 writes one blank 16-byte slot. F3 reloads a scope into BRAM.
module u22_flash_record_service (
    input  logic         clk_i,
    input  logic         rst_i,
    input  logic         start_i,
    input  logic [7:0]   command_i,
    input  logic         array_i,
    input  logic [95:0]  payload_i,
    input  logic         device_busy_i,
    input  logic         device_done_i,
    input  logic         device_error_i,
    input  logic [127:0] device_read_data_i,
    output logic         device_request_o,
    output logic [1:0]   device_operation_o,
    output logic [23:0]  device_address_o,
    output logic [4:0]   device_length_o,
    output logic [127:0] device_write_data_o,
    output logic         busy_o,
    output logic         done_o,
    output logic         error_o,
    output logic [10:0]  loaded_count_o,
    output logic [23:0]  cache_sample_o
);
    localparam int unsigned RECORDS_PER_ARRAY = 801; // 128 + 512 + 32 + 129
    typedef enum logic [2:0] {IDLE, ISSUE, WAIT_BUSY, WAIT_DONE, EVALUATE, CLEAR, SAMPLE, DIGEST} state_t;
    state_t state_q;
    logic [7:0] cmd_q;
    logic array_q;
    logic [1:0] category_q;
    logic [4:0] slot_q;
    logic [7:0] record_q;
    logic [95:0] payload_q;
    logic [9:0] iteration_q, iteration_limit_q;
    logic [10:0] clear_base_q, clear_count_q, clear_index_q;
    logic [10:0] last_valid_index_q;
    logic [127:0] cache_word_q;
    logic [23:0] sample_digest;
    (* ram_style = "block" *) logic [127:0] cache_data [0:1601];
    (* ram_style = "block" *) logic cache_valid [0:1601];
    logic [4:0] active_slot;
    logic [7:0] active_record;
    logic [10:0] active_cache_index;
    logic [7:0] p [0:11];
    logic [7:0] checksum, read_checksum;
    logic record_blank, record_valid;
    genvar g;
    generate for (g=0;g<12;g=g+1) begin : g_payload
        assign p[g] = payload_i[g*8 +: 8];
    end endgenerate

    function automatic [10:0] cache_index(input logic array_sel,
                                            input logic [1:0] category,
                                            input logic [4:0] slot,
                                            input logic [7:0] record_id);
        logic [10:0] offset;
        begin
            case (category)
                2'd0: offset = {6'b0,slot} * 16 + {7'b0,record_id[3:0]};
                2'd1: offset = 11'd128 + {6'b0,slot} * 16 + {7'b0,record_id[3:0]};
                2'd2: offset = 11'd640 + {6'b0,slot};
                default: offset = 11'd672 + {3'b0,record_id};
            endcase
            cache_index = (array_sel ? 11'd801 : 11'd0) + offset;
        end
    endfunction

    always_comb begin
        if (cmd_q == 8'hF3) begin
            if (category_q == 2'd1) begin
                active_slot = iteration_q[8:4];
                active_record = {4'b0,iteration_q[3:0]};
            end else if (category_q == 2'd2) begin
                active_slot = iteration_q[4:0];
                active_record = 0;
            end else if (category_q == 2'd3) begin
                active_slot = 0;
                active_record = iteration_q[7:0];
            end else begin
                active_slot = slot_q;
                active_record = {4'b0,iteration_q[3:0]};
            end
        end else if (cmd_q == 8'hF5) begin
            active_slot = iteration_q[4:0];
            active_record = 0;
        end else begin
            active_slot = slot_q;
            active_record = record_q;
        end
        active_cache_index = cache_index(array_q,category_q,active_slot,active_record);
        device_operation_o = cmd_q == 8'hF2 ? 2'd1 :
                             cmd_q == 8'hF3 ? 2'd0 : 2'd2;
        // High bits follow the BJN110 allocation; records occupy 16-byte slots.
        device_address_o = {array_q,category_q,active_slot,16'b0} +
                           {12'b0,active_record,4'b0};
        device_length_o = cmd_q == 8'hF1 || cmd_q == 8'hF5 ? 5'd0 : 5'd16;
        checksum = 0;
        read_checksum = 0;
        for (integer i=0;i<12;i=i+1) begin
            checksum = checksum + payload_q[i*8 +: 8];
            read_checksum = read_checksum + device_read_data_i[i*8 +: 8];
        end
        device_write_data_o = {8'h5A,8'hA5,~checksum,checksum,payload_q};
        record_blank = device_read_data_i == {128{1'b1}};
        record_valid = device_read_data_i[127:112] == 16'h5AA5 &&
                       device_read_data_i[103:96] == read_checksum &&
                       device_read_data_i[111:104] == ~device_read_data_i[103:96];
        sample_digest = 0;
        for (integer j=0;j<16;j=j+1)
            sample_digest[(j%3)*8 +: 8] =
                sample_digest[(j%3)*8 +: 8] ^ cache_word_q[j*8 +: 8];
    end

    assign device_request_o = state_q == ISSUE && !device_busy_i;
    assign busy_o = state_q != IDLE;
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            state_q <= CLEAR;
            cmd_q <= 0;
            array_q <= 0;
            category_q <= 0;
            slot_q <= 0;
            record_q <= 0;
            payload_q <= 0;
            iteration_q <= 0;
            iteration_limit_q <= 0;
            clear_base_q <= 0;
            clear_count_q <= 11'd1602;
            clear_index_q <= 0;
            done_o <= 0;
            error_o <= 0;
            loaded_count_o <= 0;
            cache_sample_o <= 0;
            last_valid_index_q <= 0;
            cache_word_q <= 0;
        end else begin
            done_o <= 0;
            case (state_q)
                IDLE: if (start_i) begin
                    cmd_q <= command_i;
                    array_q <= array_i;
                    payload_q <= payload_i;
                    iteration_q <= 0;
                    loaded_count_o <= 0;
                    cache_sample_o <= 0;
                    error_o <= 0;
                    if (p[0] <= 7) begin
                        category_q <= 0;
                        slot_q <= p[0][4:0];
                        iteration_limit_q <= 16;
                    end else if (p[0] == 8'h11) begin
                        category_q <= 1;
                        slot_q <= p[2][4:0];
                        iteration_limit_q <= 512;
                    end else if (p[0] == 8'h12) begin
                        category_q <= 2;
                        slot_q <= p[2][4:0];
                        iteration_limit_q <= 32;
                    end else begin
                        category_q <= 3;
                        slot_q <= 0;
                        iteration_limit_q <= 129;
                    end
                    record_q <= p[0] == 8'h13 ? p[1] : {4'b0,p[3][1:0],p[4][1:0]};
                    if (command_i == 8'hF5) begin
                        category_q <= 0;
                        iteration_limit_q <= 128;
                        state_q <= ISSUE;
                    end else if ((p[0] != 8'h13 && p[0] > 7 &&
                                  (p[1] != 0 || p[2] > 31)) ||
                                 (p[0] == 8'h13 && p[1] > 128) ||
                                 ((p[0] <= 7 || p[0] == 8'h11) &&
                                  (p[3] > 3 || p[4] > 3))) begin
                        error_o <= 1;
                        done_o <= 1;
                    end else state_q <= ISSUE;
                end
                ISSUE: if (!device_busy_i) state_q <= WAIT_BUSY;
                WAIT_BUSY: if (device_busy_i) state_q <= WAIT_DONE;
                WAIT_DONE: if (device_done_i) state_q <= EVALUATE;
                EVALUATE: if (device_error_i) begin
                    error_o <= 1;
                    done_o <= 1;
                    state_q <= IDLE;
                end else if (cmd_q == 8'hF2) begin
                    cache_data[active_cache_index] <= device_write_data_o;
                    cache_valid[active_cache_index] <= 1;
                    done_o <= 1;
                    state_q <= IDLE;
                end else if (cmd_q == 8'hF3) begin
                    if (!record_blank && !record_valid) begin
                        error_o <= 1;
                        done_o <= 1;
                        state_q <= IDLE;
                    end else begin
                        cache_data[active_cache_index] <= device_read_data_i;
                        cache_valid[active_cache_index] <= !record_blank;
                        if (!record_blank) begin
                            loaded_count_o <= loaded_count_o + 1'b1;
                            last_valid_index_q <= active_cache_index;
                        end
                        if (iteration_q == iteration_limit_q - 1) begin
                            state_q <= SAMPLE;
                        end else begin
                            iteration_q <= iteration_q + 1'b1;
                            state_q <= ISSUE;
                        end
                    end
                end else if (cmd_q == 8'hF5 && iteration_q != 127) begin
                    iteration_q <= iteration_q + 1'b1;
                    if (active_slot == 31) category_q <= category_q + 1'b1;
                    state_q <= ISSUE;
                end else begin
                    clear_index_q <= 0;
                    if (cmd_q == 8'hF5) begin
                        clear_base_q <= array_q ? 11'd801 : 11'd0;
                        clear_count_q <= 11'd801;
                    end else begin
                        clear_base_q <= cache_index(array_q,category_q,slot_q,0);
                        clear_count_q <= category_q == 2'd3 ? 11'd129 :
                                         category_q == 2'd2 ? 11'd1 : 11'd16;
                    end
                    state_q <= CLEAR;
                end
                CLEAR: begin
                    cache_valid[clear_base_q + clear_index_q] <= 0;
                    if (clear_index_q == clear_count_q - 1) begin
                        done_o <= 1;
                        state_q <= IDLE;
                    end else clear_index_q <= clear_index_q + 1'b1;
                end
                SAMPLE: begin
                    if (loaded_count_o != 0)
                        cache_word_q <= cache_data[last_valid_index_q];
                    state_q <= DIGEST;
                end
                DIGEST: begin
                    if (loaded_count_o != 0) cache_sample_o <= sample_digest;
                    done_o <= 1;
                    state_q <= IDLE;
                end
                default: state_q <= IDLE;
            endcase
        end
    end
endmodule
