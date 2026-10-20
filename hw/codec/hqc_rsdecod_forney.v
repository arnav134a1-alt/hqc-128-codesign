// Serial Forney error-value computation for the HQC RS(46,16) decoder (delta = 15).
// Replaces the z-polynomial + err_val stages.  Pipelined version: the GF multiplier
// operands are registered (ma_r, mb_r), so operand selection and the multiplier are
// separate pipeline stages.
//   omega(x) = S(x)*sigma(x) mod x^(2*delta),  S(x) = sum_{k=1..2delta} S_k x^(k-1)
//   e_p      = omega(X^-1) / sigma'(X^-1),     X^-1 = alpha^-p   (first consecutive root b = 1)
// Only message positions (G-1 .. N1-1) are returned, byte i = position G-1+i.
module hqc_rsdecod_forney #(
    parameter PARAM_DELTA = 15,
    parameter PARAM_G     = 31,
    parameter PARAM_K     = 16,
    parameter PARAM_N1    = 46
    )(
    input                           clk_i,
    input                           rst_ni,
    input                           start_i,
    input  [8*2*PARAM_DELTA-1:0]    syn_i,     // byte k-1 = S_k
    input  [8*(PARAM_DELTA+1)-1:0]  sigma_i,   // byte j   = sigma_j
    input  [8*PARAM_N1-1:0]         error_i,   // byte p nonzero = error at position p
    output                          busy_o,
    output [8*PARAM_K-1:0]          err_o,
    output                          valid_o
    );

localparam NS = 2*PARAM_DELTA;   // 30

