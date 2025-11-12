package dut;


import SpecialFIFOs::*;
import FIFO::*;
import GetPut::*;
import Vector::*;
import ClientServer::*;
import FPadder32Pipelined::*;
import DReg::*;

typedef enum {EMISS, TRANS} Emission_t deriving(Bits,Eq);
typedef enum {NORMAL, FIRST} Input_t deriving(Bits,Eq);
typedef enum {INITIAL, NOTINITIAL, ZERO} OverallState_t deriving(Bits,Eq);
typedef enum {TRACEBACK, STORE, OUTPUT} TraceState_t deriving(Bits,Eq);
typedef struct {Emission_t emission; Bit#(5) memCurState; Bit#(9) memIndex;} MemReq_t deriving(Bits,Eq);

typedef struct {Bool endMark; Bool isFirst; MemReq_t memReq_op1; Bit#(5) state_op2; Bool isZero;} PreMem_t deriving(Bits,Eq);
typedef struct {Bool endMark; Bool isFirst; Emission_t emission; Bit#(32) memValue_op1; Bit#(32) value_op2; Bool isZero;} PreAdd_t deriving(Bits,Eq);
typedef struct {Bool endMark; Bool isFirst; Emission_t emission; Bit#(32) addOut; Bool isZero;} PreCom_t deriving(Bits,Eq);
typedef struct {Bool endMark; Bit#(10) timestep; Bit#(5) curState; Bit#(5) bestState; Bool isZero;} PreTrace_t deriving(Bits,Eq); 
typedef struct {Bit#(1) isInter; Bit#(5) state; Bit#(32) value;} PreMaxStr_t deriving(Bits,Eq); 
typedef struct {Bit#(10) timestep; Bit#(5) curState; Bit#(5) bestState;} TraceWrReq_t deriving(Bits,Eq);
typedef struct {Bit#(5) state; Bit#(32) value;} TempMax_t deriving(Bits,Eq);
typedef struct {Bit#(10) timestep; Bit#(5) bestState;} BackTrack_t deriving(Bits,Eq);
typedef struct {Bool endMark; Bool isFirst; Emission_t emission; Bool isZero;} AddMetadata deriving (Bits, Eq);

interface DuT_pins;
    method PreMem_t getMemAddr_mv();
    method ActionValue#(PreMaxStr_t) maxStore();
    method Action putMemVal_ma(Bit#(32) d, Bit#(32) d1);
    method Action putInpVal_ma(Bit#(32) in);
    method ActionValue#(TraceWrReq_t) traceStore_mav();
    method ActionValue#(TraceWrReq_t) traceWrite_mav();
    method ActionValue#(BackTrack_t) getBackTrack_mv();
    method Action putBackTrack_ma (Bit#(5) storedVal);
    method ActionValue#(Bit#(32)) outputPrint_mav();
    method Action putInitial_ma(Bit#(32) n, Bit#(32) m);
    method ActionValue#(Bit#(32)) outputPrint0_mav();
endinterface

(* synthesize *)
module mkdut(DuT_pins);

    FIFO#(PreMem_t) preMem_F <- mkSizedFIFO(2);
    FIFO#(PreAdd_t) preAdd_F <- mkSizedFIFO(2);
    FIFO#(AddMetadata) metadata_fifo <- mkSizedFIFO(2);
    FIFO#(PreCom_t) preCom_F <- mkSizedFIFO(2);
    FIFO#(PreTrace_t) preTrace_F <- mkSizedFIFO(2);
    FIFO#(PreMaxStr_t) preMax_F <- mkSizedFIFO(2);
    FIFO#(Bit#(9)) inp_F <- mkSizedFIFO(2);
    AdderIfc fpadder <- mkFPadder32;
    

    Reg#(OverallState_t) viterbiState <- mkReg(INITIAL);

    Reg#(Bit#(5)) numStates <- mkReg(0);
    Reg#(Bit#(9)) numObs <- mkReg(0);


    Reg#(Bool) vt_inter_is_ready <- mkReg(True); 
    Reg#(Bool) vt_is_ready <- mkReg(True);       
    
    Reg#(Bool) clear_inter_stall_dly <- mkDReg(False); 
    Reg#(Bool) clear_stall_dly <- mkDReg(False);      


    Reg#(Bit#(5)) iCounter_stage1 <- mkReg(1);
    Reg#(Bit#(5)) jCounter_stage1 <- mkReg(1);
    Reg#(Emission_t) emiss_stage1 <- mkReg(TRANS);
    Reg#(Input_t) inpIsFirst_stage1 <- mkReg(FIRST);

    (* descending_urgency = "stage_1_zero, stage_1_Endmark, stage_1_FirstInp, stage_1_Normal_Trans, stage_1_Normal_Emiss" *)

    rule stage_1_zero((viterbiState == NOTINITIAL) && (inp_F.first() == '0));
        $display($time," DEBUG: RULE stage_1_zero fired. Input is zero. Setting state to ZERO.");
        viterbiState <= ZERO;
        preMem_F.enq(PreMem_t{endMark:False, isFirst: False, memReq_op1: unpack('0), state_op2: 0, isZero : True});
    endrule


    rule stage_1_Endmark((viterbiState == NOTINITIAL) && (inp_F.first() == '1));
        let enqueued_data = PreMem_t{
            endMark:     True,
            isFirst:     (inpIsFirst_stage1 == FIRST),
            memReq_op1: MemReq_t{ emission: emiss_stage1, memCurState: iCounter_stage1, memIndex: '0 },
            state_op2:   0, isZero: False
        };
        preMem_F.enq(enqueued_data);
        inpIsFirst_stage1 <= FIRST;
        inp_F.deq();
    endrule


   
    rule stage_1_FirstInp(inpIsFirst_stage1 == FIRST && (viterbiState == NOTINITIAL) && (inp_F.first() != 0)
                           && (emiss_stage1 == TRANS || vt_inter_is_ready == True)); 
        let indfi = (emiss_stage1 == EMISS) ? inp_F.first() : 9'b0;
        let op2fi = (emiss_stage1 == EMISS) ? iCounter_stage1 : 5'b0;
        PreMem_t xfi = PreMem_t{
            endMark:     False,
            isFirst:     True,
            memReq_op1: MemReq_t{ emission: emiss_stage1, memCurState: iCounter_stage1, memIndex: indfi },
            state_op2: op2fi, isZero: False
        };


        if (iCounter_stage1 == numStates) begin
            iCounter_stage1 <= 1;
            emiss_stage1 <= unpack(~pack(emiss_stage1)); 

            if (emiss_stage1 == TRANS) begin 
                vt_inter_is_ready <= False; 
            end
            else begin 
                inpIsFirst_stage1 <= NORMAL; 
                inp_F.deq();
                vt_is_ready <= False;       
            end
        end
        else iCounter_stage1 <= iCounter_stage1 + 1;

        preMem_F.enq(xfi);
    endrule

    
    rule stage_1_Normal_Trans(inpIsFirst_stage1 == NORMAL && (emiss_stage1 == TRANS)
                               && (vt_is_ready == True)); 
        Bit#(5) op2nt = jCounter_stage1;
        let indnt = zeroExtend(jCounter_stage1); 

        PreMem_t xnt = PreMem_t{
            endMark:     False,
            isFirst:     False,
            memReq_op1: MemReq_t{ emission: emiss_stage1, memCurState: iCounter_stage1, memIndex: indnt },
            state_op2: op2nt, isZero: False
        };

        preMem_F.enq(xnt);

        if (jCounter_stage1 == numStates) begin
            jCounter_stage1 <= 1;
            if (iCounter_stage1 == numStates) begin
                iCounter_stage1 <= 1;
                emiss_stage1 <= unpack(~pack(emiss_stage1)); 
                vt_inter_is_ready <= False; 
            end
            else iCounter_stage1 <= iCounter_stage1 + 1;
        end
        else jCounter_stage1 <= jCounter_stage1 + 1;
    endrule

    
    rule stage_1_Normal_Emiss(inpIsFirst_stage1 == NORMAL && (emiss_stage1 == EMISS)
                               && (vt_inter_is_ready == True)); 
        Bit#(5) op2ne = iCounter_stage1;
        let indne = inp_F.first();
        PreMem_t xne = PreMem_t{
            endMark:     False,
            isFirst:     False,
            memReq_op1: MemReq_t{ emission: emiss_stage1, memCurState: iCounter_stage1, memIndex: indne },
            state_op2: op2ne, isZero: False
        };

        preMem_F.enq(xne);

        if (iCounter_stage1 == numStates) begin
            emiss_stage1 <= unpack(~pack(emiss_stage1)); 
            iCounter_stage1 <= 1;
            inp_F.deq();
            vt_is_ready <= False; 
        end
        else iCounter_stage1 <= iCounter_stage1 + 1;
    endrule
  rule memEnd_handle(preMem_F.first().endMark == True || preMem_F.first().isZero == True);
    let xhand = preMem_F.first();
    preMem_F.deq();
    preAdd_F.enq(PreAdd_t{endMark: xhand.endMark, isFirst: xhand.isFirst, emission: xhand.memReq_op1.emission, memValue_op1: 32'b0, value_op2: 32'b0, isZero: xhand.isZero});
  endrule

rule feed_adder_stage1;

        let xadd = preAdd_F.first();
        preAdd_F.deq();

        let a = unpack(xadd.memValue_op1);
        let b = unpack(xadd.value_op2);

        fpadder.put(a, b);

       let meta = AddMetadata {
            endMark:  xadd.endMark,
            isFirst:  xadd.isFirst,
            emission: xadd.emission,
            isZero:   xadd.isZero
        };
        metadata_fifo.enq(meta);
        
    endrule

    rule retrieve_from_adder_stage2;
        let y <- fpadder.get;
        
        let meta = metadata_fifo.first;
        metadata_fifo.deq;

        let addOut_y = pack(y);

        let com_data = PreCom_t{
            endMark:  meta.endMark,
            isFirst:  meta.isFirst,
            emission: meta.emission,
            addOut:   addOut_y, 
            isZero:   meta.isZero
        };

        preCom_F.enq(com_data);

    endrule




    rule rl_clear_inter_stall_delay (clear_inter_stall_dly);
        vt_inter_is_ready <= True;
        clear_inter_stall_dly <= False;
    endrule

    rule rl_clear_stall_delay (clear_stall_dly);
        vt_is_ready <= True;
        clear_stall_dly <= False;
    endrule

    Reg#(Bit#(5)) iCounter_Comp <- mkReg(1);
    Reg#(Bit#(5)) jCounter_Comp <- mkReg(1);
    Reg#(TempMax_t) tempMaxj <- mkReg(unpack('1));
    Reg#(TempMax_t) tempMaxi <- mkReg(unpack('1));

    Reg#(TraceState_t) traceStage_State <- mkReg(STORE);
    Reg#(Bit#(32)) valOut <- mkReg(0);

    Reg#(Bit#(10)) timeS <- mkReg(1);

    (* descending_urgency = "compare_stage_zero, compare_Stage_EndMarker, compare_Stage_First, compare_Stage_Emission, compare_Stage_Transition" *)
    rule compare_stage_zero(preCom_F.first().isZero == True);
        let xzero = preCom_F.first();
        preCom_F.deq();
        let trace_en = PreTrace_t{
            endMark:   False,
            timestep: timeS,
            curState: 0, 
            bestState: 0, 
            isZero: True
        };
        preTrace_F.enq(trace_en);
    endrule

    rule compare_Stage_First((preCom_F.first()).isFirst == True);
        let xcf = preCom_F.first();
        if (xcf.emission == EMISS) begin
            if (xcf.addOut < tempMaxi.value) begin
                tempMaxi <= TempMax_t{state: iCounter_Comp, value: xcf.addOut};
            end
            
            preMax_F.enq(PreMaxStr_t{isInter: 0, state: iCounter_Comp, value: xcf.addOut});
            if (iCounter_Comp == numStates) begin
                clear_stall_dly <= True;  
            end
        end
        else begin
            
            preMax_F.enq(PreMaxStr_t{isInter: 1, state: iCounter_Comp, value: xcf.addOut});
            if (iCounter_Comp == numStates) begin
                clear_inter_stall_dly <= True; 
            end
        end

        if (iCounter_Comp == numStates) iCounter_Comp <= 1;
        else iCounter_Comp <= iCounter_Comp + 1;
        preCom_F.deq();
    endrule

    rule compare_Stage_EndMarker((preCom_F.first()).endMark == True && traceStage_State == STORE);
        let trace_enq = PreTrace_t{
            endMark:   True,
            timestep: timeS-1,
            curState: tempMaxi.state,
            bestState:'0, isZero: False
        };
        valOut <= tempMaxi.value;
        preTrace_F.enq(trace_enq);
        preCom_F.deq();

        timeS <= 1;
        iCounter_Comp <= 1;
        jCounter_Comp <= 1;
        tempMaxj <= unpack('1);
        tempMaxi <= unpack('1);
    endrule

   rule compare_Stage_Transition((preCom_F.first()).emission == TRANS && (preCom_F.first()).endMark == False);
        let xcom = preCom_F.first();

        if(jCounter_Comp == numStates) begin
            if (xcom.addOut < tempMaxj.value) begin
                preMax_F.enq(PreMaxStr_t{isInter: 1, state: iCounter_Comp, value: xcom.addOut});
                let trace_enq = PreTrace_t{
                    endMark:   False,
                    timestep: timeS,
                    curState: iCounter_Comp,
                    bestState: jCounter_Comp, isZero: False
                };
                preTrace_F.enq(trace_enq);
            end
            else begin
                preMax_F.enq(PreMaxStr_t{isInter: 1, state: iCounter_Comp, value: tempMaxj.value});
                let trace_enq = PreTrace_t{
                    endMark:   False, 
                    timestep: timeS,
                    curState: iCounter_Comp,
                    bestState: tempMaxj.state, isZero: False
                };
                preTrace_F.enq(trace_enq);
            end
            jCounter_Comp <= 1;
            tempMaxj <= unpack('1);

            if (iCounter_Comp == numStates) begin
                iCounter_Comp <= 1;
                tempMaxi <= unpack('1);
                clear_inter_stall_dly <= True;
            end
            else iCounter_Comp <= iCounter_Comp + 1;
        end
        else begin
            if (xcom.addOut < tempMaxj.value) begin
                tempMaxj <= TempMax_t{state: jCounter_Comp, value: xcom.addOut};
            end
            jCounter_Comp <= jCounter_Comp + 1;
        end
        preCom_F.deq();
    endrule

    
    rule compare_Stage_Emission((preCom_F.first()).emission == EMISS && (preCom_F.first()).endMark == False);
        let xcome = preCom_F.first();

        preMax_F.enq(PreMaxStr_t{isInter: 0, state: iCounter_Comp, value: xcome.addOut});

        if (xcome.addOut < tempMaxi.value) begin
            tempMaxi <= TempMax_t{state: iCounter_Comp, value: xcome.addOut};
        end
        if (iCounter_Comp == numStates) begin
            iCounter_Comp <= 1;
            timeS <= timeS + 1;
            clear_stall_dly <= True; 
        end
        else iCounter_Comp <= iCounter_Comp + 1;

        preCom_F.deq();
    endrule


    
    Vector#(2, Reg#(Bit#(5))) backTrackReg <- replicateM(mkReg(0));
    Reg#(Bool) fPrint_dreg <- mkDReg(False);
    Reg#(Bool) valPrint_dreg <- mkDReg(False);
    Reg#(Bit#(10)) countTime <- mkReg(0);
    Reg#(Bit#(10)) timeTotal <- mkReg(0);
    Reg#(Bool) index <- mkReg(False);
    Reg#(Bool) done <- mkReg(False);
    Wire#(Bool) wireisZero <- mkDWire(False);
    Wire#(Bool) wireisEnd <- mkDWire(False);

    rule trace_stage_endstore ((preTrace_F.first()).endMark == True && traceStage_State == STORE && (preTrace_F.first()).isZero == False);
        let xstagestore = preTrace_F.first(); 
        if (preTrace_F.first().timestep == 0) begin
            index <= True;
            traceStage_State <= OUTPUT;
            done <= True;
            backTrackReg[0] <= xstagestore.curState;
            preTrace_F.deq();
        end
        else begin
            traceStage_State <= TRACEBACK;
            preTrace_F.deq();                   
            timeTotal <= xstagestore.timestep;
            countTime <= xstagestore.timestep;
            index <= False;
            backTrackReg[1] <= xstagestore.curState; 
        end
    endrule

    rule wirezero(preTrace_F.first().isZero == True);
        wireisZero <= True;
    endrule
    rule wireend(preTrace_F.first().isZero == True);
        wireisEnd <= True;
    endrule


    method ActionValue#(TraceWrReq_t) traceStore_mav() if (wireisEnd == False && traceStage_State == STORE && wireisZero == False);
        let xstore = preTrace_F.first();
        TraceWrReq_t xstorreq;
        xstorreq = TraceWrReq_t{timestep: xstore.timestep, curState: xstore.curState, bestState: xstore.bestState};
        preTrace_F.deq();
        return xstorreq;
    endmethod

    method ActionValue#(TraceWrReq_t) traceWrite_mav() if (traceStage_State == TRACEBACK && index == True);
        TraceWrReq_t xstorreq;
        xstorreq = TraceWrReq_t{timestep: countTime, curState: 1, bestState: backTrackReg[1]};
        backTrackReg[1] <= backTrackReg[0];
        if (countTime == 1) begin
            traceStage_State <= OUTPUT;
            index <= True;
        end
        else begin
            countTime <= countTime - 1;
            index <= False;
        end 
        return xstorreq;
    endmethod

    method ActionValue#(BackTrack_t) getBackTrack_mv() if ((traceStage_State == TRACEBACK && countTime != 0 && index == False) || traceStage_State == OUTPUT && index == False);
        BackTrack_t ybttrack;
        index <= True;
        if (traceStage_State == TRACEBACK && countTime != 0 && index == False) begin
            ybttrack = BackTrack_t{timestep: countTime, bestState: backTrackReg[1]};
        end
        else begin
            ybttrack = BackTrack_t{timestep: countTime, bestState: 1};
            if (countTime == timeTotal) done <= True;
            else countTime <= countTime + 1;          
        end
        return ybttrack;
    endmethod

    method Action putBackTrack_ma (Bit#(5) storedVal);
        backTrackReg[0] <= storedVal;
    endmethod

    method ActionValue#(Bit#(32)) outputPrint0_mav() if (wireisZero == True && traceStage_State == STORE);
        Bit#(32) xret;
        xret = 32'b0;
        preTrace_F.deq(); 
        return xret;
    endmethod

    method ActionValue#(Bit#(32)) outputPrint_mav() if ((traceStage_State == OUTPUT) && index == True);

        Bit#(32) xret;

        if (done) begin
            valPrint_dreg <= True;
            done <= False;
        end
        if (valPrint_dreg) begin
            xret = valOut;
            fPrint_dreg <= True;
        end
        else if (fPrint_dreg) begin
            xret = 32'hFFFF_FFFF;
            traceStage_State <= STORE;
        end
        else begin
            xret = {27'b0, backTrackReg[0]};
            if (done == False) begin
                index <= False;
            end
        end
        return xret;
    endmethod

    method Action putInpVal_ma(Bit#(32) in);
        inp_F.enq(in[8:0]);
    endmethod

    method ActionValue#(PreMaxStr_t) maxStore();
        let sp = preMax_F.first();
        preMax_F.deq();
        return sp;
    endmethod

    method Action putInitial_ma(Bit#(32) n, Bit#(32) m) if (viterbiState == INITIAL);
        viterbiState <= NOTINITIAL;
        numStates <= n[4:0];
        numObs <= m[8:0];
        inpIsFirst_stage1 <= FIRST;
        iCounter_stage1 <= 1;
        jCounter_stage1 <= 1;
        iCounter_Comp <= 1;
        jCounter_Comp <= 1;
        emiss_stage1 <= TRANS;
        tempMaxj <= unpack('1);
        tempMaxi <= unpack('1);
        timeS <= 1;
    endmethod

    method PreMem_t getMemAddr_mv() if ((preMem_F.first()).endMark == False);
        let xmem = preMem_F.first();
        return xmem;
    endmethod

    method Action putMemVal_ma(Bit#(32) d, Bit#(32)d1) if (((preMem_F.first()).endMark == False) && (preMem_F.first().isZero == False));
        let xval = preMem_F.first();
        PreAdd_t add_data;
        if (xval.isFirst && xval.memReq_op1.emission == TRANS) begin
        add_data = PreAdd_t{
            endMark:     xval.endMark,
            isFirst:     xval.isFirst,
            emission:     xval.memReq_op1.emission,
            memValue_op1: d,
            value_op2:     0, isZero: xval.isZero
        };
        end
        else begin
        add_data = PreAdd_t{
            endMark:     xval.endMark,
            isFirst:     xval.isFirst,
            emission:     xval.memReq_op1.emission,
            memValue_op1: d,
            value_op2: d1, isZero: xval.isZero
        };
        end
        preAdd_F.enq(add_data);
        preMem_F.deq();
    endmethod

endmodule

endpackage