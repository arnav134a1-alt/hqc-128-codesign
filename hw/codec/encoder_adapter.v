`timescale 1ns / 1ps

module encoder_adapter #(
    parameter DW = 64,
    parameter DEPTH = 277,
    parameter ADDR_W_D = 9,
    parameter K_BYTES = 16,
    parameter N1_BYTES = 46,
    parameter MULTIPLICITY = 3
)(
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  start,
    input  wire [8*K_BYTES-1:0]  msg_in,
    
    // Interface to MG BRAM
    output reg                   mg_we,
    output reg  [ADDR_W_D-1:0]   mg_waddr,
    output reg  [DW-1:0]         mg_wdata,
    
    output reg                   done
);
    localparam LOG_N1 = $clog2(N1_BYTES);
    
    reg  enc_start;
    wire enc_done;
    reg  cdw_en;
    reg  [LOG_N1-1:0] cdw_addr;
    wire [127:0] cdw_data;

    concat_code #(
        .parameter_set("hqc128")
    ) CONCAT_ENC (
        .clk(clk),
        .rst(rst),
        .start(enc_start),
        .msg_in(msg_in),
        .cdw_out_en(cdw_en),
        .cdw_out_addr(cdw_addr),
        .cdw_out(cdw_data),
        .done(enc_done)
    );

    localparam S_IDLE       = 3'd0;
    localparam S_START_ENC  = 3'd1;
    localparam S_WAIT_ENC   = 3'd2;
    localparam S_READ_CDW   = 3'd3;
    localparam S_WRITE_LO   = 3'd4;
    localparam S_WRITE_HI   = 3'd5;
    localparam S_WRITE_TAIL = 3'd6;
    localparam S_DONE       = 3'd7;

    reg [2:0] state;
    reg [5:0] block_idx;     // 0 to 45
    reg [1:0] copy_idx;      // 0 to 2
    reg [7:0] word_idx_128;  // 0 to 137

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            enc_start <= 1'b0;
            cdw_en <= 1'b0;
            cdw_addr <= 0;
            mg_we <= 1'b0;
            mg_waddr <= 0;
            mg_wdata <= 0;
            done <= 1'b0;
            block_idx <= 0;
            copy_idx <= 0;
            word_idx_128 <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    done <= 1'b0;
                    mg_we <= 1'b0;
                    if (start) state <= S_START_ENC;
                end

                S_START_ENC: begin
                    enc_start <= 1'b1;
                    state <= S_WAIT_ENC;
                end

                S_WAIT_ENC: begin
                    enc_start <= 1'b0;
                    if (enc_done) begin
                        block_idx <= 0;
                        copy_idx <= 0;
                        word_idx_128 <= 0;
                        cdw_en <= 1'b1;
                        cdw_addr <= 0;
                        state <= S_READ_CDW;
                    end
                end

                S_READ_CDW: begin
                    // Wait 1 cycle for BRAM read inside reed_muller_encode
                    state <= S_WRITE_LO;
                end

                S_WRITE_LO: begin
                    // Write lower 64 bits to MG BRAM
                    mg_we <= 1'b1;
                    mg_waddr <= {word_idx_128, 1'b0};
                    mg_wdata <= cdw_data[63:0];
                    state <= S_WRITE_HI;
                end

                S_WRITE_HI: begin
                    // Write upper 64 bits to MG BRAM
                    mg_we <= 1'b1;
                    mg_waddr <= {word_idx_128, 1'b1};
                    mg_wdata <= cdw_data[127:64];

                    // Advance indices
                    word_idx_128 <= word_idx_128 + 1;
                    if (copy_idx == MULTIPLICITY - 1) begin
                        copy_idx <= 0;
                        if (block_idx == N1_BYTES - 1) begin
                            state <= S_WRITE_TAIL;
                        end else begin
                            block_idx <= block_idx + 1;
                            cdw_addr <= block_idx + 1;
                            state <= S_READ_CDW;
                        end
                    end else begin
                        copy_idx <= copy_idx + 1;
                        // Keep same cdw_addr to repeat block
                        state <= S_READ_CDW;
                    end
                end

                S_WRITE_TAIL: begin
                    // Write final word 276 with 0
                    mg_we <= 1'b1;
                    mg_waddr <= 9'd276;
                    mg_wdata <= 64'd0;
                    cdw_en <= 1'b0;
                    state <= S_DONE;
                end

                S_DONE: begin
                    mg_we <= 1'b0;
                    done <= 1'b1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
