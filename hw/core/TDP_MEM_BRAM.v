`timescale 1ns / 1ps

module TDP_MEM_BRAM #(
    parameter DW = 64, 
    parameter DEPTH = 1024,
    parameter ADDR_W = 10
)(
    input wire clk,
    input wire weA,
    input wire [ADDR_W-1:0] addrA,
    input wire [DW-1:0] dinA,
    output reg [DW-1:0] doutA,
    
    input wire weB,
    input wire [ADDR_W-1:0] addrB,
    input wire [DW-1:0] dinB,
    output reg [DW-1:0] doutB
);
    (* ram_style = "block" *) reg [DW-1:0] ram [0:DEPTH-1];
    
    always @(posedge clk) begin
        if (weA) ram[addrA] <= dinA;
        doutA <= ram[addrA];
    end
    
    always @(posedge clk) begin
        if (weB) ram[addrB] <= dinB;
        doutB <= ram[addrB];
    end
endmodule
