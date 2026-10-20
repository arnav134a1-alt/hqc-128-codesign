`timescale 1ns / 1ps

module top_full #(
    parameter DW = 64,
    parameter DEPTH = 277,
    parameter W = 66,
    parameter WR = 75,
    parameter WE = 75,
    parameter ADDR_W_S = 7,
    parameter SP_DATA_W = 15,
    parameter ADDR_W_D = 9,
    parameter PKE_BYTES = 16
)(
    input  wire                  clk,
    input  wire                  rst,
    
    // Control interface
    input  wire [1:0]            op_mode,    // 2'b00=KeyGen, 2'b01=Encap, 2'b10=Decap
    input  wire                  start,
    output reg                   done,
    
    // Message interface
    input  wire [8*PKE_BYTES-1:0]  msg_in,     // 128-bit message to encrypt
    output wire [8*PKE_BYTES-1:0]  msg_out,    // 128-bit recovered message from decrypt
    output wire                  msg_valid,
    
    // Host memory access
    input  wire [3:0]            host_mem_sel,
    input  wire [ADDR_W_D-1:0]   host_addr,
    input  wire [DW-1:0]         host_wdata,
    input  wire                  host_we,
    output wire [DW-1:0]         host_rdata
);

    /* State storage: 5 dense polynomials (h, s, U/n, V/mG, x) + 1 shared ring acc (T1). Total 6 RAMB36 tiles. */

    // Dense State BRAMs
    reg we_h; reg [ADDR_W_D-1:0] addr_h; reg [DW-1:0] din_h; wire [DW-1:0] dout_h;
    DENSE_MEM_BRAM h(.clk(clk), .we(we_h), .waddr(addr_h), .din(din_h), .raddr(addr_h), .dout(dout_h));
    
    reg we_s; reg [ADDR_W_D-1:0] addr_s; reg [DW-1:0] din_s; wire [DW-1:0] dout_s;
    DENSE_MEM_BRAM s(.clk(clk), .we(we_s), .waddr(addr_s), .din(din_s), .raddr(addr_s), .dout(dout_s));
    
    reg we_U; reg [ADDR_W_D-1:0] addr_U; reg [DW-1:0] din_U; wire [DW-1:0] dout_U;
    DENSE_MEM_BRAM U(.clk(clk), .we(we_U), .waddr(addr_U), .din(din_U), .raddr(addr_U), .dout(dout_U));
    
    reg we_V; reg [ADDR_W_D-1:0] addr_V; reg [DW-1:0] din_V; wire [DW-1:0] dout_V;
    DENSE_MEM_BRAM V(.clk(clk), .we(we_V), .waddr(addr_V), .din(din_V), .raddr(addr_V), .dout(dout_V));
    
    reg we_x; reg [ADDR_W_D-1:0] addr_x; reg [DW-1:0] din_x; wire [DW-1:0] dout_x;
    DENSE_MEM_BRAM x(.clk(clk), .we(we_x), .waddr(addr_x), .din(din_x), .raddr(addr_x), .dout(dout_x));

    // Shared Datapath Accumulator BRAM (T1)
    reg                  we_T1;
    reg  [ADDR_W_D-1:0]  waddr_T1, raddr_T1;
    reg  [DW-1:0]        din_T1;
    wire [DW-1:0]        dout_T1;

    DENSE_MEM_BRAM T1_shared(
        .clk(clk), .we(we_T1), .waddr(waddr_T1), .din(din_T1),
        .raddr(raddr_T1), .dout(dout_T1)
    );

    // Sparse Polynomial Memories (Synthesized into Distributed LUTRAM)
    reg we_r1; reg [ADDR_W_S-1:0] addr_r1; reg [SP_DATA_W-1:0] din_r1; wire [SP_DATA_W-1:0] dout_r1;
    SPARSE_MEM #(.W(WR)) r1(.clk(clk), .we(we_r1), .addr(addr_r1), .din(din_r1), .dout(dout_r1));
    
    reg we_r2; reg [ADDR_W_S-1:0] addr_r2; reg [SP_DATA_W-1:0] din_r2; wire [SP_DATA_W-1:0] dout_r2;
    SPARSE_MEM #(.W(WR)) r2(.clk(clk), .we(we_r2), .addr(addr_r2), .din(din_r2), .dout(dout_r2));
    
    reg we_e; reg [ADDR_W_S-1:0] addr_e; reg [SP_DATA_W-1:0] din_e; wire [SP_DATA_W-1:0] dout_e;
    SPARSE_MEM #(.W(WE)) e(.clk(clk), .we(we_e), .addr(addr_e), .din(din_e), .dout(dout_e));
    
    reg we_y; reg [ADDR_W_S-1:0] addr_y; reg [SP_DATA_W-1:0] din_y; wire [SP_DATA_W-1:0] dout_y;
    SPARSE_MEM y(.clk(clk), .we(we_y), .addr(addr_y), .din(din_y), .dout(dout_y));

    /* Datapath instances */

    /* KeyGen datapath */
    reg  kg_start;
    wire kg_done;
    wire [ADDR_W_D-1:0] kg_addr_h, kg_addr_x, kg_addr_s;
    wire [ADDR_W_S-1:0] kg_addr_y;
    wire [DW-1:0] kg_s_out;
    wire kg_s_we;
    wire kg_T1_we;
    wire [ADDR_W_D-1:0] kg_T1_waddr, kg_T1_raddr;
    wire [DW-1:0] kg_T1_din;

    KeyGen_datapath_shared KG (
        .clk(clk), .rst(rst), .start(kg_start), .done(kg_done),
        .addr_out_h(kg_addr_h), .data_in_h(dout_h),
        .addr_out_y(kg_addr_y), .data_in_y(dout_y),
        .addr_out_x(kg_addr_x), .data_in_x(dout_x),
        .s_out(kg_s_out), .s_addr(kg_addr_s), .s_we(kg_s_we),
        .T1_we(kg_T1_we), .T1_waddr(kg_T1_waddr), .T1_din(kg_T1_din),
        .T1_raddr(kg_T1_raddr), .T1_dout(dout_T1)
    );

    /* Encryption datapath */
    reg  enc_start;
    wire enc_done;
    wire [ADDR_W_D-1:0] enc_addr_h, enc_addr_s, enc_addr_MG, enc_addr_U, enc_addr_V;
    wire [ADDR_W_S-1:0] enc_addr_r1, enc_addr_r2, enc_addr_e;
    wire enc_we_U, enc_we_V;
    wire [DW-1:0] enc_dout_U, enc_dout_V;
    wire enc_T1_we;
    wire [ADDR_W_D-1:0] enc_T1_waddr, enc_T1_raddr;
    wire [DW-1:0] enc_T1_din;

    Encryption_datapath_shared ENC (
        .clk(clk), .rst(rst), .enc_start(enc_start), .enc_done(enc_done),
        .data_in_h(dout_h), .data_in_s(dout_s), .data_in_MG(dout_V),
        .data_in_r1(dout_r1), .data_in_r2(dout_r2), .data_in_e(dout_e),
        .addr_out_h(enc_addr_h), .addr_out_s(enc_addr_s), .addr_out_MG(enc_addr_MG),
        .addr_out_r1(enc_addr_r1), .addr_out_r2(enc_addr_r2), .addr_out_e(enc_addr_e),
        .U_out(enc_dout_U), .V_out(enc_dout_V),
        .U_addr(enc_addr_U), .V_addr(enc_addr_V), .U_we(enc_we_U), .V_we(enc_we_V),
        .T1_we(enc_T1_we), .T1_waddr(enc_T1_waddr), .T1_din(enc_T1_din),
        .T1_raddr(enc_T1_raddr), .T1_dout(dout_T1)
    );

    /* Decryption datapath */
    reg  dec_start;
    wire dec_done;
    wire [ADDR_W_D-1:0] dec_addr_U, dec_addr_V, dec_addr_N;
    wire [ADDR_W_S-1:0] dec_addr_y;
    wire dec_we_N;
    wire [DW-1:0] dec_dout_N;
    wire dec_T1_we;
    wire [ADDR_W_D-1:0] dec_T1_waddr, dec_T1_raddr;
    wire [DW-1:0] dec_T1_din;

    Decryption_datapath_shared DEC (
        .clk(clk), .rst(rst), .dec_start(dec_start), .dec_done(dec_done),
        .data_in_U(dout_U), .data_in_V(dout_V), .data_in_y(dout_y),
        .addr_out_U(dec_addr_U), .addr_out_V(dec_addr_V), .addr_out_y(dec_addr_y),
        .N_out(dec_dout_N), .N_addr(dec_addr_N), .N_we(dec_we_N),
        .T1_we(dec_T1_we), .T1_waddr(dec_T1_waddr), .T1_din(dec_T1_din),
        .T1_raddr(dec_T1_raddr), .T1_dout(dout_T1)
    );

    /* RS + RM encoder adapter */
    reg  codec_enc_start;
    wire codec_enc_done;
    wire enc_mg_we;
    wire [ADDR_W_D-1:0] enc_mg_waddr;
    wire [DW-1:0] enc_mg_wdata;

    encoder_adapter ENC_ADAPT (
        .clk(clk), .rst(rst), .start(codec_enc_start), .msg_in(msg_in),
        .mg_we(enc_mg_we), .mg_waddr(enc_mg_waddr), .mg_wdata(enc_mg_wdata),
        .done(codec_enc_done)
    );

    /* RS + RM decoder adapter */
    reg  codec_dec_start;
    wire codec_dec_done;
    wire [ADDR_W_D-1:0] dec_n_raddr;

    decoder_adapter DEC_ADAPT (
        .clk(clk), .rst(rst), .start(codec_dec_start),
        .n_raddr(dec_n_raddr), .n_dout(dout_U),
        .msg_out(msg_out), .msg_valid(msg_valid),
        .done(codec_dec_done)
    );

    /* Top-level control FSM */

    localparam P_IDLE       = 4'd0;
    localparam P_KEYGEN     = 4'd1;
    localparam P_WAIT_KG    = 4'd2;
    localparam P_ENC_CODEC  = 4'd3;
    localparam P_WAIT_ECOD  = 4'd4;
    localparam P_ENC_ARITH  = 4'd5;
    localparam P_WAIT_EARI  = 4'd6;
    localparam P_DEC_ARITH  = 4'd7;
    localparam P_WAIT_DARI  = 4'd8;
    localparam P_DEC_CODEC  = 4'd9;
    localparam P_WAIT_DCOD  = 4'd10;
    localparam P_DONE       = 4'd11;

    reg [3:0] pke_state;

    reg start_prev;
    always @(posedge clk) begin
        if (rst) start_prev <= 1'b0;
        else start_prev <= start;
    end
    wire start_pulse = start && !start_prev;

    always @(posedge clk) begin
        if (rst) begin
            pke_state <= P_IDLE;
            done <= 1'b0;
            kg_start <= 1'b0;
            enc_start <= 1'b0;
            dec_start <= 1'b0;
            codec_enc_start <= 1'b0;
            codec_dec_start <= 1'b0;
        end else begin
            case (pke_state)
                P_IDLE: begin
                    done <= 1'b0;
                    kg_start <= 1'b0;
                    enc_start <= 1'b0;
                    dec_start <= 1'b0;
                    codec_enc_start <= 1'b0;
                    codec_dec_start <= 1'b0;

                    if (start_pulse) begin
                        if (op_mode == 2'b00) pke_state <= P_KEYGEN;
                        else if (op_mode == 2'b01) pke_state <= P_ENC_CODEC;
                        else if (op_mode == 2'b10) pke_state <= P_DEC_ARITH;
                    end
                end

                /* KeyGen */
                P_KEYGEN: begin
                    kg_start <= 1'b1;
                    pke_state <= P_WAIT_KG;
                end

                P_WAIT_KG: begin
                    kg_start <= 1'b0;
                    if (kg_done) pke_state <= P_DONE;
                end

                /* Encapsulation */
                P_ENC_CODEC: begin
                    codec_enc_start <= 1'b1;
                    pke_state <= P_WAIT_ECOD;
                end

                P_WAIT_ECOD: begin
                    codec_enc_start <= 1'b0;
                    if (codec_enc_done) pke_state <= P_ENC_ARITH;
                end

                P_ENC_ARITH: begin
                    enc_start <= 1'b1;
                    pke_state <= P_WAIT_EARI;
                end

                P_WAIT_EARI: begin
                    enc_start <= 1'b0;
                    if (enc_done) pke_state <= P_DONE;
                end

                /* Decapsulation */
                P_DEC_ARITH: begin
                    dec_start <= 1'b1;
                    pke_state <= P_WAIT_DARI;
                end

                P_WAIT_DARI: begin
                    dec_start <= 1'b0;
                    if (dec_done) pke_state <= P_DEC_CODEC;
                end

                P_DEC_CODEC: begin
                    codec_dec_start <= 1'b1;
                    pke_state <= P_WAIT_DCOD;
                end

                P_WAIT_DCOD: begin
                    codec_dec_start <= 1'b0;
                    if (codec_dec_done) pke_state <= P_DONE;
                end

                P_DONE: begin
                    done <= 1'b1;
                    pke_state <= P_IDLE;
                end

                default: pke_state <= P_IDLE;
            endcase
        end
    end

    wire is_busy = (pke_state != P_IDLE);

    /* Datapath and host MMIO multiplexing */

    // Shared Accumulator Muxing
    always @(*) begin
        we_T1 = 1'b0; waddr_T1 = 0; raddr_T1 = 0; din_T1 = 0;

        case (pke_state)
            P_KEYGEN, P_WAIT_KG: begin
                we_T1    = kg_T1_we;
                waddr_T1 = kg_T1_waddr;
                raddr_T1 = kg_T1_raddr;
                din_T1   = kg_T1_din;
            end

            P_ENC_ARITH, P_WAIT_EARI: begin
                we_T1    = enc_T1_we;
                waddr_T1 = enc_T1_waddr;
                raddr_T1 = enc_T1_raddr;
                din_T1   = enc_T1_din;
            end

            P_DEC_ARITH, P_WAIT_DARI: begin
                we_T1    = dec_T1_we;
                waddr_T1 = dec_T1_waddr;
                raddr_T1 = dec_T1_raddr;
                din_T1   = dec_T1_din;
            end
        endcase
    end

    // State BRAM and Sparse Memory Muxing
    always @(*) begin
        we_h = 1'b0; addr_h = 0; din_h = 0;
        we_s = 1'b0; addr_s = 0; din_s = 0;
        we_U = 1'b0; addr_U = 0; din_U = 0;
        we_V = 1'b0; addr_V = 0; din_V = 0;
        we_x = 1'b0; addr_x = 0; din_x = 0;
        
        we_r1 = 1'b0; addr_r1 = 0; din_r1 = 0;
        we_r2 = 1'b0; addr_r2 = 0; din_r2 = 0;
        we_e = 1'b0; addr_e = 0; din_e = 0;
        we_y = 1'b0; addr_y = 0; din_y = 0;
        
        if (!is_busy) begin
            // HOST DIRECT ACCESS
            case (host_mem_sel)
                4'd0: begin we_h = host_we; addr_h = host_addr; din_h = host_wdata; end
                4'd1: begin we_s = host_we; addr_s = host_addr; din_s = host_wdata; end
                4'd2: begin we_V = host_we; addr_V = host_addr; din_V = host_wdata; end // MG (reused in V)
                4'd3: begin we_U = host_we; addr_U = host_addr; din_U = host_wdata; end
                4'd4: begin we_V = host_we; addr_V = host_addr; din_V = host_wdata; end
                4'd5: begin we_r1 = host_we; addr_r1 = host_addr[ADDR_W_S-1:0]; din_r1 = host_wdata[SP_DATA_W-1:0]; end
                4'd6: begin we_r2 = host_we; addr_r2 = host_addr[ADDR_W_S-1:0]; din_r2 = host_wdata[SP_DATA_W-1:0]; end
                4'd7: begin we_e = host_we; addr_e = host_addr[ADDR_W_S-1:0]; din_e = host_wdata[SP_DATA_W-1:0]; end
                4'd8: begin we_y = host_we; addr_y = host_addr[ADDR_W_S-1:0]; din_y = host_wdata[SP_DATA_W-1:0]; end
                4'd9: begin we_U = host_we; addr_U = host_addr; din_U = host_wdata; end // N (reused in U)
                4'd10: begin we_x = host_we; addr_x = host_addr; din_x = host_wdata; end
            endcase
            // Modulo mask top word on write
            if (host_addr == 276 && (host_mem_sel < 5 || host_mem_sel == 9 || host_mem_sel == 10)) begin
                din_h = host_wdata & 64'h000000000000001F;
                din_s = host_wdata & 64'h000000000000001F;
                din_U = host_wdata & 64'h000000000000001F;
                din_V = host_wdata & 64'h000000000000001F;
                din_x = host_wdata & 64'h000000000000001F;
            end
        end else begin
            case (pke_state)
                P_KEYGEN, P_WAIT_KG: begin
                    addr_h = kg_addr_h; 
                    addr_y = kg_addr_y; 
                    addr_x = kg_addr_x;
                    we_s = kg_s_we; addr_s = kg_addr_s; din_s = kg_s_out;
                end

                P_ENC_CODEC, P_WAIT_ECOD: begin
                    we_V = enc_mg_we;
                    addr_V = enc_mg_waddr;
                    din_V = enc_mg_wdata;
                end

                P_ENC_ARITH, P_WAIT_EARI: begin
                    addr_h = enc_addr_h; 
                    addr_s = enc_addr_s; 
                    addr_r1 = enc_addr_r1; 
                    addr_r2 = enc_addr_r2; 
                    addr_e = enc_addr_e; 
                    we_U = enc_we_U; addr_U = enc_addr_U; din_U = enc_dout_U;
                    we_V = enc_we_V;
                    addr_V = enc_we_V ? enc_addr_V : enc_addr_MG;
                    din_V = enc_dout_V;
                end

                P_DEC_ARITH, P_WAIT_DARI: begin
                    we_U = dec_we_N;
                    addr_U = dec_we_N ? dec_addr_N : dec_addr_U;
                    din_U = dec_dout_N;
                    addr_V = dec_addr_V;
                    addr_y = dec_addr_y;
                end

                P_DEC_CODEC, P_WAIT_DCOD: begin
                    addr_U = dec_n_raddr;
                end
            endcase
        end
    end

    // Host Readback
    assign host_rdata = (host_mem_sel == 4'd0) ? dout_h :
                        (host_mem_sel == 4'd1) ? dout_s :
                        (host_mem_sel == 4'd2) ? dout_V :
                        (host_mem_sel == 4'd3) ? dout_U :
                        (host_mem_sel == 4'd4) ? dout_V :
                        (host_mem_sel == 4'd5) ? {49'd0, dout_r1} :
                        (host_mem_sel == 4'd6) ? {49'd0, dout_r2} :
                        (host_mem_sel == 4'd7) ? {49'd0, dout_e} :
                        (host_mem_sel == 4'd8) ? {49'd0, dout_y} :
                        (host_mem_sel == 4'd9) ? dout_U :
                        (host_mem_sel == 4'd10) ? dout_x :
                        64'd0;

endmodule
