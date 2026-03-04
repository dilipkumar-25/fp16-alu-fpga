// Module     : fp16_unpack.
// Function   : Extracts sign, exponent, mantissa from FP input.
//              Detects special cases: zero, inf, NaN, denormal.
// Parameters : DATA_WIDTH -> total bits (default 16).
//              EXP_WIDTH  -> exponent bits (default 5).
//              MANT_WIDTH -> mantissa bits (default 10).
// Stage      : Pipeline Stage 1.
// ------------------------------------------------------------

module fp16_unpack #(
    parameter DATA_WIDTH = 16,   // total FP word width.
    parameter EXP_WIDTH = 5,   // exponent field width.
    parameter MANT_WIDTH = 10   // mantissa field width.
)(
    input wire [DATA_WIDTH-1:0] fp_in,    // FP input.

    output wire sign,   // sign bit.
    output wire [EXP_WIDTH-1:0] exponent,   // biased exponent.
    output wire [MANT_WIDTH-1:0] mantissa,   // raw mantissa.
    output wire [MANT_WIDTH:0] mantissa_full,   // mantissa + implicit 1.

    output wire is_zero,
    output wire is_inf,
    output wire is_nan,
    output wire is_denormal
);
    // Local parameters (calculated automatically).
    localparam EXP_ONES = {EXP_WIDTH{1'b1}};   // all 1s in exponent = 11111.
    localparam EXP_ZERO = {EXP_WIDTH{1'b0}};   // all 0s in exponent = 00000.
    localparam MANT_ZERO = {MANT_WIDTH{1'b0}};   // all 0s in mantissa.

    // Extract fields.
    assign sign = fp_in[DATA_WIDTH-1];
    assign exponent = fp_in[DATA_WIDTH-2 : MANT_WIDTH];
    assign mantissa = fp_in[MANT_WIDTH-1 : 0];

    // Add implicit leading 1.
    assign mantissa_full = (exponent == EXP_ZERO)
                           ? {1'b0, mantissa}   // denormal
                           : {1'b1, mantissa};   // normal

    // Special case detection.
    assign is_zero = (exponent == EXP_ZERO) && (mantissa == MANT_ZERO);
    assign is_denormal = (exponent == EXP_ZERO) && (mantissa != MANT_ZERO);
    assign is_inf = (exponent == EXP_ONES) && (mantissa == MANT_ZERO);
    assign is_nan = (exponent == EXP_ONES) && (mantissa != MANT_ZERO);

endmodule

