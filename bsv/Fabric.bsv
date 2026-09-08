package Fabric;

import Vector::*;
import RegIf::*;

// 一个 IP 在地址空间里的落位。base 默认由 IP 自带，组装时可覆盖。
typedef struct {
  Bit#(aw)        base;
  Bit#(aw)        span;
  RegIf#(aw, dw)  regs;
  Maybe#(Bool)    irq;    // 无中断的 IP 填 Invalid
} Device#(numeric type aw, numeric type dw);

function Device#(aw, dw) device(Bit#(aw) base, Bit#(aw) span,
                                RegIf#(aw, dw) regs, Maybe#(Bool) irq) =
  Device { base: base, span: span, regs: regs, irq: irq };

// 把 IP 自己那点地址宽度接到片上的宽地址。IP 按它在 ip.yaml 里声明的
// contract.aw 例化，价目表也是照那个宽度量的；换算发生在这里，
// 而不是把每个 IP 都撑到 32 位——那样量出来的面积对不上账。
function RegIf#(bw, dw) narrow(RegIf#(nw, dw) r)
    provisos (Add#(a__, nw, bw));
  return (interface RegIf;
    method ActionValue#(RegRsp#(dw)) access(RegReq#(bw, dw) q);
      let x <- r.access(RegReq { addr:  truncate(q.addr),
                                 write: q.write,
                                 wdata: q.wdata,
                                 wstrb: q.wstrb });
      return x;
    endmethod
  endinterface);
endfunction

// 地址译码：命中则把局部偏移转给该 IP，未命中回错误。
// 译码在编译期完全展开，不产生运行时查表。
module mkFabric#(Vector#(k, Device#(aw, dw)) devs)(RegIf#(aw, dw));
  method ActionValue#(RegRsp#(dw)) access(RegReq#(aw, dw) r);
    RegRsp#(dw) rsp = RegRsp { rdata: 0, err: True };
    for (Integer i = 0; i < valueOf(k); i = i + 1) begin
      if (r.addr >= devs[i].base && r.addr < devs[i].base + devs[i].span) begin
        let x <- devs[i].regs.access(RegReq { addr:  r.addr - devs[i].base,
                                              write: r.write,
                                              wdata: r.wdata,
                                              wstrb: r.wstrb });
        rsp = x;
      end
    end
    return rsp;
  endmethod
endmodule

// 中断汇聚：值方法读出的是组合信号，放进 Vector 即成中断向量，直送 PLIC/ACLINT。
function Vector#(k, Bool) irqsOf(Vector#(k, Device#(aw, dw)) devs);
  function Bool one(Device#(aw, dw) d) = fromMaybe(False, d.irq);
  return map(one, devs);
endfunction

// 地址重叠检查。编译期求值，冲突直接让 bsc 报错而非拖到仿真。
function Bool overlaps(Vector#(k, Device#(aw, dw)) devs);
  Bool bad = False;
  for (Integer i = 0; i < valueOf(k); i = i + 1)
    for (Integer j = i + 1; j < valueOf(k); j = j + 1)
      if (devs[i].base < devs[j].base + devs[j].span &&
          devs[j].base < devs[i].base + devs[i].span) bad = True;
  return bad;
endfunction

endpackage
