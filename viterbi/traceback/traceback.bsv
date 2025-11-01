package traceback;

  import Vector::*;

  // ---- Parameters ----
  typedef 32  T;    // number of timesteps (e.g., 8)
  typedef 32 N;    // number of states   (e.g., 32)

  // ---- Types ----
  typedef enum { NIL, TERMINATE } TraceBState_t deriving (Bits, Eq);
  typedef Bit#(TLog#(N)) State_t;       // 5 bits if N=32
  typedef Bit#(TLog#(T)) TimeStep_t;    // 3 bits if T=8

  interface IfcTraceB;
    method Action store(State_t bestState, State_t curState, TimeStep_t timeStep);
    method Action terminate(State_t finalState);
    method Vector#(T, State_t) terminateRead();
  endinterface

  (* synthesize *)
  module mkTraceBack(IfcTraceB);

    // bp[time][cur] = bestPrev
    Vector#(T, Vector#(N, Reg#(State_t))) traceBStorage <- replicateM(replicateM(mkRegU));
    Vector#(T,              Reg#(State_t)) traceBResult  <- replicateM(mkRegU);

    Reg#(TraceBState_t) controlState <- mkReg(NIL);
    Reg#(UInt#(TLog#(T))) counter    <- mkReg(0);   // counts 0 .. T-1

    // Run from counter = T-2 down to 0. Seed result[T-1] in terminate().
    rule rl_terminate (controlState == TERMINATE);
      let tNext = counter + 1;                               // 1..T-1
      let prev  = traceBStorage[tNext][ traceBResult[tNext] ];
      traceBResult[counter] <= prev;

      if (counter == 0) begin
        controlState <= NIL;                                 // done
      end else begin
        counter <= counter - 1;                              // continue
      end 
    endrule

    // Only allow writes while idle
    method Action store(State_t bestState, State_t curState, TimeStep_t timeStep)
      if (controlState == NIL);
      traceBStorage[timeStep][curState] <= bestState;
    endmethod

    method Action terminate (State_t finalState) if (controlState == NIL);
      traceBResult[valueOf(T)-1] <= finalState;               // seed last
      counter      <= fromInteger(valueOf(T)-2);              // start from T-2
      controlState <= TERMINATE;
    endmethod

    method Vector#(T, State_t) terminateRead();
      Vector#(T, State_t) out = newVector;
      for (Integer i = 0; i < valueOf(T); i = i + 1)
        out[i] = traceBResult[i];
      return out;
    endmethod

  endmodule

endpackage
