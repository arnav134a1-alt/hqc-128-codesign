	imescale 1ns / 1ps
module ACCUM_MEM_BRAM(
    input clk,
    input we,
    input [9:0] waddr,
    input [63:0] din,
    input [9:0] raddr,
    output reg [63:0] dout
);
    (* ram_style = "block" *) reg [63:0] ram [0:552];
    always @(posedge clk) begin
        if (we) ram[waddr] <= din;
        dout <= ram[raddr];
    end
endmodule
