package FabTb;

import HwcoreCfg::*;

import Vector::*;
import RegIf::*;
import Fabric::*;
import Fakes::*;

(* synthesize *)
module mkFabTb(Empty);
  RegIf#(AW, DW)     f <- mkFast;
  RegTarget#(AW, DW) s <- mkSlow(4);

  Vector#(1, Device#(AW, DW))     fast = cons(device('h00, 'h10, f, tagged Invalid), nil);
  Vector#(1, SlowDevice#(AW, DW)) slow = cons(slowDevice('h20, 'h10, s, tagged Invalid), nil);
  RegTarget#(AW, DW) fab <- mkFabricT(fast, slow);

  Reg#(Bit#(8))  ph   <- mkReg(0);
  Reg#(Bit#(16)) cyc  <- mkReg(0);
  Reg#(Bool)     bad  <- mkReg(False);
  Reg#(Bit#(16)) took <- mkReg(0);
  Reg#(Bool)     hold <- mkReg(False);
  Reg#(RegReq#(AW, DW)) q <- mkRegU;

  // 打一拍的快照：读 fab 的组合输出与写它的请求不能在同一条规则里
  Reg#(Bool)         rdy <- mkReg(True);
  Reg#(Bool)         rv  <- mkReg(False);
  Reg#(RegRsp#(DW))  rx  <- mkRegU;

  rule snap;
    rdy <= fab.ready;
    rv  <= fab.rspValid;
    rx  <= fab.rsp;
  endrule

  rule drive;
    fab.req(hold, q);
  endrule

  rule timeout;
    cyc <= cyc + 1;
    if (cyc > 2000) begin $display("TIMEOUT at phase %0d", ph); $finish(1); end
  endrule

  rule run;
    case (ph)
      // 零等待那一路：写进去、读回来，而且必须**同一拍**就答
      0: action
           q    <= RegReq { addr: 'h04, write: True, wdata: 'h1234ABCD, wstrb: '1 };
           hold <= True;
           ph   <= 1;
         endaction
      1: action
           hold <= False;
           ph   <= 2;
         endaction
      2: action
           if (!rv) begin
             $display("FAIL a zero wait device did not answer in the same cycle");
             bad <= True;
           end
           q    <= RegReq { addr: 'h04, write: False, wdata: 0, wstrb: '1 };
           hold <= True;
           ph   <= 3;
         endaction
      3: action hold <= False; ph <= 4; endaction
      4: action
           if (!rv || rx.rdata != 'h1234ABCD) begin
             $display("FAIL zero wait read back %08h", rx.rdata);
             bad <= True;
           end
           // 慢设备那一路：请求要顶着，直到答上来
           q    <= RegReq { addr: 'h24, write: True, wdata: 'h55AA55AA, wstrb: '1 };
           hold <= True;
           took <= 0;
           ph   <= 5;
         endaction
      // 顶着请求等。ready 必须在这期间落下去，答上来之后再抬起来。
      5: action
           took <= took + 1;
           if (rdy && took > 1) begin
             $display("FAIL the fabric stayed ready while a slow device was busy");
             bad <= True;
             ph  <= 9;
           end else if (rv) begin
             hold <= False;
             ph   <= 6;
           end
         endaction
      6: action
           if (took < 3) begin
             $display("FAIL the slow write answered in %0d cycles, too fast to be real",
                      took);
             bad <= True;
           end
           q    <= RegReq { addr: 'h24, write: False, wdata: 0, wstrb: '1 };
           hold <= True;
           took <= 0;
           ph   <= 7;
         endaction
      // 响应要在 rv 为真的**那一拍**就看：快照每拍都被覆盖，晚一拍读到的是空闲值
      7: action
           took <= took + 1;
           if (rv) begin
             if (rx.rdata != 'h55AA55AA) begin
               $display("FAIL the slow device read back %08h, want 55AA55AA", rx.rdata);
               bad <= True;
             end
             hold <= False;
             ph   <= 9;
           end
         endaction
      default: action
                 if (bad) $display("FAILED");
                 else $display("PASS fabric: a zero wait device still answers in the "
                               + "same cycle, and a slow one stalls until it is ready");
                 $finish(bad ? 1 : 0);
               endaction
    endcase
  endrule
endmodule

endpackage
