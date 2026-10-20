`timescale 1ns / 1ps

/*
 * Functional testbench for HQC-128 PKE core (top_full).
 * Tests KeyGen -> Encap -> Decap round-trip at 100 MHz clock.
 */

module tb_top_full;

    localparam DW        = 64;
    localparam DEPTH     = 277;
    localparam W         = 66;
    localparam ADDR_W_S  = 7;
    localparam SP_DATA_W = 15;
    localparam ADDR_W_D  = 9;
    localparam PKE_BYTES   = 16;
    localparam CLK_PERIOD = 10.0; /* 100 MHz */

    reg                     clk;
    reg                     rst;
    reg  [1:0]              op_mode;
    reg                     start;
    wire                    done;
    reg  [8*PKE_BYTES-1:0]    msg_in;
    wire [8*PKE_BYTES-1:0]    msg_out;
    wire                    msg_valid;
    reg  [3:0]              host_mem_sel;
    reg  [ADDR_W_D-1:0]     host_addr;
    reg  [DW-1:0]           host_wdata;
    reg                     host_we;
    wire [DW-1:0]           host_rdata;

    integer cycle_count;
    integer kg_cycles;
    integer enc_cycles;
    integer dec_cycles;
    integer i;
    reg [63:0] dbg_u, dbg_v;
    integer int_k;

    always @(posedge clk) begin
        if (dut.ENC_ADAPT.CONCAT_ENC.done_rs) begin
            $display("[DEBUG RS_ENC] RS Codeword (46 bytes): %h", dut.ENC_ADAPT.CONCAT_ENC.rs_cdw_out);
        end
        if (dut.DEC_ADAPT.DECODER.RM_DECOD.ram_dout_wr_o) begin
            $display("[DEBUG RM_DECOD] Decoded cdw[%0d] = 0x%02h", 
                     dut.DEC_ADAPT.DECODER.RM_DECOD.RM_DECOD_CTRL.cnt_out, 
                     dut.DEC_ADAPT.DECODER.RM_DECOD.ram_dout_o);
        end
        if (dut.DEC_ADAPT.state == 3'd1 && dut.DEC_ADAPT.step == 3'd7) begin
            if (dut.DEC_ADAPT.cdw_idx >= 40) begin
                $display("[DEBUG DEC_ADAPT] Prefetched cdw %0d (base %0d): buf[0]=0x%032h, buf[1]=0x%032h, buf[2]=0x%032h",
                         dut.DEC_ADAPT.cdw_idx, dut.DEC_ADAPT.base_addr,
                         dut.DEC_ADAPT.prefetch_buf[0],
                         dut.DEC_ADAPT.prefetch_buf[1],
                         {dut.DEC_ADAPT.n_dout, dut.DEC_ADAPT.buf_lo});
            end
        end
        if (dut.dec_done) begin
            $display("[DEBUG DECAP ARITH] Decap Arith done, dumping words 240-276 of BRAM U (N):");
            for (int_k = 240; int_k < 277; int_k = int_k + 1) begin
                $display("  N_word[%0d] = 0x%016h", int_k, dut.U.ram[int_k]);
            end
        end
        if (dut.DEC_ADAPT.DECODER.RS_DECOD.done_o) begin
            $display("[DEBUG RS_DECOD] RS Decoder done:");
            $display("  msg_temp  = 0x%032h", dut.DEC_ADAPT.DECODER.RS_DECOD.msg_temp);
            $display("  err_val   = 0x%032h", dut.DEC_ADAPT.DECODER.RS_DECOD.err_val);
            $display("  deg_sigma = %0d", dut.DEC_ADAPT.DECODER.RS_DECOD.deg_sigma);
            $display("  syndromes = 0x%h", dut.DEC_ADAPT.DECODER.RS_DECOD.syndromes);
        end
    end

    top_full #(
        .DW(DW),
        .DEPTH(DEPTH),
        .W(W),
        .ADDR_W_S(ADDR_W_S),
        .SP_DATA_W(SP_DATA_W),
        .ADDR_W_D(ADDR_W_D),
        .PKE_BYTES(PKE_BYTES)
    ) dut (
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

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2.0) clk = ~clk;
    end

    always @(posedge clk) begin
        if (rst) cycle_count <= 0;
        else cycle_count <= cycle_count + 1;
    end

    always @(dut.pke_state) begin
        case (dut.pke_state)
            4'd0:  $display("  [FSM @ %0t ns] P_IDLE", $time);
            4'd1:  $display("  [FSM @ %0t ns] P_KEYGEN", $time);
            4'd2:  $display("  [FSM @ %0t ns] P_WAIT_KG", $time);
            4'd3:  $display("  [FSM @ %0t ns] P_ENC_CODEC", $time);
            4'd4:  $display("  [FSM @ %0t ns] P_WAIT_ECOD", $time);
            4'd5:  $display("  [FSM @ %0t ns] P_ENC_ARITH", $time);
            4'd6:  $display("  [FSM @ %0t ns] P_WAIT_EARI", $time);
            4'd7:  $display("  [FSM @ %0t ns] P_DEC_ARITH", $time);
            4'd8:  $display("  [FSM @ %0t ns] P_WAIT_DARI", $time);
            4'd9:  $display("  [FSM @ %0t ns] P_DEC_CODEC", $time);
            4'd10: $display("  [FSM @ %0t ns] P_WAIT_DCOD", $time);
            4'd11: $display("  [FSM @ %0t ns] P_DONE", $time);
            default: ;
        endcase
    end

    task read_dense(input [3:0] sel, input [8:0] addr, output [63:0] data);
    begin
        @(posedge clk);
        #1;
        host_mem_sel = sel;
        host_addr    = addr;
        host_we      = 1'b0;
        @(posedge clk);
        #1;
        data = host_rdata;
    end
    endtask

    task write_dense(input [3:0] sel, input [8:0] addr, input [63:0] data);
    begin
        @(posedge clk);
        #1;
        host_mem_sel = sel;
        host_addr    = addr;
        host_wdata   = data;
        host_we      = 1'b1;
        @(posedge clk);
        #1;
        host_we      = 1'b0;
    end
    endtask

    task write_sparse(input [3:0] sel, input [6:0] addr, input [14:0] data);
    begin
        @(posedge clk);
        #1;
        host_mem_sel = sel;
        host_addr    = {2'b00, addr};
        host_wdata   = {49'd0, data};
        host_we      = 1'b1;
        @(posedge clk);
        #1;
        host_we      = 1'b0;
    end
    endtask

    task trigger_operation(input [1:0] mode);
    begin
        @(posedge clk);
        #1;
        op_mode = mode;
        start   = 1'b1;
        @(posedge clk);
        #1;
        start   = 1'b0;
    end
    endtask

    initial begin
        $display("HQC-128 core simulation start (100 MHz)");

        /* system reset */
        rst          = 1'b1;
        op_mode      = 2'b00;
        start        = 1'b0;
        msg_in       = 128'h0;
        host_mem_sel = 4'd0;
        host_addr    = 9'd0;
        host_wdata   = 64'd0;
        host_we      = 1'b0;

        repeat (10) @(posedge clk);
        #1;
        rst = 1'b0;
        repeat (5) @(posedge clk);

        /* preload dense ring parameter h and clear state */
        for (i = 0; i < DEPTH; i = i + 1) begin
            write_dense(4'd0, i, {32'hA5A50000 + i, 32'h5A5A0000 + i});
            write_dense(4'd1, i, 64'd0);
            write_dense(4'd3, i, 64'd0);
            write_dense(4'd4, i, 64'd0);
            write_dense(4'd10, i, 64'd0);
        end

        /* preload sparse polynomials y, r1, r2, e */
        for (i = 0; i < W; i = i + 1) begin
            write_sparse(4'd8, i, (i * 267 + 5) % 17669);
            write_sparse(4'd5, i, 15'd0);
            write_sparse(4'd6, i, 15'd0);
            write_sparse(4'd7, i, 15'd0);
        end

        /* KeyGen execution */
        $display("Starting KeyGen (op=00)...");
        kg_cycles = cycle_count;
        trigger_operation(2'b00);

        @(posedge done);
        kg_cycles = cycle_count - kg_cycles;
        $display("KeyGen complete: %0d cycles (%0.2f us @ 100 MHz)", 
                 kg_cycles, kg_cycles * 0.010);

        repeat (10) @(posedge clk);

        /* Encapsulation execution */
        msg_in = 128'h000102030405060708090a0b0c0d0e0f;
        $display("Starting Encap (op=01), msg_in=0x%032h", msg_in);

        enc_cycles = cycle_count;
        trigger_operation(2'b01);

        @(posedge done);
        enc_cycles = cycle_count - enc_cycles;
        $display("Encap complete: %0d cycles (%0.2f us @ 100 MHz)", 
                 enc_cycles, enc_cycles * 0.010);

        repeat (5) @(posedge clk);

        /* Decapsulation execution */
        $display("Starting Decap (op=10)...");
        dec_cycles = cycle_count;
        trigger_operation(2'b10);

        @(posedge done);
        dec_cycles = cycle_count - dec_cycles;
        $display("Decap complete: %0d cycles (%0.2f us @ 100 MHz)", 
                 dec_cycles, dec_cycles * 0.010);

        repeat (5) @(posedge clk);

        /* verification check */
        $display("Verification:");
        $display("  msg_in:    0x%032h", msg_in);
        $display("  msg_out:   0x%032h", msg_out);
        $display("  msg_valid: %b", msg_valid);
        $display("  latencies: KeyGen %0d cyc, Encap %0d cyc, Decap %0d cyc",
                 kg_cycles, enc_cycles, dec_cycles);

        if (msg_out === msg_in) begin
            $display("PASS: Recovered message matches input (bit-exact round trip)");
        end else begin
            $display("FAIL: Mismatch! Expected 0x%032h, got 0x%032h", msg_in, msg_out);
        end

        repeat (20) @(posedge clk);
        $finish;
    end

    /* 2 ms watchdog to prevent hang on broken state machine */
    initial begin
        #2_000_000;
        $display("[ERROR] Watchdog timeout (2 ms); core hung in state %0d", dut.pke_state);
        $finish;
    end

endmodule
