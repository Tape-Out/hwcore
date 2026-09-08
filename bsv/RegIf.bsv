package RegIf;

import Vector::*;

// 总线无关的寄存器访问契约。
// IP 只实现本接口，不认识任何具体总线；APB4 / AXI4-Lite / Wishbone / TL-UL
// 的绑定器分别住在 amba / wishbone / tilelink 仓里。
// 这样加一种总线是 +1 个适配器，而不是给每个 IP 各加一份包装。

typedef struct {
  Bit#(aw)           addr;
  Bool               write;
  Bit#(dw)           wdata;
  Bit#(TDiv#(dw, 8)) wstrb;
} RegReq#(numeric type aw, numeric type dw) deriving (Bits, FShow);

typedef struct {
  Bit#(dw) rdata;
  Bool     err;
} RegRsp#(numeric type dw) deriving (Bits, FShow);

interface RegIf#(numeric type aw, numeric type dw);
  method ActionValue#(RegRsp#(dw)) access(RegReq#(aw, dw) r);
endinterface

// 按字节选通合并写数据。所有绑定器与 IP 共用，避免各写一份写错。
function Bit#(dw) applyStrb(Bit#(dw) old, Bit#(dw) new_, Bit#(TDiv#(dw, 8)) strb)
    provisos (Mul#(TDiv#(dw, 8), 8, dw));
  Vector#(TDiv#(dw, 8), Bit#(8)) o = unpack(old);
  Vector#(TDiv#(dw, 8), Bit#(8)) n = unpack(new_);
  Vector#(TDiv#(dw, 8), Bit#(8)) m = newVector;
  for (Integer i = 0; i < valueOf(TDiv#(dw, 8)); i = i + 1)
    m[i] = (strb[i] == 1) ? n[i] : o[i];
  return pack(m);
endfunction

RegRsp#(dw) regErr = RegRsp { rdata: 0, err: True };

function RegRsp#(dw) regOk(Bit#(dw) d) = RegRsp { rdata: d, err: False };

// 发起方那一侧的契约。DMA、缓存、核都要自己发访存，而 RegIf 只描述被访问的一侧。
// 形态跟控制口一样是扁平的 always_ready 方法：E23 量过，Server 形态在小 IP 上
// 要贵 39.3%，而这里同样不需要它的排队语义。
interface RegManager#(numeric type aw, numeric type dw);
  (* always_ready *) method Bool                valid;
  (* always_ready *) method RegReq#(aw, dw)     req;
  (* always_ready, always_enabled *) method Action ready(Bool r);
  (* always_ready, always_enabled *) method Action resp(Bool v, RegRsp#(dw) x);
endinterface

endpackage
