`timescale 1ns / 1ps

module decoder_adapter #(
    parameter DW = 64,
    parameter DEPTH = 277,
    parameter ADDR_W_D = 9,
    parameter K_BYTES = 16
)(
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  start,
    
    // Interface to N BRAM (reads from BRAM U)
    output reg  [ADDR_W_D-1:0]   n_raddr,
    input  wire [DW-1:0]         n_dout,
    
    // Output recovered message
    output wire [8*K_BYTES-1:0]  msg_out,
    output wire                  msg_valid,
    output reg                   done
);

    wire dec_busy;
    wire [127:0] ram_din;
    wire ram_rd;
    wire [7:0] ram_addr;
    wire [127:0] dec_dout;
    wire dec_valid;
    reg  dec_start;

    // Active-low reset for hqc_decod_top
    wire rst_n = ~rst;

    hqc_decod_top #(
        .PARAM_SECURITY(128)
    ) DECODER (
        .clk_i(clk),
        .rst_ni(rst_n),
        .start_i(dec_start),
        .busy_o(dec_busy),
        .ram_din_i(ram_din),
        .ram_din_rd_o(ram_rd),
        .ram_din_addr_o(ram_addr),
        .dout_o(dec_dout),
        .dout_valid_o(dec_valid)
    );

    // Holding registers for message output
    reg [8*K_BYTES-1:0] msg_out_reg;
    reg                 msg_valid_reg;

    assign msg_out   = msg_out_reg;
    assign msg_valid = msg_valid_reg;

    // -------------------------------------------------------------------------
    // Prefetch Buffer: holds 3 128-bit words (6 64-bit BRAM words) per codeword
    // -------------------------------------------------------------------------
    reg [127:0] prefetch_buf [0:2];
    reg [63:0]  buf_lo;
    reg [1:0]   word_sel;
    reg [1:0]   cnt_word;
    reg [5:0]   cdw_idx;        // 0 to 45 (46 codewords)
    reg [2:0]   step;           // 0 to 7 prefetch cycle counter
    reg         first_cdw;

    assign ram_din = prefetch_buf[word_sel];

    localparam S_IDLE       = 3'd0;
    localparam S_PREFETCH   = 3'd1;
    localparam S_WAIT_REQ   = 3'd2;
    localparam S_WAIT_DONE  = 3'd3;

    reg [2:0] state;

    wire [8:0] base_addr = (cdw_idx << 2) + (cdw_idx << 1); // cdw_idx * 6

    always @(posedge clk) begin
        if (rst) begin
            state         <= S_IDLE;
            dec_start     <= 1'b0;
            n_raddr       <= 9'd0;
            buf_lo        <= 64'd0;
            word_sel      <= 2'd0;
            cnt_word      <= 2'd0;
            cdw_idx       <= 6'd0;
            step          <= 3'd0;
            first_cdw     <= 1'b1;
            done          <= 1'b0;
            msg_out_reg   <= {8*K_BYTES{1'b0}};
            msg_valid_reg <= 1'b0;
            prefetch_buf[0] <= 128'd0;
            prefetch_buf[1] <= 128'd0;
            prefetch_buf[2] <= 128'd0;
        end else begin
            // Hold dec_start as a 1-cycle strobe
            if (dec_start) dec_start <= 1'b0;

            // Global capture of decoded output whenever DECODER signals completion
            if (dec_valid) begin
                msg_out_reg   <= dec_dout;
                msg_valid_reg <= 1'b1;
            end

            case (state)
                S_IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        msg_valid_reg <= 1'b0;
                        cdw_idx       <= 6'd0;
                        cnt_word      <= 2'd0;
                        step          <= 3'd0;
                        first_cdw     <= 1'b1;
                        state         <= S_PREFETCH;
                    end
                end

                // -------------------------------------------------------------
                // PREFETCH: Fetch 6 64-bit BRAM words into 3 128-bit buffers
                // Latency: 1 cycle BRAM read latency
                // -------------------------------------------------------------
                S_PREFETCH: begin
                    case (step)
                        3'd0: begin
                            n_raddr <= base_addr + 9'd0;
                            step    <= 3'd1;
                        end
                        3'd1: begin
                            n_raddr <= base_addr + 9'd1;
                            step    <= 3'd2;
                        end
                        3'd2: begin
                            buf_lo  <= n_dout; // word 0 lo
                            n_raddr <= base_addr + 9'd2;
                            step    <= 3'd3;
                        end
                        3'd3: begin
                            prefetch_buf[0] <= {n_dout, buf_lo}; // word 0 complete
                            n_raddr <= base_addr + 9'd3;
                            step    <= 3'd4;
                        end
                        3'd4: begin
                            buf_lo  <= n_dout; // word 1 lo
                            n_raddr <= base_addr + 9'd4;
                            step    <= 3'd5;
                        end
                        3'd5: begin
                            prefetch_buf[1] <= {n_dout, buf_lo}; // word 1 complete
                            n_raddr <= base_addr + 9'd5;
                            step    <= 3'd6;
                        end
                        3'd6: begin
                            buf_lo  <= n_dout; // word 2 lo
                            step    <= 3'd7;
                        end
                        3'd7: begin
                            prefetch_buf[2] <= {n_dout, buf_lo}; // word 2 complete
                            step    <= 3'd0;
                            if (first_cdw) begin
                                dec_start <= 1'b1;
                                first_cdw <= 1'b0;
                            end
                            state <= S_WAIT_REQ;
                        end
                    endcase
                end

                // -------------------------------------------------------------
                // WAIT_REQ: Serve 3 words to DECODER with exact 1-cycle latency
                // -------------------------------------------------------------
                S_WAIT_REQ: begin
                    if (dec_valid) begin
                        done  <= 1'b1;
                        state <= S_IDLE;
                    end else if (ram_rd) begin
                        word_sel <= cnt_word;
                        if (cnt_word == 2'd2) begin
                            cnt_word <= 2'd0;
                            if (cdw_idx < 6'd45) begin
                                cdw_idx <= cdw_idx + 1'b1;
                                step    <= 3'd0;
                                state   <= S_PREFETCH;
                            end else begin
                                state   <= S_WAIT_DONE;
                            end
                        end else begin
                            cnt_word <= cnt_word + 1'b1;
                        end
                    end
                end

                // -------------------------------------------------------------
                // WAIT_DONE: All 46 codewords served; waiting for final RS done
                // -------------------------------------------------------------
                S_WAIT_DONE: begin
                    if (dec_valid) begin
                        done  <= 1'b1;
                        state <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
