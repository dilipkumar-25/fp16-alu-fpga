// -----------------------------------------------
// Module     : fp16_mul.
// Function   : FP16 Pipelined Multiplication.
// Parameters : DATA_WIDTH, EXP_WIDTH, MANT_WIDTH.
// Pipeline   : 3 stages.
// -----------------------------------------------

module fp16_mul #(
    parameter DATA_WIDTH = 16,
    parameter EXP_WIDTH = 5,
    parameter MANT_WIDTH = 10
)(
    input wire clk, rst_n, valid_in,
    input wire [DATA_WIDTH-1:0] a, b,

    output reg [DATA_WIDTH-1:0] result,
    output reg valid_out, overflow, underflow
);

    localparam BIAS = (1 << (EXP_WIDTH-1)) - 1;   // 15 for FP16.
    localparam EXP_ONES = {EXP_WIDTH{1'b1}};
    localparam EXP_ZERO = {EXP_WIDTH{1'b0}};
    localparam NAN_OUT = {1'b0,{EXP_WIDTH{1'b1}},1'b1,{(MANT_WIDTH-1){1'b0}}};

    // Unpack A.
    wire sign_a = a[DATA_WIDTH-1];
    wire [EXP_WIDTH-1:0] exp_a = a[DATA_WIDTH-2:MANT_WIDTH];
    wire [MANT_WIDTH-1:0] mant_a = a[MANT_WIDTH-1:0];
    wire [MANT_WIDTH:0] mfull_a = (exp_a == EXP_ZERO) ? {1'b0, mant_a} : {1'b1, mant_a};

    // Unpack B.
    wire sign_b = b[DATA_WIDTH-1];
    wire [EXP_WIDTH-1:0] exp_b = b[DATA_WIDTH-2:MANT_WIDTH];
    wire [MANT_WIDTH-1:0] mant_b = b[MANT_WIDTH-1:0];
    wire [MANT_WIDTH:0] mfull_b = (exp_b == EXP_ZERO) ? {1'b0, mant_b} : {1'b1, mant_b};

    // Special case detection.
    wire a_is_zero = (exp_a == EXP_ZERO) && (mant_a == 0);
    wire b_is_zero = (exp_b == EXP_ZERO) && (mant_b == 0);
    wire a_is_nan = (exp_a == EXP_ONES) && (mant_a != 0);
    wire b_is_nan = (exp_b == EXP_ONES) && (mant_b != 0);
    wire a_is_inf = (exp_a == EXP_ONES) && (mant_a == 0);
    wire b_is_inf = (exp_b == EXP_ONES) && (mant_b == 0);

    // Result sign (XOR of input signs).
    wire result_sign = sign_a ^ sign_b;

    // ----------------------------------------------------------
    // PIPELINE STAGE 1 — Compute Sign, Exponent, Start Multiply.
    // ----------------------------------------------------------

    reg s1_sign, s1_valid, s1_nan, s1_inf, s1_zero;
    reg [EXP_WIDTH+1:0] s1_exp;   // 2 extra bits to detect overflow.
    reg [MANT_WIDTH:0] s1_mant_a, s1_mant_b;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_valid <= 0;
        end else begin
            s1_valid <= valid_in;

            // Special cases.
            if (a_is_nan || b_is_nan) begin
                // NaN input -> NaN output.
                s1_nan <= 1;
                s1_inf <= 0;
                s1_zero <= 0;

            end else if ((a_is_inf && b_is_zero) || (a_is_zero && b_is_inf)) begin
                // Inf × 0 = NaN (undefined).
                s1_nan <= 1;
                s1_inf <= 0;
                s1_zero <= 0;

            end else if (a_is_inf || b_is_inf) begin
                // Inf × anything = Inf.
                s1_nan <= 0;
                s1_inf <= 1;
                s1_zero <= 0;

            end else if (a_is_zero || b_is_zero) begin
                // anything × 0 = 0.
                s1_nan <= 0;
                s1_inf <= 0;
                s1_zero <= 1;

            end else begin
                s1_nan <= 0;
                s1_inf <= 0;
                s1_zero <= 0;

                // Normal multiplication setup.
                s1_sign <= result_sign;

                // Add exponents and subtract one bias.
                // Use extra bits to detect overflow/underflow.
                s1_exp <= (exp_a + exp_b) - BIAS;

                // Pass mantissas to stage 2 for multiplication.
                s1_mant_a <= mfull_a;
                s1_mant_b <= mfull_b;
            end
        end
    end

    // --------------------------------------
    // PIPELINE STAGE 2 — Multiply Mantissas.
    // --------------------------------------

    reg s2_sign, s2_valid, s2_nan, s2_inf, s2_zero;
    reg [EXP_WIDTH+1:0] s2_exp;
    reg [(MANT_WIDTH+1)*2-1:0] s2_product;   // 22 bits for 11×11.

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_valid <= 0;
        end else begin
            s2_valid <= s1_valid;
            s2_sign <= s1_sign;
            s2_exp <= s1_exp;
            s2_nan <= s1_nan;
            s2_inf <= s1_inf;
            s2_zero <= s1_zero;

            // Multiply the two 11-bit mantissas.
            // 11 × 11 = 22 bit result.
            s2_product <= s1_mant_a * s1_mant_b;
        end
    end

    // --------------------------------------
    // PIPELINE STAGE 3 — Normalize and Pack.
    // --------------------------------------

    reg [(MANT_WIDTH+1)*2-1:0] norm_product;

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
                result <= {s2_sign, EXP_ONES, {MANT_WIDTH{1'b0}}};

            end else if (s2_zero) begin
                result <= {s2_sign, {DATA_WIDTH-1{1'b0}}};

            end else begin

                // Check exponent overflow/underflow.
                if ($signed(s2_exp) <= 0) begin
                    // Exponent too small -> underflow → zero.
                    underflow <= 1;
                    result <= {s2_sign, {(DATA_WIDTH-1){1'b0}}};

                end else if (s2_exp >= EXP_ONES) begin
                    // Exponent too large -> overflow -> infinity.
                    overflow <= 1;
                    result <= {s2_sign, EXP_ONES, {MANT_WIDTH{1'b0}}};

                end else begin
                    // Normal case: normalize the product.
                    // 11×11 product = 22 bits.
                    // Top bit position is either 21 or 20.
                    // (1.xxx × 1.xxx = 1x.xxxx or 1.xxxx).

                    if (s2_product[(2*MANT_WIDTH)+1]) begin
                        // Product bit 21 is 1 -> result is 1x.xxxx
                        // Shift right by 1, increment exponent.
                        if (s2_exp + 1 >= EXP_ONES) begin
                            overflow <= 1;
                            result <= {s2_sign, EXP_ONES, {MANT_WIDTH{1'b0}}};
                        end else begin
                            result <= {s2_sign, s2_exp[EXP_WIDTH-1:0] + 1'b1, s2_product[2*MANT_WIDTH : MANT_WIDTH+1]};
                        end

                    end else begin
                        // Product bit 20 is 1 → result is 1.xxxx
                        // No shift needed.
                        result <= {s2_sign, s2_exp[EXP_WIDTH-1:0], s2_product[2*MANT_WIDTH-1 : MANT_WIDTH]};
                    end
                end
            end
        end
    end

endmodule


