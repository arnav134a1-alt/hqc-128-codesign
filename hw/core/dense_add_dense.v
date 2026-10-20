`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 15.09.2026 16:52:52
// Design Name: 
// Module Name: dense_add_dense
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


module dense_add_dense#(
    parameter DW = 64,
    parameter depth = 277
    )(
    input wire clk,
    input wire rst,
    input wire start,
    output reg done,
    output reg [8:0] addr_out_A,
    output reg [8:0] addr_out_B,
    input wire [63:0] data_in_A,
    input wire [63:0] data_in_B,
    output reg [63:0] data_out_C,
    output reg [8:0] addr_out_C,
    output reg we_C
    );
    reg start_prev;
    reg [2:0] state;
    reg [8:0] chunk_idx;
    
    localparam S_REQUEST = 3'd0;
    localparam S_WAIT = 3'd1;
    localparam S_XOR_WRITE = 3'd2;
    always@(posedge clk) begin
        if(rst) begin
            state <= S_REQUEST;
            chunk_idx <=0;
            data_out_C <= 0;
            addr_out_C<=0;
            we_C<=0;
            done<=1'b0;
            start_prev<=0;
        end
        else begin
            start_prev <= start;
            case(state) 
            
            S_REQUEST: begin
                we_C <= 1'b0;
                done <= 1'b0;
                if((start&&!start_prev) || chunk_idx != 0) begin
                    addr_out_A <= chunk_idx;
                    addr_out_B <= chunk_idx;
                    done <= 1'b0; 
                    state <= S_WAIT;
                end
                
            end
            S_WAIT: begin
                state<=S_XOR_WRITE;
            end
            S_XOR_WRITE: begin
                data_out_C <= data_in_A^data_in_B;
                addr_out_C <= chunk_idx;
                we_C <= 1'b1;
                chunk_idx <= chunk_idx +1;
                if(chunk_idx == depth-1) begin
                    done <= 1'b1;
                    chunk_idx<=0;
                    state<=S_REQUEST;
                end
                else state<= S_REQUEST;
            end
        endcase
    end
    end
    
    
    
endmodule
