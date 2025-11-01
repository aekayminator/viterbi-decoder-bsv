package dut;

import typedefs::*;
import SpecialFIFOs::*;

typedef enum {EMISS, TRANS} emission_t deriving(Bits,Eq);
typedef enum {ENDMARKER, NORMAL} input_t deriving(Bits,Eq);

typedef struct {emission_t Emission, Bit#(5) MemCurState, Bit#(9) MemIndex} memReq_t deriving(Bits,Eq);
typedef struct {memReq_t MemReq_op1, Bit#(32) Value_op2} preMem_t deriving(Bits,Eq);
typedef struct {emission_t Emission, Bit#(32) MemValue_op1, Bit#(32) Value_op2} preAdd_t deriving(Bits,Eq);
typedef struct {emission_t Emission, Bit#(32) AddOut} preCom_t deriving(Bits,Eq);
typedef struct {Bit#(5) CurState, Bit#(5) BestState, input_t EndMark} preTrace_t deriving(Bits,Eq); //realised i need endmark, yet to add that everywhere throughout the pipeline
typedef struct {Bit#(5) State, Bit#(32) Value} tempMax_t deriving(Bits,Eq);

interface DuT_pins;
    method memReq_t getMemAddr_mv();
    method Action putMemVal_ma(Bit#(32) d);
    method Bit#(1) getInp_mv();
    method Action putInpVal_ma(Bit#(32) in);
    //add methods for populating trace
    //add methods to handle backtracking of trace
    //add initialise method to read Ndat
endinterface

module mkdut;

    fpAdd_Ifc fpAdd1 <- mkfpadd();
    FIFO#(preMem_t) preMem_F <- mkSizedFIFO(2);
    FIFO#(preAdd_t) preAdd_F <- mkSizedFIFO(2);
    FIFO#(preCom_t) preCom_F <- mkSizedFIFO(2);
    FIFO#(traceWr_t) preTrace_F <- mkSizedFIFO(2);

    Reg#(tempMax_t) tempMaxj <- mkReg(pack(0));
    Reg#(tempMax_t) tempMaxi <- mkReg(pack(0));
    Reg#(Bit#(5)) iCounter_stage1 <- mkReg(0);
    Reg#(Bit#(5)) jCounter_stage1 <- mkReg(0);
    Reg#(Bit#(5)) iCounter_Comp <- mkReg(1);
    Reg#(Bit#(5)) jCounter_Comp <- mkReg(1);

    Reg#(Bit#(5)) numStates <- mkReg(0);
    Reg#(Bit#(9)) numObs <- mkReg(0);
    Reg#(Bit#(32)) inp <- mkReg(0);

    Vector#(32, Bit#(32)) prevMax_inter <- replicateM(mkReg(0));
    Vector#(32, Bit#(32)) prevMax <- replicateM(mkReg(0));

    rule stage_1();
    // have to fill stage 1 methods at the bottom as well
    //when to increment icounter and jcounterstage 1
    //enqueue logic for preMem_F 
    //FFFFFFFF Marker logic
    endrule

    rule addStart_Stage();
        let xadd = preAdd_F.first();
        fpAdd1.sumStart_ma(xadd.MemValue_op1,xadd.Value_op2);
        preAdd_F.deq();
    endrule

    rule addEnd_Stage();
        let yadd = fpAdd1.sumEnd_mav();
        preCom_F.enq(yadd);
    endrule
    
    rule initialise();
        //reset everything
    endrule

    (* decending_urgency = “compare_Stage_Marker, compare_Stage_Emission, compare_Stage_Transition” *)

    rule compare_Stage_Marker(input_t == ENDMARKER);
        preTrace_F.enq({0,0,ENDMARKER});
        preComp_F.deq();
        iCounter_Comp <= 0;
        jCounter_COmp <= 0;
    endrule

    rule compare_Stage_Emission(!((preCom_F.first()).Emission));
        let xcom = preCom_F.first();
        if(jCounter_Comp == COMP_LIM) begin //have to figure out COMP_LIM
            if (xcom.Addout > tempMaxj.Value) begin
                prevMax_inter[iCounter_Comp] <= xcom.Addout;
                preTrace_F.enq({iCounter_Comp, jCounter_Comp});
            end
            else begin
                prevMax_inter[iCounter_Comp] <= tempMaxj.Value;
                preTrace_F.enq({iCounter_Comp, tempMaxj.State, NORMAL});                
            end
            jCounter_Comp <= 0;
            iCounter_Comp <= iCounter_Comp + 1;
        end
        else begin
            if (xcom.Addout > tempMaxj.Value) begin
                tempMaxj.Value <= xcom.Addout;
                tempMaxj.State <= jCounter_Comp;
            end
        end

        if (iCounter_Comp == COMP_LIM) begin
            iCounter_Comp <= 0;
        end

        preCom_F.deq();
    endrule

    rule compare_Stage_Transition(((preCom_F.first()).Emission));
        let xcome = preCom_F.first();
        prevMax[iCounter_Comp] <= xcome.Addout;
        if (xcome.Addout > tempMaxi.Value) begin
            tempMaxi.Value <= xcome.Addout;
            tempMaxi.State <= iCounter_Comp;
        end
        iCounter_Comp <= iCounter_Comp + 1;
        preCom_F.deq();
    endrule

    method Bit#(1) getInp_mv();
        return (iCounter_stage1 == COMP_LIM) && (jCounter_stage1 == COMP_LIM);        //stage 1 logic
    endmethod

    method putInpVal_ma(Bit#(32) in);
        inp <= in;
        //reset counters
    endmethod

    method 
        //to read NM values Condition should be if state == initial
    endmethod

    method memReq_t getMemAddr_mv();
        let xmem = preMem_F.first();
        return xmem.MemReq_op1;   // Bit#(11)
    endmethod

    method Action putMemVal_ma(Bit#(32) d);
        let xval = preMem_F.first();
        preAdd_F.enq({xval.Emission, d, xval.Value_op2});
        preMem_F.deq();
    endmethod 

    //big yet to write logic for termination; write the logic such that loads to trace are backpressured in the FIFO

endmodule


endpackage
