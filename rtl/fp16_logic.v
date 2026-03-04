// ------------------------------------------------------
// Module     : fp16_logic.
// Function   : Logic operations and comparison for FP16.
// Operations : AND, OR, XOR, NOT, ABS, NEG, CMP, MAX.
// Pipeline   : 1 stage (registered output).
// ------------------------------------------------------

module fp16_logic #(
    parameter DATA_WIDTH = 16,
    parameter EXP_WIDTH = 5,
    parameter MANT_WIDTH = 10,
    parameter OP_WIDTH = 3
)(
    input wire clk,
    input wire rst_n,
    input wire [DATA_WIDTH-1:0] a, b,
    input wire [OP_WIDTH-1:0] op,
    input wire valid_in,

    output reg [DATA_WIDTH-1:0] result,
    output reg valid_out,
    output reg [1:0] cmp_flags   // cmp_flags[1] = A > B ; cmp_flags[0] = A == B.
);
    // Operation Encoding.
    localparam OP_AND = 3'b000;
    localparam OP_OR = 3'b001;
    localparam OP_XOR = 3'b010;
    localparam OP_MIN = 3'b011;
    localparam OP_ABS = 3'b100;
    localparam OP_NEG = 3'b101;
    localparam OP_CMP = 3'b110;
    localparam OP_MAX = 3'b111;

    // Comparison Logic (combinational).
    wire sign_a = a[DATA_WIDTH-1];
    wire sign_b = b[DATA_WIDTH-1];

    // Remove sign bits for magnitude comparison.
    wire [DATA_WIDTH-2:0] mag_a = a[DATA_WIDTH-2:0];
    wire [DATA_WIDTH-2:0] mag_b = b[DATA_WIDTH-2:0];

    // A > B logic.
    wire a_gt_b =
        // Both positive: larger magnitude wins.
        (!sign_a && !sign_b && mag_a > mag_b) ||
        // Both negative: smaller magnitude wins.
        (sign_a  && sign_b  && mag_a < mag_b) ||
        // A positive, B negative: A always wins.
        (!sign_a && sign_b);

    // A == B logic.
    // Note: +0 and -0 are equal in FP.
    wire a_zero = (a[DATA_WIDTH-2:0] == 0);
    wire b_zero = (b[DATA_WIDTH-2:0] == 0);
    wire a_eq_b = (a == b) || (a_zero && b_zero);

    // Pipeline Register.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 0;
            result <= 0;
            cmp_flags <= 0;
        end else begin
            valid_out <= valid_in;
            cmp_flags <= 0;

            case (op)

                OP_AND: begin
                    result <= a & b;
                end
                OP_OR: begin
                    result <= a | b;
                end
                OP_XOR: begin
                    result <= a ^ b;
                end
                OP_MIN: begin
                    result <= a_gt_b ? b : a;
                end
                OP_ABS: begin
                    // Absolute value: clear sign bit.
                    // Force bit 15 to 0, keep all other bits.
                    result <= {1'b0, a[DATA_WIDTH-2:0]};
                end
                OP_NEG: begin
                    // Negate: flip sign bit only.
                    // Flip bit 15, keep all other bits.
                    result <= {~a[DATA_WIDTH-1], a[DATA_WIDTH-2:0]};
                end
                OP_CMP: begin
                    // Result = 0 (not meaningful for CMP).
                    result <= 0;
                    cmp_flags[1] <= a_gt_b;
                    cmp_flags[0] <= a_eq_b;
                end
                OP_MAX: begin
                    result <= a_gt_b ? a : b;
                end

                default: begin
                    result <= 0;
                end
            endcase
        end
    end
endmodule


