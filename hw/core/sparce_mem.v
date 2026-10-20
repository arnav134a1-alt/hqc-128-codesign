module SPARSE_MEM #(
    parameter W = 66,      // (Hamming weight)
    parameter ADDR_W = 15  // Bit-width required to store the maximum index position N
)(
    input wire clk,
    input wire we,
    input wire [$clog2(W)-1:0] addr,
    input wire [ADDR_W-1:0] din,
    output reg [ADDR_W-1:0] dout  
);

   
    (* ram_style = "distributed" *) reg [ADDR_W-1:0] mem [0:W-1];

    always @(posedge clk) begin
        if (we) begin
            mem[addr] <= din;
        end
        dout <= mem[addr];
    end

endmodule