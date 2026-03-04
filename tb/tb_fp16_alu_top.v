// ============================================================
// Testbench : tb_fp16_alu_top
// Tests all operations through the unified top module
// ============================================================

module tb_fp16_alu_top;

    parameter DATA_WIDTH = 16;
    parameter EXP_WIDTH  = 5;
    parameter MANT_WIDTH = 10;
    parameter OP_WIDTH   = 4;

    // ── Operation codes ──
    parameter OP_ADD    = 4'b0000;
    parameter OP_SUB    = 4'b0001;
    parameter OP_MUL    = 4'b0010;
    parameter OP_AND    = 4'b0011;
    parameter OP_OR     = 4'b0100;
    parameter OP_XOR    = 4'b0101;
    parameter OP_MIN    = 4'b0110;
    parameter OP_ABS    = 4'b0111;
    parameter OP_NEG    = 4'b1000;
    parameter OP_CMP    = 4'b1001;
    parameter OP_MAX    = 4'b1010;
    parameter OP_FP2INT = 4'b1011;

    reg                   clk, rst_n;
    reg [DATA_WIDTH-1:0]  a, b;
    reg [OP_WIDTH-1:0]    op_sel;
    reg                   valid_in;

    wire [DATA_WIDTH-1:0] result;
    wire                  valid_out;
    wire                  overflow;
    wire                  underflow;
    wire [1:0]            cmp_flags;

    // ── Clock ──
    initial clk = 0;
    always #5 clk = ~clk;

    // ── Instantiate top module ──
    fp16_alu_top #(
        .DATA_WIDTH (DATA_WIDTH),
        .EXP_WIDTH  (EXP_WIDTH),
        .MANT_WIDTH (MANT_WIDTH),
        .OP_WIDTH   (OP_WIDTH)
    ) uut (
        .clk       (clk),
        .rst_n     (rst_n),
        .a         (a),
        .b         (b),
        .op_sel    (op_sel),
        .valid_in  (valid_in),
        .result    (result),
        .valid_out (valid_out),
        .overflow  (overflow),
        .underflow (underflow),
        .cmp_flags (cmp_flags)
    );

    // ── Test task ──
    task apply_test;
        input [DATA_WIDTH-1:0] in_a, in_b;
        input [OP_WIDTH-1:0]   operation;
        input [DATA_WIDTH-1:0] expected;
        input [31:0]           test_num;
        begin
            @(posedge clk);
            a        <= in_a;
            b        <= in_b;
            op_sel   <= operation;
            valid_in <= 1;
            repeat(5) @(posedge clk);
            valid_in <= 0;
            @(posedge clk);

            if (result == expected)
                $display("TEST %0d: PASS | op=%04b result=0x%04X",
                          test_num, operation, result);
            else
                $display("TEST %0d: FAIL | op=%04b got=0x%04X exp=0x%04X",
                          test_num, operation, result, expected);
        end
    endtask

    integer pass_count;
    integer fail_count;

    initial begin
        rst_n      = 0;
        valid_in   = 0;
        a = 0; b = 0; op_sel = 0;
        pass_count = 0;
        fail_count = 0;
        repeat(3) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);

        $display("==========================================");
        $display("    FP16 ALU TOP MODULE TESTBENCH        ");
        $display("==========================================");

        // ── ADD: 1.5 + 0.5 = 2.0 ──
        apply_test(16'h3E00, 16'h3800, OP_ADD, 16'h4000, 1);

        // ── SUB: 2.0 - 1.0 = 1.0 ──
        apply_test(16'h4000, 16'h3C00, OP_SUB, 16'h3C00, 2);

        // ── MUL: 1.5 × 2.0 = 3.0 ──
        apply_test(16'h3E00, 16'h4000, OP_MUL, 16'h4200, 3);

        // ── AND ──
        apply_test(16'hFF00, 16'h0FF0, OP_AND, 16'h0F00, 4);

        // ── OR ──
        apply_test(16'hFF00, 16'h00FF, OP_OR,  16'hFFFF, 5);

        // ── XOR ──
        apply_test(16'hFFFF, 16'hFF00, OP_XOR, 16'h00FF, 6);

        // ── MIN: MIN(1.5, 2.0) = 1.5 ──
        apply_test(16'h3E00, 16'h4000, OP_MIN, 16'h3E00, 7);

        // ── ABS: ABS(-1.0) = 1.0 ──
        apply_test(16'hBC00, 16'h0000, OP_ABS, 16'h3C00, 8);

        // ── NEG: NEG(1.5) = -1.5 ──
        apply_test(16'h3E00, 16'h0000, OP_NEG, 16'hBE00, 9);

        // ── MAX: MAX(1.5, 2.0) = 2.0 ──
        apply_test(16'h3E00, 16'h4000, OP_MAX, 16'h4000, 10);

        // ── FP2INT: 6.0 → 6 ──
        apply_test(16'h4600, 16'h0000, OP_FP2INT, 16'h0006, 11);

        $display("==========================================");
        $display("         ALL TESTS DONE                  ");
        $display("==========================================");
        $finish;
    end

endmodule

