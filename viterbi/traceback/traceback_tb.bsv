package traceback_tb;

import Vector::*;
import traceback::*;   // mkTraceBack, IfcTraceB

typedef enum { INIT, STORE, TERM, WAIT, CHECK, DONE } Phase deriving (Bits, Eq);
// Build a constant expected path of length 8 (each < 32)
function Vector#(8, State_t) mkPath();
  Vector#(8, State_t) p = newVector;
  p[0] = 5;   p[1] = 7;   p[2] = 3;   p[3] = 12;
  p[4] = 1;   p[5] = 9;   p[6] = 18;  p[7] = 4;
  return p;
endfunction

(* synthesize *)
module mkTracebackTB (Empty);

  // DUT
  IfcTraceB dut <- mkTraceBack;

  // Expected decoded sequence
  Vector#(8, State_t) path = mkPath();

  // Phases
  Reg#(Phase)    phase   <- mkReg(INIT);

  // Iterators: t = 1..7, cur = 0..31
  Reg#(UInt#(3)) tReg    <- mkReg(1);   // start at 1
  Reg#(UInt#(5)) curReg  <- mkReg(0);   // 0..31

  // Slack cycles to let traceback rule run
  Reg#(UInt#(4)) waitCnt <- mkReg(0);

  // INIT → STORE
  rule rl_init (phase == INIT);
    tReg   <= 1;
    curReg <= 0;
    phase  <= STORE;
  endrule

  // For each time t=1..7, load ALL 32 backpointers:
  //   bp[t][cur] = (cur == path[t]) ? path[t-1] : 0;
  rule rl_store (phase == STORE);
    TimeStep_t timeStep = pack(tReg);     // UInt#(3) -> Bit#(3)
    State_t    curSt    = pack(curReg);   // UInt#(5) -> Bit#(5)

    let bestTrue = path[tReg-1];          // State_t
    let curTrue  = path[tReg];            // State_t
    State_t best = (curSt == curTrue) ? bestTrue : fromInteger(0);

    dut.store(best, curSt, timeStep);
    $display("TB: store t=%0d cur=%0d best=%0d", timeStep, curSt, best);

    if (curReg < 31) begin
      curReg <= curReg + 1;
    end
    else begin
      // finished all 32 cur entries at this t
      curReg <= 0;
      if (tReg < 7) begin
        tReg <= tReg + 1;
      end
      else begin
        phase <= TERM;
      end
    end
  endrule

  // Trigger traceback with final state = path[7]
  rule rl_term (phase == TERM);
    dut.terminate(path[7]);
    $display("TB: terminate finalState=%0d", path[7]);
    waitCnt <= 10;       // DUT needs ~7 cycles; give slack
    phase   <= WAIT;
  endrule

  // Idle while DUT runs rl_terminate
  rule rl_wait (phase == WAIT);
    if (waitCnt != 0) waitCnt <= waitCnt - 1;
    else              phase   <= CHECK;
  endrule

  // Read results and compare against expected path
  rule rl_check (phase == CHECK);
    let res = dut.terminateRead();
    Bool ok = True;
    for (Integer i = 0; i < 8; i = i + 1) begin
      $display("TB: res[%0d]=%0d exp=%0d", i, res[i], path[i]);
      ok = ok && (res[i] == path[i]);
    end
    if (ok) $display("TB PASS");
    else    $display("TB FAIL");
    phase <= DONE;
  endrule

  rule rl_done (phase == DONE);
    $finish;
  endrule

endmodule

endpackage
