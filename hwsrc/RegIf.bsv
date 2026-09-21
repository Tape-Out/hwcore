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
// 发起方在收到响应之前必须把 valid 与 req 顶着不动。因此「收到响应」
// 就意味着「请求已被接收」——只做一次一笔的发起方可以不看 ready。
// 要连发（上一笔还没答就送下一笔）的发起方才必须看。
interface RegManager#(numeric type aw, numeric type dw);
  (* always_ready *) method Bool                valid;
  (* always_ready *) method RegReq#(aw, dw)     req;
  (* always_ready, always_enabled *) method Action ready(Bool r);
  (* always_ready, always_enabled *) method Action resp(Bool v, RegRsp#(dw) x);
endinterface

// RegManager 的对偶：一个**会停顿**的目标。
//
// RegIf 的 access 是一次就答的动作值，表达不了「这次答不上来，等我几拍」，
// 而缓存缺失正是这个形状；RegManager 又只能当发起方。缓存的核这一侧因此
// 无处安放——这是扁平契约第一次不够用的地方，也是当初契约写「两个 Server」
// 的理由。这里只补最小的一块：答不上来就把 ready 拉低。
//
// 不上整套 Server：E23 量过 Server 在小模块上贵 39.3%，而这里要的不是
// 排队与背压的全套语义，只是一个「还没好」的信号。
interface RegTarget#(numeric type aw, numeric type dw);
  (* always_ready, always_enabled *)
  method Action req(Bool valid, RegReq#(aw, dw) r);
  (* always_ready *) method Bool           ready;     // 这一拍收得下吗
  (* always_ready *) method Bool           rspValid;  // 这一拍有答复吗
  (* always_ready *) method RegRsp#(dw)    rsp;
endinterface

// 发起方接目标。装配的 pipe 段生成的就是它。
//
// 发与收分两条规则：有的目标答复是从请求组合出来的（地址图 mkFabricT 就是这样，
// 零等待的设备当拍答完），那种目标的 rspValid 读的正是 req 写的那条线，同一条
// 规则里又写又读是 G0004。两条规则仍在同一拍跑，一拍也不多花。
module mkPipe#(RegManager#(aw, dw) m, RegTarget#(aw, dw) t)(Empty);
  rule send;
    t.req(m.valid, m.req);
    m.ready(t.ready);
  endrule
  rule take;
    m.resp(t.rspValid, t.rsp);
  endrule
endmodule

// m 个发起方共用一个会停顿的目标：轮转授予，一笔在途期间不换人。
//
// 不设仲裁队列：发起方在收到答复之前顶着 valid 与 req 不动（RegManager 的约定），
// 所以「记住这一笔是谁的」就够了，不需要标签，也不会乱序。
//
// 公平由轮转保证。固定优先级会让缓存一忙起来核就饿死——那是仿真里偶尔看得见、
// 流片后天天看得见的毛病。
module mkArb#(Vector#(m, RegManager#(aw, dw)) ms, RegTarget#(aw, dw) t)(Empty)
    provisos (Add#(1, _x, m));
  Reg#(Bit#(TLog#(TAdd#(m, 1))))         turn <- mkReg(0);
  Reg#(Maybe#(Bit#(TLog#(TAdd#(m, 1))))) cur  <- mkReg(tagged Invalid);

  Vector#(m, Wire#(Bool))          gnt  <- replicateM(mkDWire(False));
  Vector#(m, Wire#(RegRsp#(dw)))   mrsp <- replicateM(
      mkDWire(RegRsp { rdata: 0, err: False }));

  Wire#(Bool)                     actW <- mkDWire(False);
  Wire#(Bool)                     goW  <- mkDWire(False);
  Wire#(Bit#(TLog#(TAdd#(m, 1)))) whoW <- mkDWire(0);
  Wire#(Bit#(TLog#(TAdd#(m, 1)))) selW <- mkDWire(0);

  rule issue;
    Bit#(TLog#(TAdd#(m, 1))) s = 0;
    Bool any = False;
    // 轮转要在更宽的类型里算：turn + i 最大 2*(m-1)，在索引自己的位宽里会回绕，
    // 回绕之后那句范围修正就救不回来，某个发起方于是一次也轮不到。
    // 宽一位就够，而且必须跟着 m 走——写死 Bit#(8) 在 m 大于 128 时反而不够。
    for (Integer i = 0; i < valueOf(m); i = i + 1) begin
      Bit#(TAdd#(TLog#(TAdd#(m, 1)), 1)) w8 = zeroExtend(turn) + fromInteger(i);
      if (w8 >= fromInteger(valueOf(m))) w8 = w8 - fromInteger(valueOf(m));
      Bit#(TLog#(TAdd#(m, 1))) w = truncate(w8);
      if (!any && ms[w].valid) begin s = w; any = True; end
    end

    Bool go = False;
    RegReq#(aw, dw) rq = unpack(0);
    Bit#(TLog#(TAdd#(m, 1))) who = 0;
    Bool act = False;
    if (cur matches tagged Valid .c) begin
      who = c;
      act = True;
    end else if (any) begin
      go  = True;
      rq  = ms[s].req;
      who = s;
      act = True;
    end
    t.req(go, rq);
    actW <= act;
    goW  <= go;
    whoW <= who;
    selW <= s;
  endrule

  // 收答复必须另起一条规则，理由同 mkPipe
  rule collect;
    Bool done = actW && t.rspValid;
    Maybe#(Bit#(TLog#(TAdd#(m, 1)))) ncur = cur;
    Bit#(TLog#(TAdd#(m, 1)))         nturn = turn;
    if (done) begin
      ncur  = tagged Invalid;
      Bit#(TAdd#(TLog#(TAdd#(m, 1)), 1)) nx = zeroExtend(whoW) + 1;
      if (nx >= fromInteger(valueOf(m))) nx = 0;
      nturn = truncate(nx);
    end else if (goW)
      ncur = tagged Valid selW;
    cur  <= ncur;
    turn <= nturn;

    for (Integer i = 0; i < valueOf(m); i = i + 1)
      if (done && whoW == fromInteger(i)) begin
        gnt[i]  <= True;
        mrsp[i] <= t.rsp;
      end
  endrule

  rule drive;
    for (Integer i = 0; i < valueOf(m); i = i + 1) begin
      ms[i].ready(gnt[i]);
      ms[i].resp(gnt[i], mrsp[i]);
    end
  endrule
endmodule

endpackage
