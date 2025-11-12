import FIFO :: *;
import FShow :: *;
import Vector :: *;

import FPadder32Pipelined :: *;

function FP32 fromHex(Bit#(32) h);
    return unpack(h);
endfunction

typedef struct {
    FP32 a;
    FP32 b;
    FP32 expected;
} TestCase deriving (Bits, Eq, FShow);

(* synthesize *)
module mkTb(Empty);

    AdderIfc dut <- mkFPadder32;

    Vector#(9, TestCase) test_cases = 
        cons(TestCase {
            a:        fromHex(32'hC0000000), // -2.0
            b:        fromHex(32'hC0400000), // -3.0
            expected: fromHex(32'hC0A00000)  // -5.0
        },
        cons(TestCase {
            a:        fromHex(32'hBFC00000), // -1.5
            b:        fromHex(32'hBFC00000), // -1.5
            expected: fromHex(32'hC0400000)  // -3.0
        },
        cons(TestCase {
            a:        fromHex(32'hF1B098A2), // -2.0e30
            b:        fromHex(32'hF1B098A2), // -2.0e30
            expected: fromHex(32'hF23098A2)  // -4.0e30
        },
        cons(TestCase {
            a:        fromHex(32'h830F2CB0), // -1.0e-40
            b:        fromHex(32'h830F2CB0), // -1.0e-40
            expected: fromHex(32'h838F2CB0)  // -2.0e-40
        },
        cons(TestCase {
            a:        fromHex(32'hFE249F2C), // -1.0e38
            b:        fromHex(32'h8484196B), // -1.0e-38
            expected: fromHex(32'hFE249F2C)  // -1.0e38
        },
        cons(TestCase {
            a:        fromHex(32'hBF800000), // -1.0
            b:        fromHex(32'hB3800000), // -2^-24
            expected: fromHex(32'hBF800000)  // -1.0
        },
        cons(TestCase {
            a:        fromHex(32'hBF800001), // -(1.0 + 2^-23)
            b:        fromHex(32'hB3800000), // -2^-24
            expected: fromHex(32'hBF800002)  // -(1.0 + 2^-22)
        },
        cons(TestCase {
            a:        fromHex(32'hFF800000), // -Inf
            b:        fromHex(32'hC0000000), // -2.0
            expected: fromHex(32'hFF800000)  // -Inf
        },
        cons(TestCase {
            a:        fromHex(32'hFF800000), // -Inf
            b:        fromHex(32'hFF800000), // -Inf
            expected: fromHex(32'hFF800000)  // -Inf
        },
        nil))))))))); 

    let num_tests = 9;

    Reg#(int) send_idx    <- mkReg(0);
    Reg#(int) check_idx   <- mkReg(0);
    Reg#(int) error_count <- mkReg(0);

    FIFO#(FP32)     expected_fifo <- mkFIFO;
    FIFO#(TestCase) inputs_fifo   <- mkFIFO;

    rule send_tests (send_idx < num_tests);
        let test = test_cases[send_idx];
        dut.put(test.a, test.b);
        expected_fifo.enq(test.expected);
        inputs_fifo.enq(test); 
        send_idx <= send_idx + 1;
    endrule

    rule check_results (check_idx < num_tests);
        let actual   <- dut.get; 
        let expected = expected_fifo.first;
        let test_in  = inputs_fifo.first;
        expected_fifo.deq;
        inputs_fifo.deq;

        if (pack(actual) != pack(expected)) begin
            $display("---------------------------------");
            $display("ERROR: TEST FAILED! (Test Index: %d)", check_idx);
            $display("  A: %s (0x%h)", fshow(test_in.a), pack(test_in.a));
            $display("  B: %s (0x%h)", fshow(test_in.b), pack(test_in.b));
            $display("GOT: %s (0x%h)", fshow(actual),   pack(actual));
            $display("EXP: %s (0x%h)", fshow(expected), pack(expected));
            $display("---------------------------------");
            error_count <= error_count + 1;
        end
        
        check_idx <= check_idx + 1;
    endrule

    rule all_done (check_idx == num_tests);
        $display("---------------------------------");
        if (error_count == 0) begin
            $display("SUCCESS: All %d tests passed!", num_tests);
        end else begin
            $display("FAILURE: %d out of %d tests failed.", error_count, num_tests);
        end
        $display("---------------------------------");
        $finish(0);
    endrule

endmodule
