`timescale 1ns / 1ps

module shift_acc #(
    parameter DW        = 64,
    parameter DEPTH     = 277,
    parameter ADDR_W    = 9,
    parameter SP_ADDR_W = 7,
    parameter W         = 66,
    parameter TOP_BITS  = 5          
)(
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  start,
 
    output reg  [SP_ADDR_W-1:0]  sp_addr,      
    input  wire [14:0]           sp_pos,
 
    output reg  [ADDR_W-1:0]     dense_raddr,
    input  wire [DW-1:0]         dense_rdata,
 
    output wire                  acc_we,
    output wire [ADDR_W-1:0]     acc_waddr,
    output wire [DW-1:0]         acc_wdata,
    output reg  [ADDR_W-1:0]     acc_raddr,
    input  wire [DW-1:0]         acc_rdata,
 
    output reg                   done
);
    localparam SH = 6;                               
    localparam [DW-1:0] TOP_MASK = {DW{1'b1}} >> (DW - TOP_BITS);
 
    localparam [3:0] IDLE = 0, WAIT = 1, LOAD = 2, RUN = 3, RUN_PIPE = 4, 
                     FIX_LAST_READ = 5, FIX_LAST_WRITE = 6;
 
    reg [3:0]    state;
    reg [SH-1:0] bit_shift;
    reg [DW-1:0] carry;          

    reg                  acc_we_reg;
    reg [ADDR_W-1:0]     acc_waddr_reg;
    reg [ADDR_W-1:0]     acc_raddr_d;
    reg [2*DW-1:0]       shifted_reg;
    reg                  first_reg;
    reg [DW-1:0]         wdata_reg;
    
    reg                  wrapped;
    reg [DW-1:0]         prev_shifted_val;
 
    // tail when we process the last valid data
    wire tail  = (dense_raddr == DEPTH + 1);
    wire first = (sp_addr == 0) && !tail;     
 
    wire [DW-1:0]   word    = tail ? {DW{1'b0}} : dense_rdata;
    wire [2*DW-1:0] shifted = {word, carry} << bit_shift;
    
    wire [DW-1:0] shifted_val = shifted_reg[2*DW-1:DW];
    wire [DW-1:0] fixed_val   = (shifted_val << 59) | (prev_shifted_val >> 5);
 
    assign acc_we    = acc_we_reg;
    assign acc_waddr = acc_waddr_reg;
    assign acc_wdata = wdata_reg;

    always @(posedge clk) begin
        done       <= 1'b0;
        acc_we_reg <= 1'b0; 
 
        case (state)
            IDLE: if (start) begin
                sp_addr <= 0;
                state   <= WAIT;
            end
 
            WAIT: begin                                   
                dense_raddr <= 0;
                state       <= LOAD;
            end
 
            LOAD: begin                                   
                bit_shift   <= sp_pos[SH-1:0];
                acc_raddr   <= sp_pos[14:SH];             
                carry       <= 0;
                dense_raddr <= 1;
                wrapped     <= 0;
                prev_shifted_val <= 0;
                // Wait one more cycle for h[0] to be ready!
                state       <= RUN;
            end
 
            RUN: begin
                carry       <= word;
                dense_raddr <= dense_raddr + 1; // 2 in first cycle
                
                shifted_reg <= shifted; // shifted uses dense_rdata which is h[0] in first cycle!
                first_reg   <= first;
                
                acc_raddr_d <= acc_raddr;
                
                if (dense_raddr > 1) begin
                    prev_shifted_val <= shifted_val;
                    acc_waddr_reg <= acc_raddr_d;
                    
                    if (acc_raddr_d == DEPTH-1) begin
                        wdata_reg <= (first_reg ? {DW{1'b0}} : acc_rdata) ^ (shifted_val & TOP_MASK);
                        wrapped <= 1'b1;
                    end else if (wrapped) begin
                        wdata_reg <= (first_reg ? {DW{1'b0}} : acc_rdata) ^ fixed_val;
                    end else begin
                        wdata_reg <= (first_reg ? {DW{1'b0}} : acc_rdata) ^ shifted_val;
                    end
                    acc_we_reg <= 1'b1;
                end
                
                acc_raddr <= (acc_raddr == DEPTH-1) ? 0 : acc_raddr + 1;
 
                if (tail) begin
                    state <= RUN_PIPE; 
                end
            end
            
            RUN_PIPE: begin
                // In RUN_PIPE, we do the LAST write (h[276]).
                // We MUST NOT overwrite prev_shifted_val here!
                
                acc_waddr_reg <= acc_raddr_d;
                
                if (acc_raddr_d == DEPTH-1) begin
                    wdata_reg <= (first_reg ? {DW{1'b0}} : acc_rdata) ^ (shifted_val & TOP_MASK);
                    wrapped <= 1'b1;
                end else if (wrapped) begin
                    wdata_reg <= (first_reg ? {DW{1'b0}} : acc_rdata) ^ fixed_val;
                end else begin
                    wdata_reg <= (first_reg ? {DW{1'b0}} : acc_rdata) ^ shifted_val;
                end
                // acc_we_reg <= 1'b1; // REMOVED!
                
                acc_raddr <= sp_pos[14:SH];
                state <= FIX_LAST_READ;
            end

            FIX_LAST_READ: begin
                state <= FIX_LAST_WRITE;
            end
            
            FIX_LAST_WRITE: begin
                acc_waddr_reg <= sp_pos[14:SH];
                wdata_reg     <= acc_rdata ^ fixed_val;
                acc_we_reg    <= 1'b1;
                
                if (sp_addr == W-1) begin
                    done <= 1'b1;
                    state <= IDLE;
                end else begin
                    sp_addr <= sp_addr + 1;
                    state <= WAIT;
                end
            end
 
            default: state <= IDLE;
        endcase
 
        if (rst) begin
            state <= IDLE; done <= 1'b0;
            sp_addr <= 0;  dense_raddr <= 0;   acc_raddr <= 0; acc_raddr_d <= 0;
            acc_we_reg <= 0; acc_waddr_reg <= 0; wdata_reg <= 0;
            carry <= 0; bit_shift <= 0; wrapped <= 0; prev_shifted_val <= 0;
            shifted_reg <= 0; first_reg <= 0;
        end
    end
endmodule
