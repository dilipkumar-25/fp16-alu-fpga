// -----------------------------------------------------------
// Module     : fp16_to_int.
// Function   : Converts FP16 number to 16-bit signed integer.
// Pipeline   : 2 stages.
// Examples   : 6.0  → 6
//              -3.5 → -3  (truncate toward zero)
//              0.7  →  0  (fraction → zero)
//              inf  → max integer (saturate)
// ------------------------------------------------------------

module fp16_to_int #(
    parameter DATA_WIDTH = 16,
    parameter EXP_WIDTH = 5,
    parameter MANT_WIDTH = 10,
    parameter INT_WIDTH = 16   // output integer width.
)(
    input wire clk, rst_n, valid_in,
    input wire [DATA_WIDTH-1:0] fp_in,

    output reg [INT_WIDTH-1:0] int_out,
    output reg valid_out, overflow, is_zero
);
    // Local parameters.
    localparam BIAS = (1 << (EXP_WIDTH-1)) - 1;   // 15.
    localparam EXP_ONES = {EXP_WIDTH{1'b1}};   // 11111.
    localparam EXP_ZERO = {EXP_WIDTH{1'b0}};   // 00000.

    // Maximum positive integer for INT_WIDTH=16.
    // = 0111111111111111 = 32767.
    localparam MAX_POS = {1'b0, {(INT_WIDTH-1){1'b1}}};

    // Maximum negative integer (most negative).
    // = 1000000000000000 = -32768.
    localparam MAX_NEG = {1'b1, {(INT_WIDTH-1){1'b0}}};

    // Unpack FP16 input.
    wire sign_in = fp_in[DATA_WIDTH-1];
    wire [EXP_WIDTH-1:0] exp_in = fp_in[DATA_WIDTH-2:MANT_WIDTH];
    wire [MANT_WIDTH-1:0] mant_in = fp_in[MANT_WIDTH-1:0];
    wire [MANT_WIDTH:0] mfull = (exp_in == EXP_ZERO) ? {1'b0, mant_in} : {1'b1, mant_in};

    // Special case detection.
    wire in_is_nan = (exp_in == EXP_ONES) && (mant_in != 0);
    wire in_is_inf = (exp_in == EXP_ONES) && (mant_in == 0);
    wire in_is_zero = (exp_in == EXP_ZERO) && (mant_in == 0);

    // Actual exponent (remove bias).
    // Use signed arithmetic to handle negative exponents.
    wire signed [EXP_WIDTH:0] actual_exp = $signed({1'b0, exp_in}) - BIAS;
    // actual_exp is 6 bits signed to handle range -15 to +16.

    // ----------------------------------------------------------
    // PIPELINE STAGE 1 — Compute shift amount and shifted value.
    // ----------------------------------------------------------

    reg s1_sign, s1_valid, s1_overflow, s1_zero;
    reg [INT_WIDTH-1:0] s1_value;   // shifted integer value.

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_valid <= 0;
        end else begin
            s1_valid <= valid_in;
            s1_sign <= sign_in;
            s1_overflow <= 0;
            s1_zero <= 0;

            // Handle special cases.
            if (in_is_nan || in_is_inf) begin
                // NaN or Inf -> saturate to max integer.
                s1_overflow <= 1;
                s1_value <= MAX_POS;

            end else if (in_is_zero) begin
                // Zero input -> zero output.
                s1_zero <= 1;
                s1_value <= 0;

            end else if (actual_exp < 0) begin
                // Exponent negative -> number is pure fraction.
                // Example: 0.75 has actual_exp = -1.
                // Integer part = 0.
                s1_zero <= 1;
                s1_value <= 0;

            end else if (actual_exp >= INT_WIDTH-1) begin
                // Exponent too large -> overflow.
                // Example: actual_exp=16 means value >= 65536.
                // which is too large for 16-bit signed integer.
                s1_overflow <= 1;
                s1_value <= MAX_POS;

            end else begin
                s1_value <= mfull << actual_exp;
            end
        end
    end

    // -----------------------------------------
    // PIPELINE STAGE 2 — Apply sign and output.
    // -----------------------------------------

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 0;
            int_out <= 0;
            overflow <= 0;
            is_zero <= 0;
        end else begin
            valid_out <= s1_valid;
            overflow <= s1_overflow;
            is_zero <= s1_zero;

            if (s1_overflow) begin
                // Saturate: positive overflow -> MAX_POS.
                // Saturate: negative overflow -> MAX_NEG.
                int_out <= s1_sign ? MAX_NEG : MAX_POS;

            end else if (s1_zero) begin
                int_out <= 0;

            end else begin
                // Apply sign using two's complement for negative.
                // Two's complement: negate = invert all bits + 1.
                if (s1_sign)
                    int_out <= (~s1_value) + 1'b1;   // negative.
                else
                    int_out <= s1_value;   // positive.
            end
        end
    end

endmodule

