`timescale 1ns / 1ps
module tb_rm;
    reg clk = 0;
    always #5 clk = ~clk;
    
    reg rst = 1;
    reg start = 0;
    wire busy, done, ram_rd;
    wire [8:0] ram_addr;
    reg [127:0] ram_din = 0;
    wire [127:0] dec_dout;
    wire dec_valid;

    hqc_decod_top #(
        .PARAM_SECURITY(128)
    ) DECODER (
        .clk_i(clk),
        .rst_ni(~rst),
        .start_i(start),
        .busy_o(busy),
        .ram_din_i(ram_din),
        .ram_din_rd_o(ram_rd),
        .ram_din_addr_o(ram_addr),
        .dout_o(dec_dout),
        .dout_valid_o(dec_valid)
    );

    wire [127:0] enc_out;
    rm_encoder ENC (
        .clk(clk),
        .rst(rst),
        .start(1'b0),
        .byte_in(8'h60),
        .cdw_out(enc_out),
        .done()
    );

    initial begin
        #20 rst = 0;
        #10 start = 1;
        #10 start = 0;
    end

    always @(posedge clk) begin
        if (ram_rd) begin
            ram_din <= enc_out;
        end
        if (dec_valid) begin
            $display("Decoded: %h", dec_dout);
            $finish;
        end
    end
endmodule
