package FairTb;

import Vector::*;
import RegIf::*;
import Fabric::*;
import Fakes::*;

// 只问一件事：一个一刻不停的发起方会不会把另一个饿死。
//
// 判据是「排在后面那个跑得完」，不是「跑得快」。固定优先级下前面那个永远有请求，
// 后面那个一次也轮不到——表现是跑不完而不是跑得慢，所以超时也是判据的一部分。
(* synthesize *)
module mkFairTb(Empty);
  RegIf#(8, 32)     f <- mkFast;
  RegTarget#(8, 32) s <- mkSlow(4);

  Vector#(1, Device#(8, 32))     fast = cons(device(8'h00, 8'h10, f, tagged Invalid), nil);
  Vector#(1, SlowDevice#(8, 32)) slow = cons(slowDevice(8'h20, 8'h10, s, tagged Invalid), nil);
  RegTarget#(8, 32) fab <- mkFabricT(fast, slow);

  // 前面这个一刻不停，而且到超时也跑不完——它得一直占着，才谈得上饿死后面的。
  // 圈数给少了它自己先收工，后面那个于是照样跑得完，判据就白设了
  FakeMgr hog <- mkProg(8'h04, 32'hD4D4D4D4, 3000, 0);
  FakeMgr lil <- mkProg(8'h24, 32'hE5E5E5E5, 4,    0);

  Vector#(2, RegManager#(8, 32)) ms = cons(hog.m, cons(lil.m, nil));
  Empty arb <- mkArb(ms, fab);

  Reg#(Bit#(16)) cyc <- mkReg(0);

  rule timeout;
    cyc <= cyc + 1;
    if (cyc > 4000) begin
      $display("TIMEOUT the second initiator never got the bus");
      $finish(1);
    end
  endrule

  rule fini (lil.fin);
    if (lil.bad) $display("FAIL the starved initiator read back the wrong data");
    else $display("PASS fair: a back to back initiator does not starve the other one");
    $finish(lil.bad ? 1 : 0);
  endrule
endmodule

endpackage
