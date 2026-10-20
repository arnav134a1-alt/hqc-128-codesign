`timescale 1ns / 1ps

module Encryption_datapath_shared #(
    parameter DW = 64,
    parameter DEPTH = 277,
    parameter W = 66,
    parameter ADDR_W_S = 7,
    parameter SP_DATA_W = 15,
    parameter ADDR_W_D = 9
)(
    input clk,
    input rst,
    input enc_start,
    
    input [DW-1:0] data_in_h,
    input [DW-1:0] data_in_s,
    input [DW-1:0] data_in_MG,
    input [SP_DATA_W-1:0] data_in_r1,
    input [SP_DATA_W-1:0] data_in_r2,
    input [SP_DATA_W-1:0] data_in_e,
    
    output reg [ADDR_W_D-1:0] addr_out_h,
    output reg [ADDR_W_D-1:0] addr_out_s,
    output reg [ADDR_W_D-1:0] addr_out_MG,
    
    output reg [ADDR_W_S-1:0] addr_out_r1,
    output reg [ADDR_W_S-1:0] addr_out_r2,
    output reg [ADDR_W_S-1:0] addr_out_e,
    
    output reg [DW-1:0] U_out,
    output reg [DW-1:0] V_out,
    output reg [ADDR_W_D-1:0] U_addr,
    output reg [ADDR_W_D-1:0] V_addr, 
    output reg U_we,
    output reg V_we,
    
    output reg enc_done,

    // External Shared Accumulator Ports
    output reg                  T1_we,
    output reg  [ADDR_W_D-1:0]  T1_waddr,
    output reg  [DW-1:0]        T1_din,
    output reg  [ADDR_W_D-1:0]  T1_raddr,
    input  wire [DW-1:0]        T1_dout
);

    // Sub-module Interconnects
    reg start_shift;
    wire [ADDR_W_S-1:0] sp_addr;
    reg  [SP_DATA_W-1:0] sp_pos;
    wire [ADDR_W_D-1:0] dense_raddr;
    reg  [DW-1:0] dense_rdata;
    wire acc_we;
    wire [ADDR_W_D-1:0] acc_waddr;
    wire [DW-1:0] acc_wdata;
    wire [ADDR_W_D-1:0] acc_raddr;
    reg  [DW-1:0] acc_rdata;
    wire MUL0_done;
    
    shift_acc #(.W(75)) MUL0(
        .clk(clk), .rst(rst), .start(start_shift),
        .sp_addr(sp_addr), .sp_pos(sp_pos),
        .dense_raddr(dense_raddr), .dense_rdata(dense_rdata),
        .acc_we(acc_we), .acc_waddr(acc_waddr), .acc_wdata(acc_wdata),
        .acc_raddr(acc_raddr), .acc_rdata(acc_rdata),
        .done(MUL0_done)
    );
    
    reg start_adds0;
    wire adds0_done;
    wire [ADDR_W_D-1:0] adds0_addr_A;
    wire [ADDR_W_S-1:0] adds0_addr_B;
    reg  [DW-1:0] adds0_data_A;
    reg  [SP_DATA_W-1:0] adds0_data_B;
    wire [DW-1:0] adds0_data_C;
    wire [ADDR_W_D-1:0] adds0_addr_C;
    wire adds0_we_C;
    
    dense_add_sparse #(.W(75)) ADDS0 (
        .clk(clk), .rst(rst), .start(start_adds0), .done(adds0_done),
        .addr_out_A(adds0_addr_A), .addr_out_B(adds0_addr_B),
        .data_in_A(adds0_data_A), .data_in_B(adds0_data_B),
        .data_out_C(adds0_data_C), .addr_out_C(adds0_addr_C),
        .we_C(adds0_we_C)
    );
    
    reg start_add0;
    wire add0_done;
    wire [ADDR_W_D-1:0] add0_addr_A;
    wire [ADDR_W_D-1:0] add0_addr_B;
    reg  [DW-1:0] add0_data_A;
    reg  [DW-1:0] add0_data_B;
    wire [ADDR_W_D-1:0] add0_addr_C;
    wire [DW-1:0] add0_data_C;
    wire add0_we_C;
    
    dense_add_dense ADD0 (
        .clk(clk), .rst(rst), .start(start_add0), .done(add0_done),
        .addr_out_A(add0_addr_A), .addr_out_B(add0_addr_B),
        .data_in_A(add0_data_A), .data_in_B(add0_data_B),
        .data_out_C(add0_data_C), .addr_out_C(add0_addr_C),
        .we_C(add0_we_C)
    );
    
    localparam S_IDLE       = 4'd0;
    localparam S_CLEAR_ACC1 = 4'd1;
    localparam S_MUL_HR2_START = 4'd11;
    localparam S_MUL_HR2    = 4'd2;
    localparam S_ADD_U      = 4'd3;
    localparam S_COPY_U     = 4'd4;
    localparam S_CLEAR_ACC2 = 4'd5;
    localparam S_MUL_SR2_START = 4'd12;
    localparam S_MUL_SR2    = 4'd6; 
    localparam S_ADD_MG     = 4'd7;
    localparam S_ADD_E      = 4'd8;
    localparam S_COPY_V     = 4'd9;
    localparam S_DONE       = 4'd10;
    
    reg [3:0] state;
    reg [ADDR_W_D-1:0] clear_addr;
    reg [ADDR_W_D-1:0] copy_addr;
    reg [ADDR_W_D-1:0] copy_addr_d;
    reg                copy_valid;
    
    always@(posedge clk) begin
        if(rst) begin
            state <= S_IDLE;
            enc_done <= 1'b0;
            start_shift <= 1'b0;
            start_adds0 <= 1'b0;
            start_add0 <= 1'b0;
            clear_addr <= 0;
            copy_addr <= 0;
            copy_addr_d <= 0;
            copy_valid <= 1'b0;
        end
        else begin
            case(state)
                S_IDLE: begin 
                    enc_done <= 1'b0;
                    clear_addr <= 0;
                    copy_addr <= 0;
                    copy_addr_d <= 0;
                    copy_valid <= 1'b0;
                    if(enc_start) state <= S_CLEAR_ACC1;
                end
                
                S_CLEAR_ACC1: begin
                    clear_addr <= clear_addr + 1;
                    if (clear_addr == DEPTH-1) state <= S_MUL_HR2_START;
                end

                S_MUL_HR2_START: begin
                    start_shift <= 1'b1;
                    state <= S_MUL_HR2;
                end

                S_MUL_HR2: begin
                    start_shift <= 1'b0;
                    if (MUL0_done) state <= S_ADD_U;
                end
                
                S_ADD_U: begin
                    if(!start_adds0 && !adds0_done) begin
                        start_adds0 <= 1'b1;
                    end else if(adds0_done) begin
                        start_adds0 <= 1'b0;
                        copy_addr <= 0;
                        copy_addr_d <= 0;
                        copy_valid <= 1'b0;
                        state <= S_COPY_U;
                    end
                end

                S_COPY_U: begin
                    if (copy_addr < DEPTH) begin
                        copy_addr   <= copy_addr + 1;
                        copy_addr_d <= copy_addr;
                        copy_valid  <= 1'b1;
                    end else begin
                        copy_valid <= 1'b0;
                        clear_addr <= 0;
                        state <= S_CLEAR_ACC2;
                    end
                end
                
                S_CLEAR_ACC2: begin
                    clear_addr <= clear_addr + 1;
                    if (clear_addr == DEPTH-1) state <= S_MUL_SR2_START;
                end

                S_MUL_SR2_START: begin
                    start_shift <= 1'b1;
                    state <= S_MUL_SR2;
                end

                S_MUL_SR2: begin
                    start_shift <= 1'b0;
                    if (MUL0_done) state <= S_ADD_MG;
                end
                
                S_ADD_MG: begin
                    if(!start_add0 && !add0_done) begin
                        start_add0 <= 1'b1;
                    end else if(add0_done) begin
                        start_add0 <= 1'b0;
                        state <= S_ADD_E;
                    end
                end
                
                S_ADD_E: begin
                    if(!start_adds0 && !adds0_done) begin
                        start_adds0 <= 1'b1;
                    end else if(adds0_done) begin
                        start_adds0 <= 1'b0;
                        copy_addr <= 0;
                        copy_addr_d <= 0;
                        copy_valid <= 1'b0;
                        state <= S_COPY_V;
                    end
                end

                S_COPY_V: begin
                    if (copy_addr < DEPTH) begin
                        copy_addr   <= copy_addr + 1;
                        copy_addr_d <= copy_addr;
                        copy_valid  <= 1'b1;
                    end else begin
                        copy_valid <= 1'b0;
                        state <= S_DONE;
                    end
                end
                
                S_DONE: begin
                    enc_done <= 1'b1;
                    state <= S_IDLE;
                end
            endcase
        end
    end
    
    // MUXing Logic
    always@(*) begin
        addr_out_h = 0; addr_out_s = 0; addr_out_MG = 0;
        addr_out_r1 = 0; addr_out_r2 = 0; addr_out_e = 0;
        
        dense_rdata = 0; sp_pos = 0; acc_rdata = 0;
        adds0_data_A = 0; adds0_data_B = 0;
        add0_data_A = 0; add0_data_B = 0;
        
        U_out = 0; U_addr = 0; U_we = 1'b0;
        V_out = 0; V_addr = 0; V_we = 1'b0;
        
        T1_we = 1'b0; T1_waddr = 0; T1_din = 0; T1_raddr = 0;
        
        case(state)
            S_CLEAR_ACC1: begin
                T1_we = 1'b1;
                T1_waddr = clear_addr;
                T1_din = 0;
            end
            
            S_MUL_HR2: begin
                addr_out_h = dense_raddr;
                addr_out_r2 = sp_addr;
                dense_rdata = data_in_h;
                sp_pos = data_in_r2;
                
                // Route shift_acc to T1
                T1_raddr = acc_raddr;
                acc_rdata = T1_dout;
                T1_waddr = acc_waddr;
                T1_din = acc_wdata;
                T1_we = acc_we;
            end
            
            S_ADD_U: begin
                // In-place accumulation into T1: T1 = T1 + r1
                addr_out_r1 = adds0_addr_B;
                adds0_data_B = data_in_r1;
                
                T1_raddr = adds0_addr_A;
                adds0_data_A = T1_dout;
                
                T1_waddr = adds0_addr_C;
                T1_din   = adds0_data_C;
                T1_we    = adds0_we_C;
            end

            S_COPY_U: begin
                // Copy full 277-word u polynomial from T1 into BRAM U
                T1_raddr = copy_addr;
                U_out    = T1_dout;
                U_addr   = copy_addr_d;
                U_we     = copy_valid;
            end
            
            S_CLEAR_ACC2: begin
                T1_we = 1'b1;
                T1_waddr = clear_addr;
                T1_din = 0;
            end
            
            S_MUL_SR2: begin
                addr_out_s = dense_raddr;
                addr_out_r2 = sp_addr;
                dense_rdata = data_in_s;
                sp_pos = data_in_r2;
                
                // Route shift_acc to T1 (Reusing T1!)
                T1_raddr = acc_raddr;
                acc_rdata = T1_dout;
                T1_waddr = acc_waddr;
                T1_din = acc_wdata;
                T1_we = acc_we;
            end
            
            S_ADD_MG: begin
                // In-place accumulation: T1 = T1 + MG
                addr_out_MG = add0_addr_B;
                add0_data_B = data_in_MG;
                
                T1_raddr = add0_addr_A;
                add0_data_A = T1_dout;
                
                T1_waddr = add0_addr_C;
                T1_din   = add0_data_C;
                T1_we    = add0_we_C;
            end
            
            S_ADD_E: begin
                // In-place accumulation into T1: T1 = T1 + e
                addr_out_e = adds0_addr_B;
                adds0_data_B = data_in_e;
                
                T1_raddr = adds0_addr_A;
                adds0_data_A = T1_dout;
                
                T1_waddr = adds0_addr_C;
                T1_din   = adds0_data_C;
                T1_we    = adds0_we_C;
            end

            S_COPY_V: begin
                // Copy full 277-word v polynomial from T1 into BRAM V
                T1_raddr = copy_addr;
                V_out    = (copy_addr_d == DEPTH-1) ? 64'd0 : T1_dout;
                V_addr   = copy_addr_d;
                V_we     = copy_valid;
            end
        endcase
    end
endmodule
