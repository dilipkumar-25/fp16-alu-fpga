// Testbench : tb_fp16_unpack.
// Tests the parameterized fp16_unpack module.
// --------------------------------------------

module tb_fp16_unpack;

    // Parameters (match the design).
    parameter DATA_WIDTH = 16;
    parameter EXP_WIDTH  = 5;
    parameter MANT_WIDTH = 10;

    // Inputs.
    reg [DATA_WIDTH-1:0] fp_in;

    // Outputs.
    wire sign;
    wire [EXP_WIDTH-1:0] exponent;
    wire [MANT_WIDTH-1:0] mantissa;
    wire [MANT_WIDTH:0] mantissa_full;
    wire is_zero;
    wire is_inf;
    wire is_nan;
    wire is_denormal;

    // Instantiate parameterized module.
    fp16_unpack #(
        .DATA_WIDTH (DATA_WIDTH),
        .EXP_WIDTH  (EXP_WIDTH),
        .MANT_WIDTH (MANT_WIDTH)
    ) uut (
        .fp_in        (fp_in),
        .sign         (sign),
        .exponent     (exponent),
        .mantissa     (mantissa),
        .mantissa_full(mantissa_full),
        .is_zero      (is_zero),
        .is_inf       (is_inf),
        .is_nan       (is_nan),
        .is_denormal  (is_denormal)
    );

    // Task to display results.
    task show_result;
        begin
            $display("Input     : %b (0x%04X)", fp_in, fp_in);
            $display("Sign      : %b", sign);
            $display("Exponent  : %b (stored=%0d, actual=%0d)",
                      exponent, exponent, exponent - 15);
            $display("Mantissa  : %b", mantissa);
            $display("Mant+1    : %b", mantissa_full);
            $display("Flags     : zero=%b inf=%b nan=%b denorm=%b",
                      is_zero, is_inf, is_nan, is_denormal);
            $display("---------------------------------------------");
        end
    endtask

    // Pass/Fail checker.
    task check;
        input exp_sign;
        input [EXP_WIDTH-1:0]  exp_exponent;
        input [MANT_WIDTH-1:0] exp_mantissa;
        input exp_zero, exp_inf, exp_nan, exp_denorm;
        begin
            if (sign        == exp_sign     &&
                exponent    == exp_exponent &&
                mantissa    == exp_mantissa &&
                is_zero     == exp_zero     &&
                is_inf      == exp_inf      &&
                is_nan      == exp_nan      &&
                is_denormal == exp_denorm)
                $display("RESULT: *** PASS ***");
            else
                $display("RESULT: !!! FAIL !!!");
        end
    endtask

    integer pass_count;
    integer fail_count;

    initial begin
        pass_count = 0;
        fail_count = 0;

        $display("=============================================");
        $display("   PARAMETERIZED FP16 UNPACK TESTBENCH      ");
        $display("   DATA=%0d EXP=%0d MANT=%0d",
                  DATA_WIDTH, EXP_WIDTH, MANT_WIDTH);
        $display("=============================================");

        // TEST 1: 1.0 = 0x3C00.
        fp_in = 16'h3C00; #10;
        $display("TEST 1: 1.0");
        show_result;
        check(0, 5'd15, 10'b0, 0,0,0,0);

        // TEST 2: -1.0 = 0xBC00.
        fp_in = 16'hBC00; #10;
        $display("TEST 2: -1.0");
        show_result;
        check(1, 5'd15, 10'b0, 0,0,0,0);

        // TEST 3: 1.5 = 0x3E00.
        fp_in = 16'h3E00; #10;
        $display("TEST 3: 1.5");
        show_result;
        check(0, 5'd15, 10'b1000000000, 0,0,0,0);

        // TEST 4: 2.0 = 0x4000.
        fp_in = 16'h4000; #10;
        $display("TEST 4: 2.0");
        show_result;
        check(0, 5'd16, 10'b0, 0,0,0,0);

        // TEST 5: +Infinity = 0x7C00.
        fp_in = 16'h7C00; #10;
        $display("TEST 5: +Infinity");
        show_result;
        check(0, 5'b11111, 10'b0, 0,1,0,0);

        // TEST 6: NaN = 0x7E00.
        fp_in = 16'h7E00; #10;
        $display("TEST 6: NaN");
        show_result;
        check(0, 5'b11111, 10'b1000000000, 0,0,1,0);

        // TEST 7: Zero = 0x0000.
        fp_in = 16'h0000; #10;
        $display("TEST 7: +Zero");
        show_result;
        check(0, 5'b00000, 10'b0, 1,0,0,0);

        // TEST 8: -Zero = 0x8000.
        fp_in = 16'h8000; #10;
        $display("TEST 8: -Zero");
        show_result;
        check(1, 5'b00000, 10'b0, 1,0,0,0);

        $display("=============================================");
        $display("  ALL TESTS DONE");
        $display("=============================================");
        $finish;
    end

endmodule





