// Chien-search replacement for the additive-FFT root finder.
// error_o byte i = 1 iff sigma(alpha^-i) == 0 (i = 0..PARAM_N1-1), same layout the
// err_val stage already consumes.
module hqc_rsdecod_roots #(
    parameter PARAM_SECURITY = 128,
    parameter PARAM_DELTA    = (PARAM_SECURITY == 128)? 15:
                               (PARAM_SECURITY == 192)? 16:
                               (PARAM_SECURITY == 256)? 29 : 15,
    parameter PARAM_N1       = (PARAM_SECURITY == 128)? 46:
                               (PARAM_SECURITY == 192)? 56:
                               (PARAM_SECURITY == 256)? 90 : 46,
    parameter ERR_W          = 8*PARAM_N1,
    parameter SIG_W          = 8*(PARAM_DELTA+1)
    )(
    input                   clk_i,
    input                   rst_ni,
    input   [SIG_W-1:0]     sigma_i,
    input                   start_i,
    output                  busy_o,
    output  [ERR_W-1:0]     error_o,
    output                  dout_valid_o
    );

// GF(2^8), x^8+x^4+x^3+x^2+1
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

// alpha^(-j) = alpha^(255-j)
function [7:0] ainv_pow;
    input integer j;
    integer k;
    reg [7:0] r;
    begin
        r = 8'd1;
        for (k = 0; k < 255 - j; k = k + 1) r = gmul(r, 8'h02);
        ainv_pow = r;
    end
endfunction

reg [7:0]       t [0:PARAM_DELTA];
reg [6:0]       cnt;
reg             busy, valid;
reg [ERR_W-1:0] err;

reg [7:0] sum;
integer j;
always @(*) begin
    sum = 8'd0;
    for (j = 0; j <= PARAM_DELTA; j = j + 1) sum = sum ^ t[j];
end

genvar g;
generate
    for (g = 0; g <= PARAM_DELTA; g = g + 1) begin: term
        localparam [7:0] C = ainv_pow(g);
        always @(posedge clk_i)
            if (start_i)     t[g] <= sigma_i[8*g +: 8];
            else if (busy)   t[g] <= gmul(t[g], C);
    end
endgenerate

always @(posedge clk_i) begin
    valid <= 1'b0;
    if (~rst_ni) begin
        busy <= 1'b0;
        cnt  <= 7'd0;
    end else if (start_i) begin
        busy <= 1'b1;
        cnt  <= 7'd0;
        err  <= {ERR_W{1'b0}};
    end else if (busy) begin
        err[8*cnt +: 8] <= {7'd0, (sum == 8'd0)};
        if (cnt == PARAM_N1 - 1) begin
            busy  <= 1'b0;
            valid <= 1'b1;
        end else begin
            cnt <= cnt + 1'b1;
        end
    end
end

assign busy_o       = busy;
assign error_o      = err;
assign dout_valid_o = valid;

endmodule
