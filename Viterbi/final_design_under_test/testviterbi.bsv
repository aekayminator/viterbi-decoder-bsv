package testviterbi;

import RegFile :: *;
import Vector   :: *;
import typedefs :: *;
import dut      :: *;

typedef enum {START, NORMALTB, ENDTB} TestBenchState_t deriving(Bits,Eq);

module mkfile_io (Empty);

  DuT_pins dut <- mkdut; 
  Reg#(TestBenchState_t) testbench_state <- mkReg(START);

  RegFile#(Bit#(32), Bit#(32)) emissMem  <- mkRegFileLoad("B.dat",     0, 1023);
  RegFile#(Bit#(32), Bit#(32)) transMem  <- mkRegFileLoad("A.dat",     0, 1023);
  RegFile#(Bit#(32), Bit#(32)) ndat      <- mkRegFileLoad("N.dat",     0,   2);
  RegFile#(Bit#(32), Bit#(32)) input_rd  <- mkRegFileLoad("input.dat", 0, 1023);
  RegFile#(Bit#(10), Bit#(32)) workMem <- mkRegFile(0, 1023);
  Reg#(File) memory_wr <- mkReg(InvalidFile);
  Reg#(Bit#(32)) in_addr <- mkReg(0);
  Reg#(UInt#(32)) nobs <- mkReg(0);
  Reg#(UInt#(32)) nsts <- mkReg(0);

  rule start_tb (testbench_state == START);
    $display($time," DEBUG: RULE start_tb fired. testbench_state == START.");
    File file <- $fopen("output.dat","w");
    if (file == InvalidFile) begin
      $finish(0);
    end
    testbench_state <= NORMALTB;
    in_addr         <= 0;
    memory_wr       <= file;
    nobs <= unpack(ndat.sub(1));
    nsts <= unpack(ndat.sub(0));
    let xno = ndat.sub(0);
    let xmo = ndat.sub(1);
    dut.putInitial_ma(xno, xmo);
  endrule

  rule input_service (testbench_state == NORMALTB);
    let xins = input_rd.sub(in_addr);
    dut.putInpVal_ma(xins);
    in_addr <= in_addr + 1;
  endrule

  rule memService (testbench_state == NORMALTB);
    let reqk = dut.getMemAddr_mv();
    let req = reqk.memReq_op1;
    UInt#(32) cur  = zeroExtend(unpack(req.memCurState));
    UInt#(32) idx  = zeroExtend(unpack(req.memIndex));
    UInt#(32) addr_emission     = nobs * (cur - 1) + (idx-1);
    UInt#(32) addr_non_emission = nsts * idx      + (cur - 1);
    Bit#(32) d = (req.emission == EMISS)
                   ? emissMem.sub(pack(addr_emission))
                   : transMem.sub(pack(addr_non_emission));
    Bit#(10) d1_addr = (req.emission == EMISS) ? zeroExtend(reqk.state_op2) - 10'd1 : zeroExtend(reqk.state_op2) - 10'd1 + pack(nsts)[9:0];
    Bit#(32) d1 = workMem.sub(d1_addr);
    dut.putMemVal_ma(d,d1);
  endrule

  rule trace_Wr_req (testbench_state == NORMALTB);
    let wr_req <- dut.traceWrite_mav();
    UInt#(32) ts = zeroExtend(unpack(wr_req.timestep));
    UInt#(32) cs = zeroExtend(unpack(wr_req.curState));
    UInt#(32) wr_addr = ((ts-1)*nsts) + cs + ((2*nsts) - 1);
    workMem.upd(pack(wr_addr)[9:0], zeroExtend(unpack(wr_req.bestState)));
  endrule

  rule trace_Str_req (testbench_state == NORMALTB);
    let wr_req <- dut.traceStore_mav();
    UInt#(32) ts = zeroExtend(unpack(wr_req.timestep));
    UInt#(32) cs = zeroExtend(unpack(wr_req.curState));
    UInt#(32) wr_addr = ((ts-1)*nsts) + cs + ((2*nsts) - 1);
    workMem.upd(pack(wr_addr)[9:0], zeroExtend(unpack(wr_req.bestState)));
  endrule

  rule backTrack_service (testbench_state == NORMALTB);
    let xbts <- dut.getBackTrack_mv();
    UInt#(32) ts = zeroExtend(unpack(xbts.timestep));
    UInt#(32) bs = zeroExtend(unpack(xbts.bestState));
    UInt#(32) rd_addr = ((ts-1)*nsts) + bs + ((2*nsts) - 1);
    let stored_val = workMem.sub(pack(rd_addr)[9:0]);
    dut.putBackTrack_ma(stored_val[4:0]);
  endrule

  rule getMaxStr (testbench_state == NORMALTB);
    let sp2 <- dut.maxStore();
    Bit#(10) wr_addr;
    if (sp2.isInter == 1) begin
      wr_addr = zeroExtend(sp2.state)-10'd1;
      workMem.upd(wr_addr, sp2.value);
    end
    else begin
      wr_addr = zeroExtend(sp2.state)-10'd1+ pack(nsts)[9:0];
      workMem.upd(wr_addr, sp2.value);
    end
  endrule

  rule w_service (testbench_state == NORMALTB);
    let wr_data <- dut.outputPrint_mav();
    $fwrite(memory_wr, "%08h\n", wr_data);
  endrule

  rule w_zero (testbench_state == NORMALTB);
    let wr_data <- dut.outputPrint0_mav();
    $fwrite(memory_wr, "%08h", wr_data);
    $fclose(memory_wr);
    testbench_state <= ENDTB;
    $finish(0);
  endrule

endmodule: mkfile_io
endpackage
