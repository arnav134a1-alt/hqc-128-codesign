`timescale 1ns / 1ps

/*
 * AXI4-Lite slave bridge for HQC-128 PKE coprocessor.
 * Adapts 32-bit SoC memory bus to 64-bit dual-port BRAM datapath.
 */

module hqc_pke_axi_lite #(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 7
)(
    input  wire                              s_axi_aclk,
    input  wire                              s_axi_aresetn,

    // Write address channel
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]     s_axi_awaddr,
    input  wire [2:0]                        s_axi_awprot,
    input  wire                              s_axi_awvalid,
    output reg                               s_axi_awready,

    // Write data channel
    input  wire [C_S_AXI_DATA_WIDTH-1:0]     s_axi_wdata,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input  wire                              s_axi_wvalid,
    output reg                               s_axi_wready,

    // Write response channel
    output reg  [1:0]                        s_axi_bresp,
    output reg                               s_axi_bvalid,
    input  wire                              s_axi_bready,

    // Read address channel
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]     s_axi_araddr,
    input  wire [2:0]                        s_axi_arprot,
    input  wire                              s_axi_arvalid,
    output reg                               s_axi_arready,

    // Read data channel
    output reg  [C_S_AXI_DATA_WIDTH-1:0]     s_axi_rdata,
    output reg  [1:0]                        s_axi_rresp,
    output reg                               s_axi_rvalid,
    input  wire                              s_axi_rready
);

    // Memory-mapped internal registers
    reg [31:0] reg_cr;
    reg [31:0] reg_mar;
    reg [31:0] reg_mdr_l;
    reg [31:0] reg_mdr_h;
    reg [31:0] reg_pinr [0:3];

    reg core_start_pulse;
    reg core_we_pulse;

    // Interface decoding
    wire [1:0]   op_mode      = reg_cr[2:1];
    wire         soft_rst     = reg_cr[3] | (~s_axi_aresetn);
    wire [3:0]   host_mem_sel = reg_mar[3:0];
    wire [8:0]   host_addr    = reg_mar[12:4];
    wire [63:0]  host_wdata   = {reg_mdr_h, reg_mdr_l};
    wire [63:0]  host_rdata;
    wire         core_done;
    wire         msg_valid;
    wire [127:0] msg_out;
    wire [127:0] msg_in = {reg_pinr[3], reg_pinr[2], reg_pinr[1], reg_pinr[0]};

    reg [C_S_AXI_ADDR_WIDTH-1:0] axi_awaddr;

    // AXI4-Lite write transactions
    always @(posedge s_axi_aclk) begin
        if (~s_axi_aresetn) begin
            s_axi_awready    <= 1'b0;
            s_axi_wready     <= 1'b0;
            s_axi_bvalid     <= 1'b0;
            s_axi_bresp      <= 2'b00;
            core_start_pulse <= 1'b0;
            core_we_pulse    <= 1'b0;
            reg_cr           <= 32'd0;
            reg_mar          <= 32'd0;
            reg_mdr_l        <= 32'd0;
            reg_mdr_h        <= 32'd0;
            reg_pinr[0]      <= 32'd0;
            reg_pinr[1]      <= 32'd0;
            reg_pinr[2]      <= 32'd0;
            reg_pinr[3]      <= 32'd0;
        end else begin
            core_start_pulse <= 1'b0;
            core_we_pulse    <= 1'b0;
            reg_cr[0]        <= 1'b0; // auto-clear START bit

            // Address handshake
            if (~s_axi_awready && s_axi_awvalid && s_axi_wvalid) begin
                s_axi_awready <= 1'b1;
                axi_awaddr    <= s_axi_awaddr;
            end else begin
                s_axi_awready <= 1'b0;
            end

            // Data handshake
            if (~s_axi_wready && s_axi_wvalid && s_axi_awvalid) begin
                s_axi_wready <= 1'b1;
            end else begin
                s_axi_wready <= 1'b0;
            end

            // Write commit
            if (s_axi_awvalid && s_axi_wvalid && ~s_axi_bvalid) begin
                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= 2'b00; // OKAY

                case (s_axi_awaddr[6:2])
                    5'h00: begin // 0x00: HQC_CR
                        reg_cr <= s_axi_wdata;
                        if (s_axi_wdata[0]) core_start_pulse <= 1'b1;
                    end
                    5'h02: reg_mar   <= s_axi_wdata; // 0x08: HQC_MAR
                    5'h03: reg_mdr_l <= s_axi_wdata; // 0x0C: HQC_MDR_L
                    5'h04: begin                    // 0x10: HQC_MDR_H (atomic write commit)
                        reg_mdr_h     <= s_axi_wdata;
                        core_we_pulse <= 1'b1;
                    end
                    5'h08: reg_pinr[0] <= s_axi_wdata; // 0x20
                    5'h09: reg_pinr[1] <= s_axi_wdata; // 0x24
                    5'h0A: reg_pinr[2] <= s_axi_wdata; // 0x28
                    5'h0B: reg_pinr[3] <= s_axi_wdata; // 0x2C
                    default: ;
                endcase
            end else if (s_axi_bready && s_axi_bvalid) begin
                s_axi_bvalid <= 1'b0;
            end
        end
    end

    // AXI4-Lite read transactions
    always @(posedge s_axi_aclk) begin
        if (~s_axi_aresetn) begin
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rresp   <= 2'b00;
            s_axi_rdata   <= 32'd0;
        end else begin
            if (~s_axi_arready && s_axi_arvalid) begin
                s_axi_arready <= 1'b1;
                s_axi_rvalid  <= 1'b1;
                s_axi_rresp   <= 2'b00;

                case (s_axi_araddr[6:2])
                    5'h00: s_axi_rdata <= reg_cr;
                    5'h01: s_axi_rdata <= {29'd0, msg_valid, core_done, ~core_done}; // HQC_SR
                    5'h02: s_axi_rdata <= reg_mar;
                    5'h05: s_axi_rdata <= host_rdata[31:0];                           // 0x14: MRR_L
                    5'h06: s_axi_rdata <= host_rdata[63:32];                          // 0x18: MRR_H
                    5'h08: s_axi_rdata <= reg_pinr[0];
                    5'h09: s_axi_rdata <= reg_pinr[1];
                    5'h0A: s_axi_rdata <= reg_pinr[2];
                    5'h0B: s_axi_rdata <= reg_pinr[3];
                    5'h0C: s_axi_rdata <= msg_out[31:0];                              // 0x30: POUTR[0]
                    5'h0D: s_axi_rdata <= msg_out[63:32];                             // 0x34: POUTR[1]
                    5'h0E: s_axi_rdata <= msg_out[95:64];                             // 0x38: POUTR[2]
                    5'h0F: s_axi_rdata <= msg_out[127:96];                            // 0x3C: POUTR[3]
                    default: s_axi_rdata <= 32'd0;
                endcase
            end else if (s_axi_rready && s_axi_rvalid) begin
                s_axi_rvalid  <= 1'b0;
                s_axi_arready <= 1'b0;
            end
        end
    end

    // HQC-128 core instance
    top_full #(
        .DW(64),
        .DEPTH(277),
        .W(66),
        .WR(75),
        .WE(75),
        .ADDR_W_S(7),
        .SP_DATA_W(15),
        .ADDR_W_D(9),
        .PKE_BYTES(16)
    ) dut (
        .clk          (s_axi_aclk),
        .rst          (soft_rst),
        .op_mode      (op_mode),
        .start        (core_start_pulse),
        .done         (core_done),
        .msg_in       (msg_in),
        .msg_out      (msg_out),
        .msg_valid    (msg_valid),
        .host_mem_sel (host_mem_sel),
        .host_addr    (host_addr),
        .host_wdata   (host_wdata),
        .host_we      (core_we_pulse),
        .host_rdata   (host_rdata)
    );

endmodule
