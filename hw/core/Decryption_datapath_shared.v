`timescale 1ns / 1ps

module Decryption_datapath_shared #(
    parameter DW = 64,
    parameter DEPTH = 277,
    parameter W = 66,
    parameter ADDR_W_S = 7,
    parameter SP_DATA_W = 15,
    parameter ADDR_W_D = 9
)(
    input clk,
    input rst,
    input dec_start,
    input [DW-1:0] data_in_U,
    input [DW-1:0] data_in_V,
    input [SP_DATA_W-1:0] data_in_y,
    
    output reg [ADDR_W_D-1:0] addr_out_U,
    output reg [ADDR_W_D-1:0] addr_out_V,
    output reg [ADDR_W_S-1:0] addr_out_y,
    
    output reg [DW-1:0] N_out,
    output reg [ADDR_W_D-1:0] N_addr,
    output reg N_we,
    
    output reg dec_done,

    // External Shared Accumulator T1 Ports
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
    
    shift_acc #(.W(66)) MUL0(
        .clk(clk), .rst(rst), .start(start_shift),
        .sp_addr(sp_addr), .sp_pos(sp_pos),
        .dense_raddr(dense_raddr), .dense_rdata(dense_rdata),
        .acc_we(acc_we), .acc_waddr(acc_waddr), .acc_wdata(acc_wdata),
        .acc_raddr(acc_raddr), .acc_rdata(acc_rdata),
        .done(MUL0_done)
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
    
    localparam S_IDLE       = 3'd0;
    localparam S_CLEAR_ACC  = 3'd1;
    localparam S_MUL_UY_START = 3'd6;
    localparam S_MUL_UY     = 3'd2;
    localparam S_ADD_V      = 3'd3;
    localparam S_DONE       = 3'd4;
    
    reg [2:0] state;
    reg [ADDR_W_D-1:0] clear_addr;
    
    always@(posedge clk) begin
        if(rst) begin
            dec_done <= 0;
            state <= S_IDLE;
            start_add0 <= 0;
            start_shift <= 0;
            clear_addr <= 0;
        end
        else begin
            case(state)
                S_IDLE: begin
                    dec_done <= 0;
                    clear_addr <= 0;
                    if(dec_start) state <= S_CLEAR_ACC;
                end
                
                S_CLEAR_ACC: begin
                    clear_addr <= clear_addr + 1;
                    if (clear_addr == DEPTH-1) state <= S_MUL_UY_START;
                end

                S_MUL_UY_START: begin
                    start_shift <= 1'b1;
                    state <= S_MUL_UY;
                end

                S_MUL_UY: begin
                    start_shift <= 1'b0;
                    if (MUL0_done) state <= S_ADD_V;
                end
                
                S_ADD_V: begin
                     if(!start_add0 && !add0_done) begin
                         start_add0 <= 1'b1;
                     end else if(add0_done) begin
                         start_add0 <= 1'b0;
                         state <= S_DONE;
                     end
                end
                
                S_DONE: begin
                    dec_done <= 1'b1;
                    state <= S_IDLE;
                end
            endcase
        end
    end
    
    // MUXing Logic
    always@(*) begin
        addr_out_U = 0; addr_out_y = 0; addr_out_V = 0;
        dense_rdata = 0; sp_pos = 0; acc_rdata = 0;
        add0_data_B = 0; add0_data_A = 0;
        
        N_out = 0; N_addr = 0; N_we = 0;
        
        T1_we = 1'b0; T1_waddr = 0; T1_din = 0; T1_raddr = 0;
        
        case(state)
            S_CLEAR_ACC: begin
                T1_we = 1'b1;
                T1_waddr = clear_addr;
                T1_din = 0;
            end
            
            S_MUL_UY: begin
                addr_out_U = dense_raddr;     
                addr_out_y = sp_addr;        
                dense_rdata = data_in_U;      
                sp_pos = data_in_y;          
                
                T1_raddr = acc_raddr;
                acc_rdata = T1_dout;
                T1_waddr = acc_waddr;
                T1_din = acc_wdata;
                T1_we = acc_we;
            end
            
            S_ADD_V: begin
                addr_out_V = add0_addr_B;
                add0_data_B = data_in_V;
                
                T1_raddr = add0_addr_A;
                add0_data_A = T1_dout;
                
                N_out = add0_data_C;
                N_addr = add0_addr_C;
                N_we = add0_we_C;
             end
        endcase
    end
endmodule
