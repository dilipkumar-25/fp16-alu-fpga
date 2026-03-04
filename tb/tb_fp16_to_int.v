// ============================================================
// Testbench : tb_fp16_to_int
// ============================================================

module tb_fp16_to_int;

    parameter DATA_WIDTH = 16;
    parameter EXP_WIDTH  = 5;
    parameter MANT_WIDTH = 10;
    parameter INT_WIDTH  = 16;

    reg  [DATA_WIDTH-1:0] fp_in;
    reg                   clk, rst_n, valid_in;

    wire [INT_WIDTH-1:0]  int_out;
    wire                  valid_out;
    wire                  overflow;
    wire                  is_zero;

    // ── Clock ──
    initial clk = 0;
    always #5 clk = ~clk;

    // ── Instantiate ──
    fp16_to_int #(
        .DATA_WIDTH (DATA_WIDTH),
        .EXP_WIDTH  (EXP_WIDTH),
        .MANT_WIDTH (MANT_WIDTH),
        .INT_WIDTH  (INT_WIDTH)
    ) uut (
        .clk       (clk),
        .rst_n     (rst_n),
        .fp_in     (fp_in),
        .valid_in  (valid_in),
        .int_out   (int_out),
        .valid_out (valid_out),
        .overflow  (overflow),
        .is_zero   (is_zero)
    );

    // ── Test task ──
    task apply_test;
        input [DATA_WIDTH-1:0] input_fp;
        input signed [INT_WIDTH-1:0] expected_int;
        input [31:0] test_num;
        input [63:0] description;
        begin
            @(posedge clk);
            fp_in    <= input_fp;
            valid_in <= 1;
            repeat(3) @(posedge clk);
            valid_in <= 0;
            @(posedge clk);

            if (int_out == expected_int)
                $display("TEST %0d (%s): PASS | int_out=%0d",
                          test_num, description, $signed(int_out));
            else
                $display("TEST %0d (%s): FAIL | got=%0d expected=%0d",
                          test_num, description,
                          $signed(int_out), $signed(expected_int));
        end
    endtask

    initial begin
        rst_n = 0; valid_in = 0; fp_in = 0;
        repeat(3) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);

        $display("==========================================");
        $display("     FP16 TO INTEGER TESTBENCH           ");
        $display("==========================================");

        // Test 1: 1.0 → 1
        // 1.0 = 0x3C00
        apply_test(16'h3C00, 16'd1, 1, "1.0  ");

        // Test 2: 2.0 → 2
        // 2.0 = 0x4000
        apply_test(16'h4000, 16'd2, 2, "2.0  ");

        // Test 3: 6.0 → 6
        // 6.0 = 0x4600
        apply_test(16'h4600, 16'd6, 3, "6.0  ");

        // Test 4: -3.0 → -3
        // -3.0 = 0xC200
        apply_test(16'hC200, -16'd3, 4, "-3.0 ");

        // Test 5: 0.5 → 0 (fraction truncated)
        // 0.5 = 0x3800
        apply_test(16'h3800, 16'd0, 5, "0.5  ");

        // Test 6: 0.0 → 0
        apply_test(16'h0000, 16'd0, 6, "0.0  ");

        // Test 7: -1.0 → -1
        // -1.0 = 0xBC00
        apply_test(16'hBC00, -16'd1, 7, "-1.0 ");

        // Test 8: 100.0 → 100
        // 100.0 = 0x5640
        apply_test(16'h5640, 16'd100, 8, "100.0");

        $display("==========================================");
        $display("         ALL TESTS DONE                  ");
        $display("==========================================");
        $finish;
    end

endmodule

