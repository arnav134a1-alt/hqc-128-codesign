`timescale 1ns / 1ps

module sampler_adapter #(
    parameter W = 66,
    parameter ADDR_W_S = 7,
    parameter SP_DATA_W = 15
)(
    input  wire                   clk,
    input  wire                   rst,
    input  wire                   start,
    
    // Seed input for sampler
    input  wire [31:0]            seed_data,
    input  wire [3:0]             seed_addr,
    input  wire                   seed_we,
    
    // Interface to target SPARSE_MEM
    output reg                    sp_we,
    output reg  [ADDR_W_S-1:0]    sp_waddr,
    output reg  [SP_DATA_W-1:0]   sp_wdata,
    
    // Status
    output reg                    done
);

    reg  fw_start;
    wire fw_done;
    wire fw_valid;
    wire [14:0] fw_loc;
    reg  fw_rd;
    reg  [6:0] fw_rd_addr;

    // SHAKE256 interconnect signals
    wire sh_seed_val;
    wire sh_seed_rdy;
    wire [31:0] sh_din;
    wire sh_capture_rdy;
    wire [31:0] sh_dout;
    wire sh_force_done;
    wire sh_dout_val;

    // SHAKE256 Core
    keccak_top SHAKE_INST (
        .clk(clk),
        .rst(rst),
        .seed_in(sh_din),
        .seed_in_valid(sh_seed_val),
        .seed_in_ready(sh_seed_rdy),
        .dout(sh_dout),
        .dout_valid(sh_dout_val),
        .dout_capture_ready(sh_capture_rdy),
        .force_done(sh_force_done)
    );

    // Fixed-Weight Sampler Core
    fixed_weight_cww #(
        .parameter_set("hqc128"),
        .WEIGHT(66)
    ) SAMPLER_INST (
        .clk(clk),
        .rst(rst),
        .start(fw_start),
        .sk_seed(seed_data),
        .sk_seed_addr(seed_addr),
        .sk_seed_wen(seed_we),
        .request_another_vector(2'b00),
        .done(fw_done),
        .valid_vector(fw_valid),
        .error_loc(fw_loc),
        .rd_error_loc(fw_rd),
        .rd_addr_error_loc(fw_rd_addr),
        .seed_valid_internal(sh_seed_val),
        .seed_ready_internal(sh_seed_rdy),
        .din_shake(sh_din),
        .shake_out_capture_ready(sh_capture_rdy),
        .dout_shake_scrambled(sh_dout),
        .force_done_shake(sh_force_done),
        .dout_valid_sh_internal(sh_dout_val)
    );

    localparam S_IDLE       = 3'd0;
    localparam S_START_FW   = 3'd1;
    localparam S_WAIT_FW    = 3'd2;
    localparam S_READ_LOC   = 3'd3;
    localparam S_WRITE_MEM  = 3'd4;
    localparam S_DONE       = 3'd5;

    reg [2:0] state;

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            fw_start <= 1'b0;
            fw_rd <= 1'b0;
            fw_rd_addr <= 0;
            sp_we <= 1'b0;
            sp_waddr <= 0;
            sp_wdata <= 0;
            done <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    done <= 1'b0;
                    sp_we <= 1'b0;
                    if (start) state <= S_START_FW;
                end

                S_START_FW: begin
                    fw_start <= 1'b1;
                    state <= S_WAIT_FW;
                end

                S_WAIT_FW: begin
                    fw_start <= 1'b0;
                    if (fw_done) begin
                        fw_rd_addr <= 0;
                        fw_rd <= 1'b1;
                        state <= S_READ_LOC;
                    end
                end

                S_READ_LOC: begin
                    // Wait 1 cycle for internal vector RAM read
                    state <= S_WRITE_MEM;
                end

                S_WRITE_MEM: begin
                    sp_we <= 1'b1;
                    sp_waddr <= fw_rd_addr;
                    sp_wdata <= fw_loc;

                    if (fw_rd_addr == W - 1) begin
                        fw_rd <= 1'b0;
                        state <= S_DONE;
                    end else begin
                        fw_rd_addr <= fw_rd_addr + 1;
                        state <= S_READ_LOC;
                    end
                end

                S_DONE: begin
                    sp_we <= 1'b0;
                    done <= 1'b1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
