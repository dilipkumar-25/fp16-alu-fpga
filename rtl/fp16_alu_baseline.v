// ----------------------------------------------------------
// Module  : fp16_alu_baseline.
// Purpose : Non-optimized baseline with ALL 12 operations.
//           No pipelining, no valid gating, no shared logic.
//           Used to measure optimization improvement.
// ----------------------------------------------------------

module fp16_alu_baseline #(
    parameter DATA_WIDTH = 16,
    parameter EXP_WIDTH = 5,
    parameter MANT_WIDTH = 10,
    parameter OP_WIDTH = 4
)(
    input wire clk, rst_n, valid_in,
    input wire [DATA_WIDTH-1:0] a, b,
    input wire [OP_WIDTH-1:0] op_sel,

    output reg [DATA_WIDTH-1:0] result,
    output reg valid_out, overflow, underflow,
    output reg [1:0] cmp_flags
);
    // Local parameters.
    localparam BIAS = (1 << (EXP_WIDTH-1)) - 1;
    localparam EXP_ONES = {EXP_WIDTH{1'b1}};
    localparam EXP_ZERO = {EXP_WIDTH{1'b0}};
    localparam NAN_OUT = {1'b0,{EXP_WIDTH{1'b1}},1'b1,{(MANT_WIDTH-1){1'b0}}};
    localparam MAX_POS = {1'b0,{(DATA_WIDTH-1){1'b1}}};
    localparam MAX_NEG = {1'b1,{(DATA_WIDTH-1){1'b0}}};

    // Unpack A.
    wire sign_a = a[DATA_WIDTH-1];
    wire [EXP_WIDTH-1:0] exp_a = a[DATA_WIDTH-2:MANT_WIDTH];
    wire [MANT_WIDTH-1:0] mant_a = a[MANT_WIDTH-1:0];
    wire [MANT_WIDTH:0] mfull_a = (exp_a==EXP_ZERO) ? {1'b0,mant_a} : {1'b1,mant_a};

    // Unpack B.
    wire sign_b = b[DATA_WIDTH-1];
    wire [EXP_WIDTH-1:0] exp_b = b[DATA_WIDTH-2:MANT_WIDTH];
    wire [MANT_WIDTH-1:0] mant_b = b[MANT_WIDTH-1:0];
    wire [MANT_WIDTH:0] mfull_b = (exp_b==EXP_ZERO) ? {1'b0,mant_b} : {1'b1,mant_b};

    // Special cases.
    wire a_is_zero = (exp_a==EXP_ZERO)&&(mant_a==0);
    wire b_is_zero = (exp_b==EXP_ZERO)&&(mant_b==0);
    wire a_is_nan = (exp_a==EXP_ONES)&&(mant_a!=0);
    wire b_is_nan = (exp_b==EXP_ONES)&&(mant_b!=0);
    wire a_is_inf = (exp_a==EXP_ONES)&&(mant_a==0);
    wire b_is_inf = (exp_b==EXP_ONES)&&(mant_b==0);

    // Separate unpack for B (no sharing with A).
    // Baseline deliberately does NOT share logic.
    wire sign_a2 = a[DATA_WIDTH-1];
    wire [EXP_WIDTH-1:0] exp_a2 = a[DATA_WIDTH-2:MANT_WIDTH];
    wire [MANT_WIDTH-1:0] mant_a2 = a[MANT_WIDTH-1:0];
    wire [MANT_WIDTH:0] mfull_a2 = (exp_a2==EXP_ZERO) ? {1'b0,mant_a2} : {1'b1,mant_a2};

    wire sign_b2 = b[DATA_WIDTH-1];
    wire [EXP_WIDTH-1:0] exp_b2 = b[DATA_WIDTH-2:MANT_WIDTH];
    wire [MANT_WIDTH-1:0] mant_b2 = b[MANT_WIDTH-1:0];
    wire [MANT_WIDTH:0] mfull_b2 = (exp_b2==EXP_ZERO) ? {1'b0,mant_b2} : {1'b1,mant_b2};

    // Comparison logic (NOT shared — duplicated).
    wire sign_a3 = a[DATA_WIDTH-1];
    wire sign_b3 = b[DATA_WIDTH-1];
    wire [DATA_WIDTH-2:0] mag_a = a[DATA_WIDTH-2:0];
    wire [DATA_WIDTH-2:0] mag_b = b[DATA_WIDTH-2:0];
    wire a_gt_b2 = (!sign_a3 && !sign_b3 && mag_a > mag_b) ||
        ( sign_a3 &&  sign_b3 && mag_a < mag_b) ||
        (!sign_a3 &&  sign_b3);
    wire a_zero2 = (a[DATA_WIDTH-2:0]==0);
    wire b_zero2 = (b[DATA_WIDTH-2:0]==0);
    wire a_eq_b2 = (a==b)||(a_zero2&&b_zero2);

    // Intermediate registers.
    reg [MANT_WIDTH+2:0] mant_a_al, mant_b_al;
    reg [MANT_WIDTH+3:0] sum_mant;
    reg [EXP_WIDTH-1:0] res_exp;
    reg res_sign;
    reg [(MANT_WIDTH+1)*2-1:0] product;
    reg [DATA_WIDTH-1:0] comb_result;
    reg comb_of, comb_uf;
    reg [1:0] comb_cmp;
    integer lzc;
    reg [MANT_WIDTH+3:0] shifted;

    // Separate intermediate for mul (not shared).
    reg [MANT_WIDTH+2:0] mant_a_al2, mant_b_al2;
    reg [MANT_WIDTH+3:0] sum_mant2;
    reg [EXP_WIDTH-1:0] res_exp2;
    reg res_sign2;
    integer lzc2;
    reg [MANT_WIDTH+3:0] shifted2;

    // fp2int intermediates (not shared).
    wire signed [EXP_WIDTH:0] actual_exp3 = $signed({1'b0,exp_a}) - BIAS;
    reg [DATA_WIDTH-1:0] int_val;

    // Fully combinational — no pipeline.
    always @(*) begin
        comb_result = 0;
        comb_of = 0;
        comb_uf = 0;
        comb_cmp = 0;

        // Initialise all intermediates.
        mant_a_al = 0; mant_b_al = 0;
        mant_a_al2 = 0; mant_b_al2 = 0;
        sum_mant = 0; sum_mant2 = 0;
        res_exp = 0; res_exp2 = 0;
        res_sign = 0; res_sign2 = 0;
        product = 0;
        lzc = 0; lzc2 = 0;
        shifted = 0; shifted2 = 0;
        int_val = 0;

        case (op_sel)

            // ----
            // ADD.
            // ----
            4'b0000: begin
                if (a_is_nan || b_is_nan) begin
                    comb_result = NAN_OUT;
                end else if (a_is_inf || b_is_inf) begin
                    if (a_is_inf&&b_is_inf&&(sign_a != sign_b))
                        comb_result = NAN_OUT;
                    else
                        comb_result = {(a_is_inf ? sign_a : sign_b),EXP_ONES,{MANT_WIDTH{1'b0}}};
                end else if (a_is_zero && b_is_zero) begin
                    comb_result = 0;
                end else begin
                    if (exp_a >= exp_b) begin
                        res_exp = exp_a;
                        res_sign = sign_a;
                        mant_a_al = {mfull_a,2'b00};
                        mant_b_al = {mfull_b,2'b00} >>(exp_a-exp_b);
                    end else begin
                        res_exp = exp_b;
                        res_sign = sign_b;
                        mant_a_al = {mfull_b,2'b00};
                        mant_b_al = {mfull_a,2'b00} >>(exp_b-exp_a);
                    end
                    if (sign_a == sign_b) begin
                        sum_mant = mant_a_al + mant_b_al;
                    end else begin
                        if (mant_a_al >= mant_b_al) begin
                            sum_mant = mant_a_al - mant_b_al;
                        end else begin
                            sum_mant = mant_b_al - mant_a_al;
                            res_sign = ~res_sign;
                        end
                    end
                    if (sum_mant==0) begin
                        comb_result = 0;
                    end else if (sum_mant[MANT_WIDTH+3]) begin
                        comb_result = {res_sign,res_exp+1,sum_mant[MANT_WIDTH+2:3]};
                    end else begin
                        lzc=0;
                        if (sum_mant[MANT_WIDTH+2]) lzc=0;
                        else if (sum_mant[MANT_WIDTH+1]) lzc=1;
                        else if (sum_mant[MANT_WIDTH]) lzc=2;
                        else if (sum_mant[MANT_WIDTH-1]) lzc=3;
                        else if (sum_mant[MANT_WIDTH-2]) lzc=4;
                        else if (sum_mant[MANT_WIDTH-3]) lzc=5;
                        else if (sum_mant[MANT_WIDTH-4]) lzc=6;
                        else if (sum_mant[MANT_WIDTH-5]) lzc=7;
                        else if (sum_mant[MANT_WIDTH-6]) lzc=8;
                        else if (sum_mant[MANT_WIDTH-7]) lzc=9;
                        else if (sum_mant[MANT_WIDTH-8]) lzc=10;
                        else lzc=11;
                        shifted = sum_mant << lzc;
                        comb_result = {res_sign,res_exp-lzc,shifted[MANT_WIDTH+2:3]};
                    end
                end
            end

            // -----------------------------------
            // SUB (duplicate adder — no sharing).
            // -----------------------------------
            4'b0001: begin
                if (a_is_nan || b_is_nan) begin
                    comb_result = NAN_OUT;
                end else if (a_is_inf || b_is_inf) begin
                    comb_result = {(a_is_inf ? sign_a : ~sign_b),EXP_ONES,{MANT_WIDTH{1'b0}}};
                end else if (a_is_zero && b_is_zero) begin
                    comb_result = 0;
                end else begin
                    if (exp_a >= exp_b) begin
                        res_exp2 = exp_a;
                        res_sign2 = sign_a;
                        mant_a_al2 = {mfull_a2,2'b00};
                        mant_b_al2 = {mfull_b2,2'b00} >>(exp_a-exp_b);
                    end else begin
                        res_exp2 = exp_b;
                        res_sign2 = sign_b;
                        mant_a_al2 = {mfull_b2,2'b00};
                        mant_b_al2 = {mfull_a2,2'b00} >>(exp_b-exp_a);
                    end

                    // Subtraction: flip B sign.
                    if (sign_a != sign_b) begin
                        sum_mant2 = mant_a_al2 + mant_b_al2;
                    end else begin
                        if (mant_a_al2 >= mant_b_al2)
                            sum_mant2 = mant_a_al2 - mant_b_al2;
                        else begin
                            sum_mant2 = mant_b_al2 - mant_a_al2;
                            res_sign2 = ~res_sign2;
                        end
                    end
                    if (sum_mant2==0) begin
                        comb_result = 0;
                    end else if (sum_mant2[MANT_WIDTH+3]) begin
                        comb_result = {res_sign2,res_exp2+1,sum_mant2[MANT_WIDTH+2:3]};
                    end else begin
                        lzc2=0;
                        if (sum_mant2[MANT_WIDTH+2]) lzc2=0;
                        else if (sum_mant2[MANT_WIDTH+1]) lzc2=1;
                        else if (sum_mant2[MANT_WIDTH]) lzc2=2;
                        else if (sum_mant2[MANT_WIDTH-1]) lzc2=3;
                        else if (sum_mant2[MANT_WIDTH-2]) lzc2=4;
                        else if (sum_mant2[MANT_WIDTH-3]) lzc2=5;
                        else if (sum_mant2[MANT_WIDTH-4]) lzc2=6;
                        else if (sum_mant2[MANT_WIDTH-5]) lzc2=7;
                        else if (sum_mant2[MANT_WIDTH-6]) lzc2=8;
                        else if (sum_mant2[MANT_WIDTH-7]) lzc2=9;
                        else if (sum_mant2[MANT_WIDTH-8]) lzc2=10;
                        else lzc2=11;
                        shifted2 = sum_mant2 << lzc2;
                        comb_result = {res_sign2,res_exp2-lzc2,shifted2[MANT_WIDTH+2:3]};
                    end
                end
            end

            // ----
            // MUL.
            // ----
            4'b0010: begin
                if (a_is_nan || b_is_nan) begin
                    comb_result = NAN_OUT;
                end else if ((a_is_inf && b_is_zero)||
                             (a_is_zero && b_is_inf)) begin
                    comb_result = NAN_OUT;
                end else if (a_is_inf || b_is_inf) begin
                    comb_result = {sign_a^sign_b,EXP_ONES,{MANT_WIDTH{1'b0}}};
                end else if (a_is_zero || b_is_zero) begin
                    comb_result = 0;
                end else begin
                    product = mfull_a * mfull_b;
                    res_sign = sign_a ^ sign_b;
                    res_exp = exp_a + exp_b - BIAS;
                    if (product[(MANT_WIDTH+1)*2-1]) begin
                        comb_result = {res_sign,res_exp+1,product[(MANT_WIDTH+1)*2-2 : MANT_WIDTH+1]};
                    end else begin
                        comb_result = {res_sign,res_exp,product[(MANT_WIDTH+1)*2-2 : MANT_WIDTH+1]};
                    end
                end
            end

            // ----
            // AND.
            // ----
            4'b0011: comb_result = a & b;

            // ---
            // OR.
            // ---
            4'b0100: comb_result = a | b;

            // ----
            // XOR.
            // ----
            4'b0101: comb_result = a ^ b;

            // ---------------------------------
            // MIN (no shared comparison logic).
            // ---------------------------------
            4'b0110: begin
                comb_result = a_gt_b2 ? b : a;
            end

            // ----
            // ABS.
            // ----
            4'b0111: begin
                comb_result = {1'b0, a[DATA_WIDTH-2:0]};
            end

            // ----
            // NEG.
            // ----
            4'b1000: begin
                comb_result = {~a[DATA_WIDTH-1],a[DATA_WIDTH-2:0]};
            end

            // ---------------------------------------------
            // CMP (separate comparison logic — no sharing).
            // ---------------------------------------------
            4'b1001: begin
                comb_result = 0;
                comb_cmp[1] = a_gt_b2;
                comb_cmp[0] = a_eq_b2;
            end

            // -------------------------------------
            // MAX (separate from MIN — no sharing).
            // -------------------------------------
            4'b1010: begin
                comb_result = a_gt_b2 ? a : b;
            end

            // --------------------------------------
            // FP2INT (separate unpack — no sharing).
            // --------------------------------------
            4'b1011: begin
                if ((exp_a==EXP_ONES) || (actual_exp3 >= DATA_WIDTH-1)) begin
                    comb_of = 1;
                    comb_result = sign_a ? MAX_NEG : MAX_POS;
                end else if ((exp_a == EXP_ZERO&&mant_a == 0) || actual_exp3 < 0) begin
                    comb_result = 0;
                end else begin
                    int_val = mfull_a << actual_exp3;
                    comb_result = sign_a ? (~int_val)+1 : int_val;
                end
            end
            default: comb_result = 0;

        endcase
    end

    // Single output register (NO pipeline).
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result <= 0;
            valid_out <= 0;
            overflow <= 0;
            underflow <= 0;
            cmp_flags <= 0;
        end else begin
            result <= comb_result;
            valid_out <= valid_in;
            overflow <= comb_of;
            underflow <= comb_uf;
            cmp_flags <= comb_cmp;
        end
    end

endmodule

