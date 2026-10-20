`timescale 1ns / 1ps

module DENSE_MEM_BRAM #(
    parameter DW = 64, 
    parameter DEPTH = 277, // ceil(17669/64)
    parameter ADDR_W = 9
)(
    input wire clk,
    input wire we,
    input wire [ADDR_W-1:0] waddr,
    input wire [DW-1:0] din,
    input wire [ADDR_W-1:0] raddr,
    output reg [DW-1:0] dout
);
    reg [DW-1:0] ram [0:DEPTH-1];
    always @(posedge clk) begin
        if (we) ram[waddr] <= din;
        dout <= ram[raddr];
    end
endmodule