`timescale 1ns / 1ps

module tb_top_pke_ref;
    localparam DW          = 64;
    localparam DEPTH       = 277;
    localparam W           = 66;
    localparam ADDR_W_S    = 7;
    localparam SP_DATA_W   = 15;
    localparam ADDR_W_D    = 9;
    localparam PKE_BYTES   = 16;
    localparam NUM_VECTORS = 100;

    reg                     clk;
    reg                     rst;
    reg  [1:0]              op_mode;
    reg                     start;
    wire                    done;
    reg  [8*PKE_BYTES-1:0]  msg_in;
    wire [8*PKE_BYTES-1:0]  msg_out;
    wire                    msg_valid;
    reg  [3:0]              host_mem_sel;
    reg  [ADDR_W_D-1:0]     host_addr;
    reg  [DW-1:0]           host_wdata;
    reg                     host_we;
    wire [DW-1:0]           host_rdata;

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    reg [63:0] ref_h  [0:NUM_VECTORS*277-1];
    reg [63:0] ref_x  [0:NUM_VECTORS*277-1];
    reg [63:0] ref_y  [0:NUM_VECTORS*277-1];
    reg [63:0] ref_r1 [0:NUM_VECTORS*277-1];
    reg [63:0] ref_r2 [0:NUM_VECTORS*277-1];
    reg [63:0] ref_e  [0:NUM_VECTORS*277-1];
    reg [63:0] ref_m  [0:NUM_VECTORS*2-1];
    reg [63:0] ref_v  [0:NUM_VECTORS*277-1];
    reg [63:0] ref_u  [0:NUM_VECTORS*277-1];
    reg [63:0] ref_s  [0:NUM_VECTORS*277-1];

    initial begin
        $readmemh("h.mem",  ref_h);
        $readmemh("x.mem",  ref_x);
        $readmemh("y.mem",  ref_y);
        $readmemh("r1.mem", ref_r1);
        $readmemh("r2.mem", ref_r2);
        $readmemh("e.mem",  ref_e);
        $readmemh("m.mem",  ref_m);
        $readmemh("v.mem",  ref_v);
        $readmemh("u.mem",  ref_u);
        $readmemh("s.mem",  ref_s);
    end

    top_full dut (
        .clk(clk),
        .rst(rst),
        .op_mode(op_mode),
        .start(start),
        .done(done),
        .msg_in(msg_in),
        .msg_out(msg_out),
        .msg_valid(msg_valid),
        .host_mem_sel(host_mem_sel),
        .host_addr(host_addr),
        .host_wdata(host_wdata),
        .host_we(host_we),
        .host_rdata(host_rdata)
    );

    task write_dense;
        input [3:0] mem_sel;
        input integer addr;
        input [63:0] data;
        begin
            @(posedge clk); host_mem_sel = mem_sel;
            host_addr  = addr;
            host_wdata = data;
            host_we    = 1'b1;
            @(posedge clk);
            host_we    = 1'b0;
        end
    endtask

    task write_sparse;
        input [3:0] mem_sel;
        input integer sp_idx;
        input integer bit_pos;
        begin
            @(posedge clk); host_mem_sel = mem_sel;
            host_addr  = sp_idx;
            host_wdata = bit_pos;
            host_we    = 1'b1;
            @(posedge clk);
            host_we    = 1'b0;
        end
    endtask

    task load_sparse_from_dense;
        input [3:0] mem_sel;
        input integer v_offset;
        integer i, j, sp_idx;
        reg [63:0] word;
        begin
            sp_idx = 0;
            for (i = 0; i < 277; i = i + 1) begin
                if (mem_sel == 4'd8)      word = ref_y[v_offset + i];
                else if (mem_sel == 4'd5) word = ref_r1[v_offset + i];
                else if (mem_sel == 4'd6) word = ref_r2[v_offset + i];
                else if (mem_sel == 4'd7) word = ref_e[v_offset + i];

                for (j = 0; j < 64; j = j + 1) begin
                    if (word[j]) begin
                        write_sparse(mem_sel, sp_idx, (i * 64) + j);
                        sp_idx = sp_idx + 1;
                    end
                end
            end
        end
    endtask

    integer err_s = 0;
    integer err_v = 0;
    integer err_m = 0;
    integer err_u = 0;
    integer total_tests = 100;

    initial begin
        rst = 1;
        #1 start = 0;
        host_we = 0;
        op_mode = 0;
        #100;
        rst = 0;
        #100;

        for (integer v = 0; v < total_tests; v = v + 1) begin
            // KeyGen setup
            for (integer i = 0; i < 277; i = i + 1) write_dense(4'd10, i, ref_x[v*277 + i]);
            load_sparse_from_dense(4'd8, v*277);
            for (integer i = 0; i < 277; i = i + 1) write_dense(4'd0, i, ref_h[v*277 + i]);

            op_mode = 2'b00; // KeyGen
            @(posedge clk); #1 start = 1;
            @(posedge clk); #1 start = 0;
            @(posedge done);

            // Encrypt setup
            msg_in = {ref_m[v*2+1], ref_m[v*2]};
            load_sparse_from_dense(4'd5, v*277);
            load_sparse_from_dense(4'd6, v*277);
            load_sparse_from_dense(4'd7, v*277);

            op_mode = 2'b01; // Encrypt
            @(posedge clk); #1 start = 1;
            @(posedge clk); #1 start = 0;
            @(posedge done);

            // Decrypt setup
            op_mode = 2'b10; // Decrypt
            @(posedge clk); #1 start = 1;
            @(posedge clk); #1 start = 0;
            @(posedge done);

            if (msg_out !== {ref_m[v*2+1], ref_m[v*2]}) begin
                err_m = err_m + 1;
                $display("Vector %0d: msg_out = %016x, ref = %016x", v, msg_out, {ref_m[v*2+1], ref_m[v*2]});
            end
        end

        $display("S Mismatch: %0d", err_s);
        $display("U Mismatch: %0d", err_u);
        $display("V Mismatch: %0d", err_v);
        $display("M Mismatch: %0d", err_m);
        $finish;
    end
endmodule
