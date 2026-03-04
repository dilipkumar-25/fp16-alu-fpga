// ----------------------------
// Testbench : tb_fp16_addsub.
// ----------------------------

module tb_fp16_addsub;

    parameter DATA_WIDTH = 16;
    parameter EXP_WIDTH = 5;
    parameter MANT_WIDTH = 10;

    reg clk, rst_n, op, valid_in;
    reg [DATA_WIDTH-1:0] a, b;

    wire [DATA_WIDTH-1:0] result;
    wire valid_out, overflow, underflow;

    // Clock generation.
    initial clk = 0;
    always #5 clk = ~clk;   // 10ns period = 100MHz.

    // Instantiate module.
    fp16_addsub #(
        .DATA_WIDTH (DATA_WIDTH),
        .EXP_WIDTH (EXP_WIDTH),
        .MANT_WIDTH (MANT_WIDTH)
    ) uut (
        .clk (clk),
        .rst_n (rst_n),
        .a (a),
        .b (b),
        .op (op),
        .valid_in (valid_in),
        .result (result),
        .valid_out (valid_out),
        .overflow (overflow),
        .underflow (underflow)
    );

    // Task: apply inputs and wait for result.
    task apply_test;
        input [DATA_WIDTH-1:0] in_a, in_b;
        input operation;
        input [DATA_WIDTH-1:0] expected;
        input [63:0] test_num;
        begin
            @(posedge clk);
            a <= in_a;
            b <= in_b;
            op <= operation;
            valid_in <= 1;

            // Wait for pipeline to produce output (3 cycles).
            repeat(4) @(posedge clk);
            valid_in <= 0;

            @(posedge clk);
            if (result == expected)
                $display("TEST %0d: PASS | result=0x%04X", test_num, result);
            else
                $display("TEST %0d: FAIL | got=0x%04X expected=0x%04X",
                          test_num, result, expected);
        end
    endtask

    initial begin
        // Reset.
        rst_n = 0;
        valid_in = 0;
        a = 0; b = 0; op = 0;
        repeat(3) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);

        $display("==========================================");
        $display("   FP16 ADDSUB TESTBENCH                 ");
        $display("==========================================");

        // Test 1: 1.0 + 1.0 = 2.0
        // 1.0=0x3C00, 2.0=0x4000
        apply_test(16'h3C00, 16'h3C00, 0, 16'h4000, 1);

        // Test 2: 1.5 + 0.5 = 2.0
        // 1.5=0x3E00, 0.5=0x3800, 2.0=0x4000
        apply_test(16'h3E00, 16'h3800, 0, 16'h4000, 2);

        // Test 3: 2.0 - 1.0 = 1.0
        apply_test(16'h4000, 16'h3C00, 1, 16'h3C00, 3);

        // Test 4: 1.0 + (-1.0) = 0
        apply_test(16'h3C00, 16'hBC00, 0, 16'h0000, 4);

        // Test 5: 0 + 1.5 = 1.5
        apply_test(16'h0000, 16'h3E00, 0, 16'h3E00, 5);

        $display("==========================================");
        $display("   ALL TESTS DONE                        ");
        $display("==========================================");
        $finish;
    end

    // ── Dump waveforms ──
    initial begin
        $dumpfile("fp16_addsub.vcd");
        $dumpvars(0, tb_fp16_addsub);
    end
endmodule