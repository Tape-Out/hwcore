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

// 会停顿的设备在地址图里的落位。零等待的走 Device，这一路走 SlowDevice。
typedef struct {
  Bit#(aw)            base;
  Bit#(aw)            span;
  RegTarget#(aw, dw)  regs;
  Maybe#(Bool)        irq;
} SlowDevice#(numeric type aw, numeric type dw);

function SlowDevice#(aw, dw) slowDevice(Bit#(aw) base, Bit#(aw) span,
                                        RegTarget#(aw, dw) regs,
                                        Maybe#(Bool) irq) =
  SlowDevice { base: base, span: span, regs: regs, irq: irq };

// narrow 的会停顿版本。四个方法逐个转，只有地址要截。
function RegTarget#(bw, dw) narrowT(RegTarget#(nw, dw) r)
    provisos (Add#(a__, nw, bw));
  return (interface RegTarget;
    method Action req(Bool valid, RegReq#(bw, dw) q);
      r.req(valid, RegReq { addr:  truncate(q.addr),
                            write: q.write,
                            wdata: q.wdata,
                            wstrb: q.wstrb });
    endmethod
    method Bool        ready    = r.ready;
    method Bool        rspValid = r.rspValid;
    method RegRsp#(dw) rsp      = r.rsp;
  endinterface);
endfunction

// 混合地址图：零等待的设备同拍答，慢设备把 ready 拉低让发起方等。
//
// 为什么要混：SRAM 宏、ROM 宏、缓存都是同步的，`RegIf` 的 access 是一次就答的
// 动作值，表达不了「等我几拍」。全库改成会停顿的目标是可以的，但那样每个外设
// 都要多一拍延迟——现有外设一拍不变才是对的，慢的那几个才付代价。
//
// 一次只有一笔在途：发起方在收到响应之前顶着 valid 与 req 不动（RegManager 的
// 约定），所以不需要标签，也不会乱序。
module mkFabricT#(Vector#(k, Device#(aw, dw)) devs,
                  Vector#(m, SlowDevice#(aw, dw)) slow)(RegTarget#(aw, dw))
    provisos (Add#(1, _x, m));

  // 状态只有 upd 一条规则写。方法与 drive 都只读状态、只发线——
  // 这样「读状态」与「读响应」对调用者的次序要求才不会打架：
  // drive < 调用方 < upd，`ready` 与 `rspValid` 能在同一条规则里读。
  Reg#(Maybe#(Bit#(TLog#(m)))) busy <- mkReg(tagged Invalid);
  Reg#(RegReq#(aw, dw))        held <- mkRegU;
  Reg#(Bool)                   sent <- mkReg(False);   // 慢设备收下了没有

  Wire#(Bool)                  takeV <- mkDWire(False);
  Wire#(Bit#(TLog#(m)))        takeI <- mkDWire(0);
  Wire#(RegReq#(aw, dw))       takeR <- mkDWire(unpack(0));
  Wire#(Bool)                  gotIt <- mkDWire(False);   // 慢设备接了
  Wire#(Bool)                  doneV <- mkDWire(False);   // 慢设备答了

  Wire#(Bool)        fastV <- mkDWire(False);
  Wire#(RegRsp#(dw)) fastX <- mkDWire(RegRsp { rdata: 0, err: True });
  Wire#(Bool)        slowV <- mkDWire(False);
  Wire#(RegRsp#(dw)) slowX <- mkDWire(RegRsp { rdata: 0, err: True });

  // 慢设备的 req 是 always_enabled，每拍都得驱动，所以单列一条规则
  rule drive;
    for (Integer i = 0; i < valueOf(m); i = i + 1) begin
      Bool mine = busy matches tagged Valid .b ? b == fromInteger(i) : False;
      Bool go = mine && !sent;
      slow[i].regs.req(go, RegReq { addr:  held.addr - slow[i].base,
                                    write: held.write,
                                    wdata: held.wdata,
                                    wstrb: held.wstrb });
      if (go && slow[i].regs.ready) gotIt <= True;
      if (mine && slow[i].regs.rspValid) begin
        slowV <= True;
        slowX <= slow[i].regs.rsp;
        doneV <= True;
      end
    end
  endrule

  // 状态机唯一的写者
  rule upd;
    if (doneV) begin
      busy <= tagged Invalid;
      sent <= False;
    end else if (takeV) begin
      busy <= tagged Valid takeI;
      held <= takeR;
      sent <= False;
    end else if (gotIt)
      sent <= True;
  endrule

  method Action req(Bool valid, RegReq#(aw, dw) r);
    if (valid && !isValid(busy)) begin
      Bool hitSlow = False;
      Bit#(TLog#(m)) which = 0;
      for (Integer i = 0; i < valueOf(m); i = i + 1)
        if (r.addr >= slow[i].base && r.addr < slow[i].base + slow[i].span) begin
          hitSlow = True;
          which   = fromInteger(i);
        end
      if (hitSlow) begin
        takeV <= True;
        takeI <= which;
        takeR <= r;
      end else begin
        // 零等待的那一路，包括未命中——未命中当场回错误，不占用在途
        RegRsp#(dw) rsp = RegRsp { rdata: 0, err: True };
        for (Integer i = 0; i < valueOf(k); i = i + 1)
          if (r.addr >= devs[i].base && r.addr < devs[i].base + devs[i].span) begin
            let x <- devs[i].regs.access(RegReq { addr:  r.addr - devs[i].base,
                                                  write: r.write,
                                                  wdata: r.wdata,
                                                  wstrb: r.wstrb });
            rsp = x;
          end
        fastV <= True;
        fastX <= rsp;
      end
    end
  endmethod

  method Bool ready = !isValid(busy);
  method Bool rspValid = fastV || slowV;
  method RegRsp#(dw) rsp = slowV ? slowX : fastX;
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
