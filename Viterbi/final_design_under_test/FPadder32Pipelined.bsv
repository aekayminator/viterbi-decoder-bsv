package FPadder32Pipelined;

import FIFO :: *;
import FShow :: *;
import SpecialFIFOs :: *;

typedef struct {
    Bit#(1) sign;
    Bit#(8) exp;
    Bit#(23) frac;
} FP32 deriving (Bits, Eq, FShow);

typedef struct {
    Bit#(1) sign;
    Bit#(8) expCommon;
    Bit#(28) mantSum;
    Bool    isException;
} Stage1to2 deriving (Bits, Eq, FShow);

function Bit#(28) add28(Bit#(28) a, Bit#(28) b);
    Bit#(28) sum = 0;
    Bit#(1) carry = 0;

    for (Integer i = 0; i < 28; i = i + 1) begin
        Bit#(1) ai = a[i];
        Bit#(1) bi = b[i];
        Bit#(1) s = ai ^ bi ^ carry;
        Bit#(1) c = (ai & bi) | (carry & (ai ^ bi));
        sum[i] = s;
        carry = c;
    end
    return sum;
endfunction

function Tuple2#(Bit#(8), Bit#(23)) normalize_no_deps(Bit#(8) exp, Bit#(28) mant28);
    Bit#(8) newExp = exp;
    Bit#(23) finalFrac = 0;

    Bool carry = (mant28[27] == 1);
    Bit#(24) sig24;
    Bit#(1) g, r, s;

    if (carry) begin
        sig24 = mant28[27:4];
        g = mant28[3];
        r = mant28[2];
        s = (mant28[1] | mant28[0]);
        newExp = exp + 1;
    end else begin
        sig24 = mant28[26:3];
        g = mant28[2];
        r = mant28[1];
        s = mant28[0];
    end

    Bit#(1) lsb_sig = sig24[0];
    Bool roundUp = (g == 1) && ((r == 1) || (s == 1) || (lsb_sig == 1));
    Bit#(25) tmp = zeroExtend(sig24) + (roundUp ? 1 : 0);

    if (tmp[24] == 1) begin
        Bit#(24) normalized_sig = tmp[24:1];
        Bit#(8) incrementedExp = newExp + 1;

        if (incrementedExp == 8'hFF) begin
            finalFrac = 0;
            newExp = 8'hFF;
        end else begin
            newExp = incrementedExp;
            finalFrac = normalized_sig[22:0];
        end
    end else begin
        Bit#(24) rounded_sig = tmp[23:0];
        if (newExp == 8'hFF) begin
            finalFrac = 0;
            newExp = 8'hFF;
        end else begin
            finalFrac = rounded_sig[22:0];
        end
    end

    return tuple2(newExp, finalFrac);
endfunction

interface AdderIfc;
    method Action put(FP32 a, FP32 b);
    method ActionValue#(FP32) get;
endinterface

(* synthesize *)
module mkFPadder32(AdderIfc);
    FIFO#(Stage1to2) s1_to_s2_fifo <- mkSizedFIFO(2);
    FIFO#(FP32)     result_fifo   <- mkBypassFIFO;

    rule process_stage2;
        let s1_data = s1_to_s2_fifo.first;
        s1_to_s2_fifo.deq;

        FP32 out;

        if (s1_data.isException) begin
            out.sign = s1_data.sign;
            out.exp  = 8'hFF;
            out.frac = 0;
        end else begin
            let {newExp, newFrac} = normalize_no_deps(s1_data.expCommon, s1_data.mantSum);
            out.sign = s1_data.sign;
            out.exp  = newExp;
            out.frac = newFrac;
        end
        result_fifo.enq(out);
    endrule

    method Action put(FP32 a, FP32 b);
        Bit#(8) expDiff;
        Bit#(8) expCommon;
        Bit#(27) mantA = {1'b1, a.frac, 3'b000};
        Bit#(27) mantB = {1'b1, b.frac, 3'b000};
        Bit#(1) resultSign = a.sign;

        if (a.exp > b.exp) begin
            expDiff = a.exp - b.exp;
            Bit#(1) sticky = |(mantB & ((1 << expDiff) - 1));
            mantB = mantB >> expDiff;
            mantB[0] = mantB[0] | sticky;
            expCommon = a.exp;
        end else begin
            expDiff = b.exp - a.exp;
            Bit#(1) sticky = |(mantA & ((1 << expDiff) - 1));
            mantA = mantA >> expDiff;
            mantA[0] = mantA[0] | sticky;
            expCommon = b.exp;
        end

        Bit#(28) mantSum = add28(zeroExtend(mantA), zeroExtend(mantB));
        Bool exception = (expCommon == 8'hFF);

        s1_to_s2_fifo.enq(Stage1to2 {
            sign: resultSign,
            expCommon: expCommon,
            mantSum: mantSum,
            isException: exception
        });
    endmethod

    method ActionValue#(FP32) get;
        result_fifo.deq;
        return result_fifo.first;
    endmethod
endmodule

endpackage : FPadder32Pipelined
