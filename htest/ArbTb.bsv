package ArbTb;

import Vector::*;
import RegIf::*;
import Fabric::*;
import Fakes::*;

// 装配那一级的形状：三个发起方共用一张地址图，图里一快两慢。
//
// 单独测 mkFabricT 只证明了「慢的会停」；这里证明的是另一件事——答复不会串门。
// 慢设备答上来的那一拍，授予必须回到当初发起那一笔的人手里。轮转指着的那个当时
// 没在要、后面的人先被选中，而它在停顿期间又醒了过来——只有这种时刻才分得出
// 「记住是谁」与「每拍重新仲裁」的差别，所以三个发起方都带抖动。
(* synthesize *)
module mkArbTb(Empty);
  RegIf#(8, 32)     f <- mkFast;
  RegTarget#(8, 32) s <- mkSlow(4);

  Vector#(1, Device#(8, 32))     fast = cons(device(8'h00, 8'h10, f, tagged Invalid), nil);
  Vector#(1, SlowDevice#(8, 32)) slow = cons(slowDevice(8'h20, 8'h10, s, tagged Invalid), nil);
  RegTarget#(8, 32) fab <- mkFabricT(fast, slow);

  // p0 歇得比「轮转转回它」还久，轮到它的时候它正好没在要，于是慢设备那一笔
  // 由排在后面的人发起——轮转指针停在 p0 身上，而在途的是别人。p0 随后在停顿
  // 期间醒来，就成了「每拍重新仲裁」会挑中的那个。这一段间隔是照这个算出来的，
  // 不是随手填的：歇 3 拍就永远撞不上，测试台也就永远发现不了错发。
  FakeMgr p0 <- mkProg(8'h04, 32'hA1A1A1A1, 60, 17);   // 零等待那一路
  FakeMgr p1 <- mkProg(8'h24, 32'hB2B2B2B2, 60, 0);    // 会停顿那一路，一刻不停
  FakeMgr p2 <- mkProg(8'h28, 32'hC3C3C3C3, 60, 11);   // 同一个慢设备，另一个地址

  Vector#(3, RegManager#(8, 32)) ms = cons(p0.m, cons(p1.m, cons(p2.m, nil)));
  Empty arb <- mkArb(ms, fab);

  Reg#(Bit#(16)) cyc <- mkReg(0);

  rule timeout;
    cyc <= cyc + 1;
    if (cyc > 20000) begin
      $display("TIMEOUT p0 %0d p1 %0d p2 %0d",
               p0.fin ? 1 : 0, p1.fin ? 1 : 0, p2.fin ? 1 : 0);
      $finish(1);
    end
  endrule

  rule fini (p0.fin && p1.fin && p2.fin);
    Bool w = p0.bad || p1.bad || p2.bad;
    if (w)
      $display("FAIL an initiator read back data that was not its own: %0d %0d %0d",
               p0.bad ? 1 : 0, p1.bad ? 1 : 0, p2.bad ? 1 : 0);
    else
      $display("PASS arb: three initiators share one address map and every answer "
               + "goes back to whoever asked for it");
    $finish(w ? 1 : 0);
  endrule
endmodule

endpackage
