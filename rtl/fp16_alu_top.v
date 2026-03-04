// --------------------------------------------------------------------------
// Module     : fp16_alu_top.
// Function   : Parameterized Pipelined FP16 ALU Top Module.
// Operations : ADD, SUB, MUL, AND, OR, XOR, MIN, ABS, NEG, CMP, MAX, FP2INT.
// Pipeline   : Up to 5 stages depending on operation.
// --------------------------------------------------------------------------

module fp16_alu_top #(
    parameter DATA_WIDTH = 16,
    parameter EXP_WIDTH = 5,
    parameter MANT_WIDTH = 10,
    parameter OP_WIDTH = 4   // 4 bits = 16 possible operations.
)(
    input wire clk, rst_n, valid_in,
    input wire [DATA_WIDTH-1:0] a, b,
    input wire [OP_WIDTH-1:0] op_sel,   // operation select.

    output reg [DATA_WIDTH-1:0]  result,
    output reg valid_out, overflow, underflow,
    output reg [1:0] cmp_flags   // from CMP operation.
);
    // --------------------------
    // OPERATION SELECT ENCODING.
    // --------------------------

    localparam OP_ADD    = 4'b0000;
    localparam OP_SUB    = 4'b0001;
    localparam OP_MUL    = 4'b0010;
    localparam OP_AND    = 4'b0011;
    localparam OP_OR     = 4'b0100;
    localparam OP_XOR    = 4'b0101;
    localparam OP_MIN    = 4'b0110;
    localparam OP_ABS    = 4'b0111;
    localparam OP_NEG    = 4'b1000;
    localparam OP_CMP    = 4'b1001;
    localparam OP_MAX    = 4'b1010;
    localparam OP_FP2INT = 4'b1011;

    // ---------------------------------------------
    // INTERNAL WIRES — outputs from each submodule.
    // ---------------------------------------------

    // AddSub outputs.
    wire [DATA_WIDTH-1:0] addsub_result;
    wire addsub_valid, addsub_overflow, addsub_underflow;

    // Mul outputs.
    wire [DATA_WIDTH-1:0] mul_result;
    wire mul_valid, mul_overflow, mul_underflow;

    // Logic outputs.
    wire [DATA_WIDTH-1:0] logic_result;
    wire logic_valid;
    wire [1:0] logic_cmp_flags;

    // FP2INT outputs.
    wire [DATA_WIDTH-1:0] fp2int_result;
    wire fp2int_valid, fp2int_overflow;

    // -------------------------
    // SUBMODULE INSTANTIATIONS.
    // -------------------------

    // AddSub: handles ADD and SUB.
    // op=0 for ADD, op=1 for SUB.
    fp16_addsub #(
        .DATA_WIDTH (DATA_WIDTH),
        .EXP_WIDTH (EXP_WIDTH),
        .MANT_WIDTH (MANT_WIDTH)
    ) u_addsub (
        .clk (clk),
        .rst_n (rst_n),
        .a (a),
        .b (b),
        .op (op_sel[0]),   // bit 0: 0=add, 1=sub.
        .valid_in (valid_in && (op_sel == OP_ADD || op_sel == OP_SUB)),
        .result (addsub_result),
        .valid_out (addsub_valid),
        .overflow (addsub_overflow),
        .underflow (addsub_underflow)
    );

    // Multiplier.
    fp16_mul #(
        .DATA_WIDTH (DATA_WIDTH),
        .EXP_WIDTH (EXP_WIDTH),
        .MANT_WIDTH (MANT_WIDTH)
    ) u_mul (
        .clk (clk),
        .rst_n (rst_n),
        .a (a),
        .b (b),
        .valid_in (valid_in && (op_sel == OP_MUL)),
        .result (mul_result),
        .valid_out (mul_valid),
        .overflow (mul_overflow),
        .underflow (mul_underflow)
    );

    // Logic operations.
    // Map top-level op_sel to logic module's 3-bit op.
    // OP_AND=0011 -> logic op 000.
    // OP_OR =0100 -> logic op 001.
    // OP_XOR=0101 -> logic op 010.
    // OP_MIN=0110 -> logic op 011.
    // OP_ABS=0111 -> logic op 100.
    // OP_NEG=1000 -> logic op 101.
    // OP_CMP=1001 -> logic op 110.
    // OP_MAX=1010 -> logic op 111.

    wire [2:0] logic_op = op_sel[2:0] - 3'd3;

    // Subtracting 3 maps:
    // 3(AND)->0, 4(OR)->1, 5(XOR)->2, 6(MIN)->3.
    // 7(ABS)->4, 8(NEG)->5, 9(CMP)->6, 10(MAX)->7.

    wire logic_valid_in = valid_in && (op_sel >= OP_AND && op_sel <= OP_MAX);

    fp16_logic #(
        .DATA_WIDTH (DATA_WIDTH),
        .EXP_WIDTH (EXP_WIDTH),
        .MANT_WIDTH (MANT_WIDTH),
        .OP_WIDTH (3)
    ) u_logic (
        .clk (clk),
        .rst_n (rst_n),
        .a (a),
        .b (b),
        .op (logic_op),
        .valid_in (logic_valid_in),
        .result (logic_result),
        .valid_out (logic_valid),
        .cmp_flags (logic_cmp_flags)
    );

    // FP to Integer Converter.
    fp16_to_int #(
        .DATA_WIDTH (DATA_WIDTH),
        .EXP_WIDTH (EXP_WIDTH),
        .MANT_WIDTH (MANT_WIDTH),
        .INT_WIDTH (DATA_WIDTH)
    ) u_fp2int (
        .clk (clk),
        .rst_n (rst_n),
        .fp_in (a),   // only uses A input.
        .valid_in (valid_in && (op_sel == OP_FP2INT)),
        .int_out (fp2int_result),
        .valid_out (fp2int_valid),
        .overflow (fp2int_overflow),
        .is_zero ()   // not connected at top level.
    );

    // ---------------------------------------------------------
    // Pipeline The OP_SEL Signal.
    // We need to know which operation was in flight when.
    // result comes out. Pipeline op_sel to match latency.
    // AddSub and Mul have 3 cycle latency.
    // Logic has 1 cycle latency.
    // FP2INT has 2 cycle latency.
    // We pipeline to max latency (3 cycles) for uniform output.
    // ---------------------------------------------------------

    reg [OP_WIDTH-1:0] op_pipe1, op_pipe2, op_pipe3;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            op_pipe1 <= 0;
            op_pipe2 <= 0;
            op_pipe3 <= 0;
        end else begin
            op_pipe1 <= op_sel;
            op_pipe2 <= op_pipe1;
            op_pipe3 <= op_pipe2;
        end
    end

    // ----------------------------------------
    // OUTPUT MUX.
    // Select which submodule result to output.
    // based on the pipelined op_sel.
    // ----------------------------------------

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result <= 0;
            valid_out <= 0;
            overflow <= 0;
            underflow <= 0;
            cmp_flags <= 0;
        end else begin
            // Default values.
            overflow <= 0;
            underflow <= 0;
            cmp_flags <= 0;

            case (op_pipe3)

                OP_ADD, OP_SUB: begin
                    result <= addsub_result;
                    valid_out <= addsub_valid;
                    overflow <= addsub_overflow;
                    underflow <= addsub_underflow;
                end

                OP_MUL: begin
                    result <= mul_result;
                    valid_out <= mul_valid;
                    overflow <= mul_overflow;
                    underflow <= mul_underflow;
                end

                OP_AND, OP_OR,  OP_XOR,
                OP_MIN, OP_ABS, OP_NEG,
                OP_CMP, OP_MAX: begin
                    result <= logic_result;
                    valid_out <= logic_valid;
                    cmp_flags <= logic_cmp_flags;
                end

                OP_FP2INT: begin
                    result <= fp2int_result;
                    valid_out <= fp2int_valid;
                    overflow <= fp2int_overflow;
                end

                default: begin
                    result <= 0;
                    valid_out <= 0;
                end

            endcase
        end
    end

endmodule