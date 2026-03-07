// ============================================================
// Testbench  : tb_fp16_addsub
// Function   : Verify fp16_addsub with LZA upgrade
// New tests  : Catastrophic cancellation, large shift,
//              near equal subtraction — these specifically
//              exercise the LZA prediction path
// ============================================================

module tb_fp16_addsub;

    parameter DATA_WIDTH = 16;
    parameter EXP_WIDTH  = 5;
    parameter MANT_WIDTH = 10;

    reg clk, rst_n, op, valid_in;
    reg [DATA_WIDTH-1:0] a, b;

    wire [DATA_WIDTH-1:0] result;
    wire valid_out, overflow, underflow;

    // Clock generation — 10ns period = 100MHz
    initial clk = 0;
    always #5 clk = ~clk;

    // Instantiate module
    fp16_addsub #(
        .DATA_WIDTH (DATA_WIDTH),
        .EXP_WIDTH  (EXP_WIDTH),
        .MANT_WIDTH (MANT_WIDTH)
    ) uut (
        .clk       (clk),
        .rst_n     (rst_n),
        .a         (a),
        .b         (b),
        .op        (op),
        .valid_in  (valid_in),
        .result    (result),
        .valid_out (valid_out),
        .overflow  (overflow),
        .underflow (underflow)
    );

    // Task: apply inputs and wait for pipeline result
    task apply_test;
        input [DATA_WIDTH-1:0] in_a, in_b;
        input                  operation;
        input [DATA_WIDTH-1:0] expected;
        input [63:0]           test_num;
        input [127:0]          test_name;
        begin
            @(posedge clk);
            a        <= in_a;
            b        <= in_b;
            op       <= operation;
            valid_in <= 1;

            // Wait 3 cycles for pipeline result
            repeat(4) @(posedge clk);
            valid_in <= 0;

            @(posedge clk);
            if (result == expected)
                $display("TEST %0d PASS | %-20s | result=0x%04X",
                          test_num, test_name, result);
            else
                $display("TEST %0d FAIL | %-20s | got=0x%04X expected=0x%04X",
                          test_num, test_name, result, expected);
        end
    endtask

    initial begin
        // Reset
        rst_n    = 0;
        valid_in = 0;
        a = 0; b = 0; op = 0;
        repeat(3) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);

        $display("=================================================");
        $display("   FP16 ADDSUB TESTBENCH — WITH LZA             ");
        $display("=================================================");

        // ── Original Tests ──

        // Test 1: 1.0 + 1.0 = 2.0
        // 1.0=0x3C00  2.0=0x4000
        // carry out case — LZA not used here
        apply_test(16'h3C00, 16'h3C00, 0, 16'h4000, 1, "1.0+1.0=2.0");

        // Test 2: 1.5 + 0.5 = 2.0
        // 1.5=0x3E00  0.5=0x3800  2.0=0x4000
        apply_test(16'h3E00, 16'h3800, 0, 16'h4000, 2, "1.5+0.5=2.0");

        // Test 3: 2.0 - 1.0 = 1.0
        // 2.0=0x4000  1.0=0x3C00
        apply_test(16'h4000, 16'h3C00, 1, 16'h3C00, 3, "2.0-1.0=1.0");

        // Test 4: 1.0 + (-1.0) = 0
        // -1.0=0xBC00  result=0x0000
        apply_test(16'h3C00, 16'hBC00, 0, 16'h0000, 4, "1.0+(-1.0)=0");

        // Test 5: 0 + 1.5 = 1.5
        apply_test(16'h0000, 16'h3E00, 0, 16'h3E00, 5, "0+1.5=1.5");

        // ── New LZA Specific Tests ──
        // These tests specifically exercise the LZA prediction
        // path — large normalization shifts required

        // Test 6: 1.0 - 0.5 = 0.5
        // 1.0=0x3C00  0.5=0x3800  0.5=0x3800
        // LZA must predict shift=1
        apply_test(16'h3C00, 16'h3800, 1, 16'h3800, 6, "1.0-0.5=0.5");

        // Test 7: 1.0 - 0.998 = 0.002
        // 1.0=0x3C00  0.998=0x3BFC  result=0x1400
        // catastrophic cancellation — LZA must predict large shift
        apply_test(16'h3C00, 16'h3BFC, 1, 16'h1400, 7, "cancellation");

        // Test 8: NaN + 1.0 = NaN
        // NaN=0x7E00  1.0=0x3C00  result=0x7E00
        // special case — LZA bypassed
        apply_test(16'h7E00, 16'h3C00, 0, 16'h7E00, 8, "NaN+1.0=NaN");

        // Test 9: Inf - Inf = NaN
        // Inf=0x7C00  result=0x7E00
        // special case — LZA bypassed
        apply_test(16'h7C00, 16'h7C00, 1, 16'h7E00, 9, "Inf-Inf=NaN");

        // Test 10: 0.5 + 0.5 = 1.0
        // 0.5=0x3800  1.0=0x3C00
        // LZA must predict shift=0 for carry out
        apply_test(16'h3800, 16'h3800, 0, 16'h3C00, 10, "0.5+0.5=1.0");

        $display("=================================================");
        $display("   ALL TESTS DONE                               ");
        $display("=================================================");
        $finish;
    end

    // Dump waveforms
    initial begin
        $dumpfile("fp16_addsub.vcd");
        $dumpvars(0, tb_fp16_addsub);
    end

endmodule
