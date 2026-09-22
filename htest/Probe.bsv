package Probe;

import HwcoreCfg::*;

import Vector::*;
import RegIf::*;
import Fabric::*;

// 量交换网用的探针：四个纯组合的桩挂在 mkFabric 上，钉死在 8 位地址、32 位数据。
// 桩之所以取组合，是为了让量到的数尽量只含译码本身。
(* synthesize *)
module mkFabricProbe(RegIf#(AW, DW));
  function Device#(AW, DW) dev(Integer i) =
    Device { base: fromInteger(i * 16), span: 16,
             regs: interface RegIf;
                     method ActionValue#(RegRsp#(DW)) access(RegReq#(AW, DW) r);
                       return RegRsp { rdata: zeroExtend(r.addr), err: False };
                     endmethod
                   endinterface };
  Vector#(4, Device#(AW, DW)) devs = genWith(dev);
  let f <- mkFabric(devs);
  return f;
endmodule

endpackage
