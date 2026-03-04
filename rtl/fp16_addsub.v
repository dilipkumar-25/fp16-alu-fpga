// Module     : fp16_addsub.
// Function   : FP16 Pipelined Addition and Subtraction.
// Parameters : DATA_WIDTH, EXP_WIDTH, MANT_WIDTH.
// Pipeline   : 3 internal stages + output register.
// -----------------------------------------------------

module fp16_addsub #(
    parameter DATA_WIDTH = 16,
    parameter EXP_WIDTH = 5,
    parameter MANT_WIDTH = 10
)(
    input wire clk,
    input wire rst_n,                         // active low reset.
    input wire [DATA_WIDTH-1:0] a,            // operand A.
    input wire [DATA_WIDTH-1:0] b,            // operand B.
    input wire op,                            // 0=add, 1=subtract.
    input wire valid_in,                      // input is valid.

    output reg [DATA_WIDTH-1:0] result,       // FP16 result.
    output reg valid_out,                     // output is valid.
    output reg overflow,                      // overflow flag.
    output reg underflow                      // underflow flag.
);
    // Local parameters.
    localparam BIAS = (1 << (EXP_WIDTH-1)) - 1;   // 15 for FP16.
    localparam EXP_ONES = {EXP_WIDTH{1'b1}};
    localparam EXP_ZERO = {EXP_WIDTH{1'b0}};

    // Unpack A.
    wire sign_a = a[DATA_WIDTH-1];
    wire [EXP_WIDTH-1:0] exp_a = a[DATA_WIDTH-2:MANT_WIDTH];
    wire [MANT_WIDTH-1:0] mant_a = a[MANT_WIDTH-1:0];
    wire [MANT_WIDTH:0] mfull_a = (exp_a == EXP_ZERO) ? {1'b0, mant_a} : {1'b1, mant_a};

    // Unpack B.
    wire sign_b_raw = b[DATA_WIDTH-1];
    wire [EXP_WIDTH-1:0] exp_b = b[DATA_WIDTH-2:MANT_WIDTH];
    wire [MANT_WIDTH-1:0] mant_b = b[MANT_WIDTH-1:0];
    wire [MANT_WIDTH:0] mfull_b = (exp_b == EXP_ZERO) ? {1'b0, mant_b} : {1'b1, mant_b};

    // For subtraction, flip sign of B (A - B = A + (-B)).
    wire sign_b = sign_b_raw ^ op;

    // Special case detection.
    wire a_is_zero = (exp_a == EXP_ZERO) && (mant_a == 0);
    wire b_is_zero = (exp_b == EXP_ZERO) && (mant_b == 0);
    wire a_is_nan  = (exp_a == EXP_ONES) && (mant_a != 0);
    wire b_is_nan  = (exp_b == EXP_ONES) && (mant_b != 0);
    wire a_is_inf  = (exp_a == EXP_ONES) && (mant_a == 0);
    wire b_is_inf  = (exp_b == EXP_ONES) && (mant_b == 0);

    // NaN output pattern.
    localparam NAN_OUT = {1'b0, {EXP_WIDTH{1'b1}}, 1'b1, {(MANT_WIDTH-1){1'b0}}};

    // ----------------------------------------------------------
    // PIPELINE STAGE 1 REGISTERS — Align.
    // ----------------------------------------------------------
                                    
    reg s1_sign_a, s1_sign_b;
    reg [EXP_WIDTH-1:0] s1_exp_a, s1_exp_b;
    reg [MANT_WIDTH+2:0] s1_mant_a, s1_mant_b;   // extra bits for shifting.
    reg [EXP_WIDTH-1:0] s1_exp_result;
    reg s1_valid;
    reg s1_nan, s1_inf, s1_inf_sign;
    reg s1_zero;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_valid <= 0;
        end else begin
            s1_valid <= valid_in;

            // Handle special cases.
            if (a_is_nan || b_is_nan) begin
                s1_nan <= 1;
                s1_inf <= 0;
                s1_zero <= 0;
            end else if (a_is_inf || b_is_inf) begin
                // inf - inf = NaN.
                if (a_is_inf && b_is_inf && (sign_a != sign_b)) begin
                    s1_nan <= 1;
                    s1_inf <= 0;
                end else begin
                    s1_nan <= 0;
                    s1_inf <= 1;
                    s1_inf_sign <= a_is_inf ? sign_a : sign_b;
                end
                s1_zero <= 0;
            end else begin
                s1_nan <= 0;
                s1_inf <= 0;
                s1_zero <= a_is_zero && b_is_zero;

                // Align mantissas.
                // Compare exponents, shift smaller mantissa right.
                if (exp_a >= exp_b) begin
                    s1_sign_a <= sign_a;
                    s1_sign_b <= sign_b;
                    s1_exp_result <= exp_a;
                    s1_mant_a <= {mfull_a, 2'b00};   // add guard bits.
                    // shift B right by difference.
                    s1_mant_b <= {mfull_b, 2'b00} >> (exp_a - exp_b);
                end else begin
                    s1_sign_a <= sign_b;
                    s1_sign_b <= sign_a;
                    s1_exp_result <= exp_b;
                    s1_mant_a <= {mfull_b, 2'b00};
                    s1_mant_b <= {mfull_a, 2'b00} >> (exp_b - exp_a);
                end
            end
        end
    end

    // ----------------------------------------------
    // PIPELINE STAGE 2 — Add or Subtract Mantissas.
    // ----------------------------------------------

    reg s2_sign;
    reg [EXP_WIDTH-1:0] s2_exp;
    reg [MANT_WIDTH+3:0] s2_mant;   // one extra bit for carry.
    reg s2_valid;
    reg s2_nan, s2_inf, s2_inf_sign, s2_zero;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_valid <= 0;
        end else begin
            s2_valid <= s1_valid;
            s2_nan <= s1_nan;
            s2_inf <= s1_inf;
            s2_inf_sign <= s1_inf_sign;
            s2_zero <= s1_zero;
            s2_exp <= s1_exp_result;

            if (s1_sign_a == s1_sign_b) begin
                // Same sign -> Add mantissas.
                s2_mant <= s1_mant_a + s1_mant_b;
                s2_sign <= s1_sign_a;
            end else begin
                // Different sign -> Subtract.
                if (s1_mant_a >= s1_mant_b) begin
                    s2_mant <= s1_mant_a - s1_mant_b;
                    s2_sign <= s1_sign_a;
                end else begin
                    s2_mant <= s1_mant_b - s1_mant_a;
                    s2_sign <= s1_sign_b;
                end
            end
        end
    end
    // ---------------------------------------------
    // PIPELINE STAGE 3 — Normalize and Pack Result.
    // ---------------------------------------------

    // Leading zero counter for normalization.
    integer lzc;   // leading zero count.
    reg [MANT_WIDTH+3:0] shifted_mant;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 0;
            result <= 0;
            overflow <= 0;
            underflow <= 0;
        end else begin
            valid_out <= s2_valid;
            overflow <= 0;
            underflow <= 0;

            // Handle special cases.
            if (s2_nan) begin
                result <= NAN_OUT;
            end else if (s2_inf) begin
                result <= {s2_inf_sign, EXP_ONES, {MANT_WIDTH{1'b0}}};
            end else if (s2_zero || s2_mant == 0) begin
                result <= {DATA_WIDTH{1'b0}};
            end else begin

                // Normalize.
                if (s2_mant[MANT_WIDTH+3]) begin
                    // Carry out — shift right by 1, increment exponent.
                    if (s2_exp == EXP_ONES - 1) begin
                        // Overflow -> Infinity.
                        overflow <= 1;
                        result   <= {s2_sign, EXP_ONES, {MANT_WIDTH{1'b0}}};
                    end else begin
                        result <= {
                            s2_sign,
                            s2_exp + 1'b1,
                            s2_mant[MANT_WIDTH+2:3]   // drop LSB (rounding).
                        };
                    end

                end else begin
                    // No carry — find leading 1 and normalize.
                    // Find how many bits to shift left.
                    lzc = 0;
                    if (s2_mant[MANT_WIDTH+2]) lzc = 0;
                    else if (s2_mant[MANT_WIDTH+1]) lzc = 1;
                    else if (s2_mant[MANT_WIDTH]) lzc = 2;
                    else if (s2_mant[MANT_WIDTH-1]) lzc = 3;
                    else if (s2_mant[MANT_WIDTH-2]) lzc = 4;
                    else if (s2_mant[MANT_WIDTH-3]) lzc = 5;
                    else if (s2_mant[MANT_WIDTH-4]) lzc = 6;
                    else if (s2_mant[MANT_WIDTH-5]) lzc = 7;
                    else if (s2_mant[MANT_WIDTH-6]) lzc = 8;
                    else if (s2_mant[MANT_WIDTH-7]) lzc = 9;
                    else if (s2_mant[MANT_WIDTH-8]) lzc = 10;
                    else lzc = 11;

                    if (lzc >= s2_exp) begin
                        // Underflow -> Zero.
                        underflow <= 1;
                        result    <= {DATA_WIDTH{1'b0}};
                    end else begin
                        shifted_mant = s2_mant << lzc;
                        result <= {s2_sign, s2_exp - lzc, shifted_mant[MANT_WIDTH+1:2]};
                    end
                end
            end
        end
    end

endmodule
