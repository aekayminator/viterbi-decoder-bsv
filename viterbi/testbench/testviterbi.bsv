package testviterbi;

import RegFile :: *;
import typedefs::*

typedef enum {WRITE, OPEN, ENDED} State deriving(Bounded, Bits, Eq);

(* synthesize *)

module mkfile_io (Empty);

Reg#(State)    rg_state <- mkReg(OPEN);

// Create Register files to use as inputs in a testbench
RegFile#(Bit#(32), Bit#(32)) memory_rd1 <- mkRegFileLoad("A.dat", 0, 1023);
RegFile#(Bit#(32), Bit#(32)) memory_rd2 <- mkRegFileLoad("B.dat", 0, 1023);
RegFile#(Bit#(32), Bit#(32)) input_rd <- mkRegFileLoad("input.dat", 0, INPUT_MAX-1);
Reg#(File)                   memory_wr <- mkReg(InvalidFile) ;


rule open(rg_state == OPEN) ; //Open Initially
    // Open the file and check for proper opening
    File file <- $fopen( "output.dat","w") ;
    if ( file == InvalidFile )
    begin
    $display("cannot open the file" );
    $finish(0);
    end
    rg_state <= WRITE;
    memory_wr <= file ; // Save the file in a Register
endrule

rule rd1_service ();
    let rd1_addr <= dut.get_rd1Addr();
    dut.put_rd1Data(memory_rd1.sub(rd1_addr));
endrule

rule rd2_service ();
    let rd2_addr <= dut.get_rd2Addr();
    dut.put_rd2Data(memory_rd2.sub(rd2_addr));
endrule

rule input_service ();
    let in_addr <= dut.get_inpAddr();
    dut.put_inpData(input_rd.sub(in_addr));
endrule

rule w_service (rg_state == WRITE);
    let wr_data <= dut.get_wrData();
    $fwrite(memory_wr, "%0h\n", wr_data);
    if (wr_data == 0) begin
        $fclose(memory_wr);
        rg_state <= ENDED;
    end
endrule

endmodule: mkfile_io


endpackage