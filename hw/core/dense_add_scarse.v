`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 15.09.2026 17:32:05
// Design Name: 
// Module Name: dense_add_scarse
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

          
      
module dense_add_sparse#(
    parameter DW = 64,
    parameter W = 66,
    parameter ADDR_W_S = 7,
    parameter SP_DATA_W = 15,
    parameter depth = 277,
    parameter ADDR_W_D = 9
    )(
    input wire clk,
    input wire rst,
    input wire start,
    output reg done,
    output reg [ADDR_W_D-1:0] addr_out_A,
    output reg [ADDR_W_S-1:0] addr_out_B,
    input wire [DW-1:0] data_in_A,
    input wire [SP_DATA_W-1:0] data_in_B,
    output reg [DW-1:0] data_out_C,
    output reg [ADDR_W_D-1:0] addr_out_C,
    output reg we_C
    );
    reg start_prev;
    reg [2:0] state;
    reg [ADDR_W_S-1:0] sp_idx;
    reg [ADDR_W_D-1:0] prev_chunk;
    reg [DW-1:0] prev_data;
    reg prev_valid;
    localparam S_FETCH_SP = 3'd0;
    localparam S_WAIT_SP = 3'd1;
    localparam S_REQ_DENSE = 3'd2;
    localparam S_DENSE_WAIT=3'd3;
    localparam S_MODIFY_WRITE = 3'd4;
    localparam S_NEXT = 3'd5;
    always@(posedge clk) begin
        if(rst) begin
            state <= S_FETCH_SP;
            sp_idx <=0;
            data_out_C <= 0;
            addr_out_C<=0;
            we_C<=0;
            done<=1'b0;
            prev_valid <= 1'b0;
            start_prev<=0;
        end
        else begin
            start_prev <= start;
            case(state) 
            S_FETCH_SP: begin
                we_C <=0;
                done <= 1'b0;
                if((start && !start_prev) || sp_idx != 0) begin
                    addr_out_B <=sp_idx;
                    we_C<=1'b0;
                    done <= 1'b0;
                    state<= S_WAIT_SP;
                end
            end
            
            S_WAIT_SP: begin
                state<=S_REQ_DENSE;
            end
            S_REQ_DENSE: begin
                addr_out_A <= data_in_B >> 6;
                state<= S_DENSE_WAIT;
            end
            S_DENSE_WAIT: begin
                state<=S_MODIFY_WRITE;
            end
            S_MODIFY_WRITE: begin
                
                we_C<=1;
                addr_out_C <= data_in_B >> 6;
                if (prev_valid && ((data_in_B >> 6) == prev_chunk)) begin
                    data_out_C <= (64'b1 << data_in_B[5:0]) ^ prev_data;
                    prev_data  <= (64'b1 << data_in_B[5:0]) ^ prev_data;
                end else begin
                    data_out_C <= (64'b1 << data_in_B[5:0]) ^ data_in_A;
                    prev_data  <= (64'b1 << data_in_B[5:0]) ^ data_in_A;
                end
                prev_chunk <= data_in_B >> 6;
                prev_valid <= 1'b1;
                if(sp_idx==W-1) begin
                    done <= 1;
                    sp_idx <= 0;
                    prev_valid <= 1'b0;
                    state<= S_FETCH_SP;
                end
                else begin
                    sp_idx <= sp_idx + 1;
                    state <= S_FETCH_SP;
                end
            end
        endcase
    end
    end
endmodule
