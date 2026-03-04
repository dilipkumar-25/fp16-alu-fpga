// ============================================================
// Testbench : tb_fp16_mul
// ============================================================

module tb_fp16_mul;

    parameter DATA_WIDTH = 16;
    parameter EXP_WIDTH  = 5;
    parameter MANT_WIDTH = 10;

    reg                   clk, rst_n;
    reg [DATA_WIDTH-1:0]  a, b;
    reg                   valid_in;

    wire [DATA_WIDTH-1:0] result;
    wire                  valid_out;
    wire                  overflow;
    wire                  underflow;

    // ── Clock ──
    initial clk = 0;
    always #5 clk = ~clk;

    // ── Instantiate ──
    fp16_mul #(
        .DATA_WIDTH (DATA_WIDTH),
        .EXP_WIDTH  (EXP_WIDTH),
        .MANT_WIDTH (MANT_WIDTH)
    ) uut (
        .clk       (clk),
        .rst_n     (rst_n),
        .a         (a),
        .b         (b),
        .valid_in  (valid_in),
        .result    (result),
        .valid_out (valid_out),
        .overflow  (overflow),
        .underflow (underflow)
    );

    // ── Test task ──
    task apply_test;
        input [DATA_WIDTH-1:0] in_a, in_b;
        input [DATA_WIDTH-1:0] expected;
        input [31:0]           test_num;
        begin
            @(posedge clk);
            a        <= in_a;
            b        <= in_b;
            valid_in <= 1;

            repeat(4) @(posedge clk);
            valid_in <= 0;
            @(posedge clk);

            if (result == expected)
                $display("TEST %0d: PASS | result=0x%04X", test_num, result);
            else
                $display("TEST %0d: FAIL | got=0x%04X  expected=0x%04X",
                          test_num, result, expected);
        end
    endtask

    initial begin
        // ── Reset ──
        rst_n = 0; valid_in = 0; a = 0; b = 0;
        repeat(3) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);

        $display("==========================================");
        $display("        FP16 MULTIPLIER TESTBENCH        ");
        $display("==========================================");

        // Test 1: 1.0 × 1.0 = 1.0
        // 1.0=0x3C00
        apply_test(16'h3C00, 16'h3C00, 16'h3C00, 1);

        // Test 2: 1.5 × 2.0 = 3.0
        // 1.5=0x3E00, 2.0=0x4000, 3.0=0x4200
        apply_test(16'h3E00, 16'h4000, 16'h4200, 2);

        // Test 3: 2.0 × 2.0 = 4.0
        // 2.0=0x4000, 4.0=0x4400
        apply_test(16'h4000, 16'h4000, 16'h4400, 3);

        // Test 4: -1.0 × 1.0 = -1.0
        // -1.0=0xBC00
        apply_test(16'hBC00, 16'h3C00, 16'hBC00, 4);

        // Test 5: -1.5 × -2.0 = 3.0
        // -1.5=0xBE00, -2.0=0xC000, 3.0=0x4200
        apply_test(16'hBE00, 16'hC000, 16'h4200, 5);

        // Test 6: 1.0 × 0 = 0
        apply_test(16'h3C00, 16'h0000, 16'h0000, 6);

        // Test 7: Inf × 2.0 = Inf
        // Inf=0x7C00
        apply_test(16'h7C00, 16'h4000, 16'h7C00, 7);

        // Test 8: Inf × 0 = NaN
        // NaN=0x7E00
        apply_test(16'h7C00, 16'h0000, 16'h7E00, 8);

        $display("==========================================");
        $display("          ALL TESTS DONE                 ");
        $display("==========================================");
        $finish;
    end

endmodule


