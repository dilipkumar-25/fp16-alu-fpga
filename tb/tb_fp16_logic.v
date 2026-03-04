// ============================================================
// Testbench : tb_fp16_logic
// ============================================================

module tb_fp16_logic;

    parameter DATA_WIDTH = 16;
    parameter EXP_WIDTH  = 5;
    parameter MANT_WIDTH = 10;
    parameter OP_WIDTH   = 3;

    // ── Operation codes (must match design) ──
    parameter OP_AND = 3'b000;
    parameter OP_OR  = 3'b001;
    parameter OP_XOR = 3'b010;
    parameter OP_MIN = 3'b011;
    parameter OP_ABS = 3'b100;
    parameter OP_NEG = 3'b101;
    parameter OP_CMP = 3'b110;
    parameter OP_MAX = 3'b111;

    reg                   clk, rst_n;
    reg [DATA_WIDTH-1:0]  a, b;
    reg [OP_WIDTH-1:0]    op;
    reg                   valid_in;

    wire [DATA_WIDTH-1:0] result;
    wire                  valid_out;
    wire [1:0]            cmp_flags;

    // ── Clock ──
    initial clk = 0;
    always #5 clk = ~clk;

    // ── Instantiate ──
    fp16_logic #(
        .DATA_WIDTH (DATA_WIDTH),
        .EXP_WIDTH  (EXP_WIDTH),
        .MANT_WIDTH (MANT_WIDTH),
        .OP_WIDTH   (OP_WIDTH)
    ) uut (
        .clk       (clk),
        .rst_n     (rst_n),
        .a         (a),
        .b         (b),
        .op        (op),
        .valid_in  (valid_in),
        .result    (result),
        .valid_out (valid_out),
        .cmp_flags (cmp_flags)
    );

    // ── Test task for logic/arithmetic ops ──
    task apply_test;
        input [DATA_WIDTH-1:0] in_a, in_b;
        input [OP_WIDTH-1:0]   operation;
        input [DATA_WIDTH-1:0] expected;
        input [31:0]           test_num;
        input [63:0]           op_name;
        begin
            @(posedge clk);
            a        <= in_a;
            b        <= in_b;
            op       <= operation;
            valid_in <= 1;
            @(posedge clk);
            valid_in <= 0;
            @(posedge clk);

            if (result == expected)
                $display("TEST %0d (%s): PASS | result=0x%04X",
                          test_num, op_name, result);
            else
                $display("TEST %0d (%s): FAIL | got=0x%04X expected=0x%04X",
                          test_num, op_name, result, expected);
        end
    endtask

    // ── Test task for comparison ──
    task apply_cmp;
        input [DATA_WIDTH-1:0] in_a, in_b;
        input                  exp_gt, exp_eq;
        input [31:0]           test_num;
        begin
            @(posedge clk);
            a        <= in_a;
            b        <= in_b;
            op       <= OP_CMP;
            valid_in <= 1;
            @(posedge clk);
            valid_in <= 0;
            @(posedge clk);

            if (cmp_flags[1] == exp_gt && cmp_flags[0] == exp_eq)
                $display("TEST %0d (CMP): PASS | gt=%b eq=%b",
                          test_num, cmp_flags[1], cmp_flags[0]);
            else
                $display("TEST %0d (CMP): FAIL | got gt=%b eq=%b | exp gt=%b eq=%b",
                          test_num, cmp_flags[1], cmp_flags[0], exp_gt, exp_eq);
        end
    endtask

    initial begin
        // ── Reset ──
        rst_n = 0; valid_in = 0;
        a = 0; b = 0; op = 0;
        repeat(3) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);

        $display("==========================================");
        $display("      FP16 LOGIC OPERATIONS TESTBENCH    ");
        $display("==========================================");

        // ── AND Tests ──
        // 0xFF00 & 0x0FF0 = 0x0F00
        apply_test(16'hFF00, 16'h0FF0, OP_AND, 16'h0F00, 1, "AND");

        // ── OR Tests ──
        // 0xFF00 | 0x00FF = 0xFFFF
        apply_test(16'hFF00, 16'h00FF, OP_OR, 16'hFFFF, 2, "OR ");

        // ── XOR Tests ──
        // 0xFFFF ^ 0xFF00 = 0x00FF
        apply_test(16'hFFFF, 16'hFF00, OP_XOR, 16'h00FF, 3, "XOR");

        // ── NOT Tests ──
        // ~0xFF00 = 0x00FF
        apply_test(16'h3E00, 16'h4000, OP_MIN, 16'h3E00, 4, "MIN");

        // ── ABS Tests ──
        // ABS(-1.0) = 1.0
        // -1.0=0xBC00, 1.0=0x3C00
        apply_test(16'hBC00, 16'h0000, OP_ABS, 16'h3C00, 5, "ABS");

        // ── NEG Tests ──
        // NEG(1.5) = -1.5
        // 1.5=0x3E00, -1.5=0xBE00
        apply_test(16'h3E00, 16'h0000, OP_NEG, 16'hBE00, 6, "NEG");

        // ── CMP Tests ──
        // 2.0 > 1.0 → gt=1, eq=0
        // 2.0=0x4000, 1.0=0x3C00
        apply_cmp(16'h4000, 16'h3C00, 1, 0, 7);

        // 1.0 == 1.0 → gt=0, eq=1
        apply_cmp(16'h3C00, 16'h3C00, 0, 1, 8);

        // 1.0 < 2.0 → gt=0, eq=0
        apply_cmp(16'h3C00, 16'h4000, 0, 0, 9);

        // ── MAX Tests ──
        // MAX(1.5, 2.0) = 2.0
        apply_test(16'h3E00, 16'h4000, OP_MAX, 16'h4000, 10, "MAX");

        $display("==========================================");
        $display("          ALL TESTS DONE                 ");
        $display("==========================================");
        $finish;
    end

endmodule

