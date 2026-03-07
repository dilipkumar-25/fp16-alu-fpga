// ============================================================
// Module     : fp16_addsub
// Function   : FP16 Pipelined Addition and Subtraction
// Pipeline   : 3 stages with Leading Zero Anticipation (LZA)
// Device     : Intel MAX 10 (10M50DAF484C7G)
// ============================================================

module fp16_addsub #(
    parameter DATA_WIDTH = 16,
    parameter EXP_WIDTH  = 5,
    parameter MANT_WIDTH = 10
)(
    input  wire                   clk,
    input  wire                   rst_n,       // active low reset
    input  wire [DATA_WIDTH-1:0]  a, b,        // FP16 operands
    input  wire                   op,          // 0=ADD 1=SUB
    input  wire                   valid_in,

    output reg  [DATA_WIDTH-1:0]  result,
    output reg                    valid_out,
    output reg                    overflow,
    output reg                    underflow
);

    localparam BIAS       = (1 << (EXP_WIDTH-1)) - 1;
    localparam EXP_ONES   = {EXP_WIDTH{1'b1}};
    localparam EXP_ZERO   = {EXP_WIDTH{1'b0}};
    localparam MANT_FULL  = MANT_WIDTH + 1;    // 11 bits with hidden 1
    localparam MANT_GUARD = MANT_FULL  + 2;    // 13 bits with guard bits
    localparam MANT_WIDE  = MANT_GUARD + 1;    // 14 bits with carry

    // Quiet NaN output = 0x7E00
    localparam NAN_OUT = {1'b0,
                          {EXP_WIDTH{1'b1}},
                          1'b1,
                          {(MANT_WIDTH-1){1'b0}}};

    // ── Unpack A ──
    wire                  sign_a = a[DATA_WIDTH-1];
    wire [EXP_WIDTH-1:0]  exp_a  = a[DATA_WIDTH-2:MANT_WIDTH];
    wire [MANT_WIDTH-1:0] mant_a = a[MANT_WIDTH-1:0];

    // Restore hidden leading 1 — denormals get 0 instead
    wire [MANT_FULL-1:0] mfull_a = (exp_a == EXP_ZERO)
                                    ? {1'b0, mant_a}
                                    : {1'b1, mant_a};

    // ── Unpack B ──
    // sign_b_raw: original sign before subtraction flip
    wire                  sign_b_raw = b[DATA_WIDTH-1];
    wire [EXP_WIDTH-1:0]  exp_b      = b[DATA_WIDTH-2:MANT_WIDTH];
    wire [MANT_WIDTH-1:0] mant_b     = b[MANT_WIDTH-1:0];

    wire [MANT_FULL-1:0] mfull_b = (exp_b == EXP_ZERO)
                                    ? {1'b0, mant_b}
                                    : {1'b1, mant_b};

    // A - B = A + (-B) — flip sign of B for SUB
    wire sign_b = sign_b_raw ^ op;

    // ── Special case flags ──
    wire a_is_zero = (exp_a == EXP_ZERO) && (mant_a == 0);
    wire b_is_zero = (exp_b == EXP_ZERO) && (mant_b == 0);
    wire a_is_nan  = (exp_a == EXP_ONES) && (mant_a != 0);
    wire b_is_nan  = (exp_b == EXP_ONES) && (mant_b != 0);
    wire a_is_inf  = (exp_a == EXP_ONES) && (mant_a == 0);
    wire b_is_inf  = (exp_b == EXP_ONES) && (mant_b == 0);

    // ══════════════════════════════════════
    // STAGE 1 — Align mantissas
    // ══════════════════════════════════════

    reg                  s1_sign_a, s1_sign_b;
    reg [EXP_WIDTH-1:0]  s1_exp_result;
    reg [MANT_GUARD-1:0] s1_mant_a, s1_mant_b;
    reg                  s1_valid;
    reg                  s1_nan, s1_inf, s1_inf_sign, s1_zero;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_valid <= 0;
        end else begin
            s1_valid <= valid_in;

            if (a_is_nan || b_is_nan) begin
                // NaN input always produces NaN output
                s1_nan  <= 1; s1_inf  <= 0; s1_zero <= 0;

            end else if (a_is_inf || b_is_inf) begin
                // Inf - Inf = NaN, otherwise propagate Inf
                if (a_is_inf && b_is_inf && (sign_a != sign_b)) begin
                    s1_nan <= 1; s1_inf <= 0;
                end else begin
                    s1_nan      <= 0;
                    s1_inf      <= 1;
                    s1_inf_sign <= a_is_inf ? sign_a : sign_b;
                end
                s1_zero <= 0;

            end else begin
                s1_nan  <= 0;
                s1_inf  <= 0;
                s1_zero <= a_is_zero && b_is_zero;

                // Align: shift smaller exponent operand right
                // larger exponent operand always goes into mant_a
                if (exp_a >= exp_b) begin
                    s1_sign_a     <= sign_a;
                    s1_sign_b     <= sign_b;
                    s1_exp_result <= exp_a;
                    s1_mant_a     <= {mfull_a, 2'b00};
                    s1_mant_b     <= {mfull_b, 2'b00} >> (exp_a - exp_b);
                end else begin
                    // B has larger exponent — swap so A is always larger
                    s1_sign_a     <= sign_b;
                    s1_sign_b     <= sign_a;
                    s1_exp_result <= exp_b;
                    s1_mant_a     <= {mfull_b, 2'b00};
                    s1_mant_b     <= {mfull_a, 2'b00} >> (exp_b - exp_a);
                end
            end
        end
    end

    // ══════════════════════════════════════
    // STAGE 2 — Add mantissas + LZA parallel
    // ══════════════════════════════════════

    reg                              s2_sign;
    reg [EXP_WIDTH-1:0]              s2_exp;
    reg [MANT_WIDE-1:0]              s2_mant;
    reg                              s2_valid;
    reg                              s2_nan, s2_inf, s2_inf_sign, s2_zero;

    // LZA predicted shift — sized to match lza output
    wire [$clog2(MANT_GUARD+1)-1:0] lza_predict;

    // LZA runs in parallel with adder below — same clock cycle
    lza #(
        .WIDTH (MANT_GUARD)
    ) u_lza (
        .a       (s1_mant_a),
        .b       (s1_mant_b),
        .lza_out (lza_predict)
    );

    // registered LZA shift for Stage 3 normalization
    reg [$clog2(MANT_GUARD+1)-1:0] s2_lza_shift;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_valid <= 0;
        end else begin
            s2_valid     <= s1_valid;
            s2_nan       <= s1_nan;
            s2_inf       <= s1_inf;
            s2_inf_sign  <= s1_inf_sign;
            s2_zero      <= s1_zero;
            s2_exp       <= s1_exp_result;
            s2_lza_shift <= lza_predict;   // register LZA prediction

            if (s1_sign_a == s1_sign_b) begin
                // Same sign — add
                s2_mant <= s1_mant_a + s1_mant_b;
                s2_sign <= s1_sign_a;
            end else begin
                // Different sign — subtract smaller from larger
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

    // ══════════════════════════════════════
    // STAGE 3 — Normalize using LZA and pack
    // ══════════════════════════════════════

    reg [MANT_WIDE-1:0] shifted_mant;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 0; result <= 0;
            overflow  <= 0; underflow <= 0;
        end else begin
            valid_out <= s2_valid;
            overflow  <= 0;
            underflow <= 0;

            if (s2_nan) begin
                result <= NAN_OUT;

            end else if (s2_inf) begin
                result <= {s2_inf_sign, EXP_ONES, {MANT_WIDTH{1'b0}}};

            end else if (s2_zero || s2_mant == 0) begin
                result <= {DATA_WIDTH{1'b0}};

            end else begin
                if (s2_mant[MANT_WIDE-1]) begin
                    // Carry out — shift right 1, increment exponent
                    if (s2_exp >= EXP_ONES - 1) begin
                        overflow <= 1;
                        result   <= {s2_sign, EXP_ONES, {MANT_WIDTH{1'b0}}};
                    end else begin
                        result <= {
                            s2_sign,
                            s2_exp + 1'b1,
                            s2_mant[MANT_WIDE-2:MANT_WIDE-1-MANT_WIDTH]
                        };
                    end
                end else begin
                    // Use LZA prediction directly — no zero counting needed
                    if (s2_lza_shift >= s2_exp) begin
                        underflow <= 1;
                        result    <= {DATA_WIDTH{1'b0}};
                    end else begin
                        shifted_mant = s2_mant << s2_lza_shift;
                        result <= {
                            s2_sign,
                            s2_exp - s2_lza_shift,
                            shifted_mant[MANT_WIDE-2:MANT_WIDE-1-MANT_WIDTH]
                        };
                    end
                end
            end
        end
    end

endmodule