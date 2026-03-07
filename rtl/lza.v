// ---------------------------------------------------------------------------
// Module     : lza
// Function   : Leading Zero Anticipator
// Pipeline   : Combinational (no clock)
// Description: Predicts normalization shift amount in parallel with addition.
//              Eliminates post-addition zero counting from the critical path.
// ---------------------------------------------------------------------------

module lza #(
    parameter WIDTH = 14   // mantissa width including guard bits
)(
    input wire [WIDTH-1:0] a,   // larger aligned mantissa
    input wire [WIDTH-1:0] b,   // smaller aligned mantissa
    output reg [$clog2(WIDTH+1)-1:0] lza_out   // holds shift amount 0 to WIDTH-1 safely for any WIDTH
);
    // T=transition, G=generate, Z=zero — LZA basis vectors
    wire [WIDTH-1:0] t_vec = a ^ b;
    wire [WIDTH-1:0] g_vec = a & b;
    wire [WIDTH-1:0] z_vec = (~a) & (~b);

    // Prediction vector — f[i]=1 means leading 1 is at bit i
    wire [WIDTH-1:0] f_vec;

    // MSB boundary condition
    assign f_vec[WIDTH-1] = t_vec[WIDTH-1];

    // LZA recurrence for remaining bits — all run in parallel
    genvar i;
    generate
        for (i = 0; i < WIDTH-1; i = i + 1) begin : lza_gen
            assign f_vec[i] = t_vec[i] ^ (g_vec[i+1] | z_vec[i+1]);
        end
    endgenerate

    // Scan f_vec from MSB to find predicted leading 1 position
    integer j;
    always @(*) begin
        lza_out = WIDTH - 1;   // default
        for (j = WIDTH-1; j >= 0; j = j - 1) begin
            if (f_vec[j]) lza_out = (WIDTH - 1) - j;
        end
    end

endmodule