function [7:0] gmul;
    input [7:0] a, b;
    integer k;
    reg [7:0] r, x;
    begin
        r = 8'd0; x = a;
        for (k = 0; k < 8; k = k + 1) begin
            if (b[k]) r = r ^ x;
            x = {x[6:0], 1'b0} ^ (x[7] ? 8'h1D : 8'h00);
        end
        gmul = r;
    end
endfunction

// _I = issue (load multiplier operand registers), _C = commit (consume the product)
localparam [4:0] S_IDLE=0,  S_OM=1,     S_OMDRAIN=2, S_PCHK=3,
                 S_OEV_I=4, S_OEV_C=5,  S_Y_I=6,     S_Y_C=7,
                 S_SEV_I=8, S_SEV_C=9,  S_SQ_I=10,   S_SQ_C=11,
                 S_MUL_I=12,S_MUL_C=13, S_EV_I=14,   S_EV_C=15,
                 S_PN_I=16, S_PN_C=17,  S_DONE=18;

reg [4:0]   state;
reg [7:0]   sg [0:PARAM_DELTA];
reg [7:0]   sy [1:NS];
reg [7:0]   om [0:NS-1];
reg [PARAM_N1-1:0] flag;
reg [8*PARAM_K-1:0] errv;
reg [5:0]   m, p;
reg [4:0]   j;
reg [4:0]   k;
reg [2:0]   ib;
reg [7:0]   acc, x, y, omv, sp, r;
reg         valid;

// registered multiplier operands + combinational product of the registered operands
reg  [7:0] ma_r, mb_r;
wire [7:0] mo = gmul(ma_r, mb_r);

// streaming omega pipeline: product of the pair issued in the previous cycle
reg        v1, first1, last1;
reg [5:0]  m1;
wire [7:0] om_acc_in = first1 ? 8'd0 : acc;
wire [7:0] om_acc    = om_acc_in ^ mo;

wire [5:0] jmax = (m < PARAM_DELTA) ? m[5:0] : PARAM_DELTA;

integer i;
always @(posedge clk_i) begin
    valid <= 1'b0;
    if (~rst_ni) begin
        state <= S_IDLE;
        v1    <= 1'b0;
    end else begin
        case (state)
        S_IDLE: if (start_i) begin
            for (i = 0; i <= PARAM_DELTA; i = i + 1) sg[i] <= sigma_i[8*i +: 8];
            for (i = 1; i <= NS;          i = i + 1) sy[i] <= syn_i[8*(i-1) +: 8];
            for (i = 0; i < PARAM_N1;     i = i + 1) flag[i] <= (error_i[8*i +: 8] != 8'd0);
            errv  <= {8*PARAM_K{1'b0}};
            m <= 0; j <= 0; v1 <= 1'b0;
            state <= S_OM;
        end

        // omega coefficients: one product issued per cycle, accumulated one cycle later
        S_OM: begin
            ma_r   <= sg[j];
            mb_r   <= sy[m - j + 1];
            v1     <= 1'b1;
            first1 <= (j == 0);
            last1  <= (j == jmax[4:0]);
            m1     <= m;
            if (v1) begin
                acc <= om_acc;
                if (last1) om[m1] <= om_acc;
            end
            if (j == jmax[4:0]) begin
                j <= 0;
                if (m == NS-1) state <= S_OMDRAIN;
                else m <= m + 1'b1;
            end else j <= j + 1'b1;
        end
        S_OMDRAIN: begin
            acc <= om_acc;
            if (last1) om[m1] <= om_acc;
            v1 <= 1'b0;
            p <= 0; x <= 8'd1;
            state <= S_PCHK;
        end

        S_PCHK: begin
            if (p == PARAM_N1) state <= S_DONE;
            else if (flag[p]) begin acc <= 8'd0; k <= NS-1; state <= S_OEV_I; end
            else state <= S_PN_I;
        end

        // Horner evaluation of omega(x)
        S_OEV_I: begin ma_r <= acc; mb_r <= x; state <= S_OEV_C; end
        S_OEV_C: begin
            acc <= mo ^ om[k];
            if (k == 0) begin omv <= mo ^ om[0]; state <= S_Y_I; end
            else begin k <= k - 1'b1; state <= S_OEV_I; end
        end

        // y = x^2
        S_Y_I: begin ma_r <= x; mb_r <= x; state <= S_Y_C; end
        S_Y_C: begin y <= mo; acc <= 8'd0; k <= 7; state <= S_SEV_I; end

        // sigma'(x) = sum_k sigma_(2k+1) * y^k   (Horner in y)
        S_SEV_I: begin ma_r <= acc; mb_r <= y; state <= S_SEV_C; end
        S_SEV_C: begin
            acc <= mo ^ sg[2*k+1];
            if (k == 0) begin sp <= mo ^ sg[1]; r <= 8'd1; ib <= 3'd7; state <= S_SQ_I; end
            else begin k <= k - 1'b1; state <= S_SEV_I; end
        end

        // r = sp^254 by square-and-multiply (254 = 11111110b)
        S_SQ_I: begin ma_r <= r; mb_r <= r; state <= S_SQ_C; end
        S_SQ_C: begin
            r <= mo;
            if (ib == 0) state <= S_EV_I;
            else state <= S_MUL_I;
        end
        S_MUL_I: begin ma_r <= r; mb_r <= sp; state <= S_MUL_C; end
        S_MUL_C: begin r <= mo; ib <= ib - 1'b1; state <= S_SQ_I; end

        // e = omega(x) / sigma'(x)
        S_EV_I: begin ma_r <= omv; mb_r <= r; state <= S_EV_C; end
        S_EV_C: begin
            if (p >= PARAM_G-1) errv[8*(p-(PARAM_G-1)) +: 8] <= mo;
            state <= S_PN_I;
        end

        // x <= x * alpha^-1, next position
        S_PN_I: begin ma_r <= x; mb_r <= 8'h8E; state <= S_PN_C; end
        S_PN_C: begin x <= mo; p <= p + 1'b1; state <= S_PCHK; end

        S_DONE: begin valid <= 1'b1; state <= S_IDLE; end
        default: state <= S_IDLE;
        endcase
    end
end

assign busy_o  = (state != S_IDLE);
assign err_o   = errv;
assign valid_o = valid;

endmodule
