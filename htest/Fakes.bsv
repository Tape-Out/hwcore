package Fakes;

// 测试台共用的假设备与假发起方。放在 tb/ 里而不是 bsv/ 里：它们不进任何一次流片。

import Vector::*;
import RegIf::*;

// 零等待的假存储：四个字，按 addr[3:2] 选。
// 一定要按地址存——多个发起方打同一个设备的不同地址，共用一个字就互相盖掉，
// 「读回自己的标记」这条判据也就没有意义了。
module mkFast(RegIf#(8, 32));
  Vector#(4, Reg#(Bit#(32))) v <- replicateM(mkReg(32'hDEAD0000));
  method ActionValue#(RegRsp#(32)) access(RegReq#(8, 32) r);
    Bit#(2) i = r.addr[3:2];
    if (r.write) v[i] <= r.wdata;
    return RegRsp { rdata: v[i], err: False };
  endmethod
endmodule

// 会停顿的假存储：收到请求之后压 n 拍才答。宏与缓存就是这个形状。
module mkSlow#(Integer n)(RegTarget#(8, 32));
  // 规则与 always_enabled 的方法同写这几个量。方法每拍都在，用普通寄存器
  // 规则就永不触发——CReg 定序：端口 0 归规则、端口 1 归方法。
  Reg#(Bit#(8))  cnt[2]  <- mkCReg(2, 0);
  Reg#(Bool)     busy[2] <- mkCReg(2, False);
  Reg#(Bool)     ansV[2] <- mkCReg(2, False);
  Reg#(Bool)     wr[2]   <- mkCReg(2, False);
  Reg#(Bit#(32)) wd[2]   <- mkCReg(2, 0);
  Reg#(Bit#(2))  ix[2]   <- mkCReg(2, 0);
  Vector#(4, Array#(Reg#(Bit#(32)))) v <- replicateM(mkCReg(2, 32'hBEEF0000));

  rule tick;
    if (busy[0] && cnt[0] == 0) begin
      busy[0] <= False;
      ansV[0] <= True;
      if (wr[0]) v[ix[0]][0] <= wd[0];
    end else begin
      if (busy[0]) cnt[0] <= cnt[0] - 1;
      ansV[0] <= False;
    end
  endrule

  method Action req(Bool valid, RegReq#(8, 32) r);
    if (valid && !busy[1] && !ansV[1]) begin
      busy[1] <= True;
      cnt[1]  <= fromInteger(n);
      wr[1]   <= r.write;
      wd[1]   <= r.wdata;
      ix[1]   <= r.addr[3:2];
    end
  endmethod
  method Bool ready = !busy[1] && !ansV[1];
  method Bool rspValid = ansV[1];
  method RegRsp#(32) rsp = RegRsp { rdata: v[ix[1]][1], err: False };
endmodule

// 一个照本子跑的发起方：往 addr 写 tag、再读回来核对，来回 rounds 遍。
//
// gap 是两笔之间歇几拍（0 就是背靠背，一刻不停）。歇不歇很要紧：
// 仲裁只有在「轮转指着的那个发起方当时没在要」的时候才会选中排在它后面的，
// 而答复错发给别人这一类毛病只在那种时刻才现形。全都背靠背反而测不出来。
// 各家的间隔互不整除，相位才会一直漂，那种时刻才会反复出现。
//
// 状态只有 step 一条规则写，方法只发线——否则方法与规则同写一个量，
// 方法每拍都在，规则就永不触发。
interface FakeMgr;
  interface RegManager#(8, 32) m;
  method Bool fin;
  method Bool bad;
endinterface

module mkProg#(Bit#(8) addr, Bit#(32) tag, Bit#(16) rounds,
               Bit#(8) gap)(FakeMgr);
  Reg#(Bool)           v     <- mkReg(False);
  Reg#(RegReq#(8, 32)) rq    <- mkReg(unpack(0));
  Reg#(Bool)           wr    <- mkReg(True);
  Reg#(Bit#(16))       left  <- mkReg(rounds);
  Reg#(Bool)           badR  <- mkReg(False);
  Reg#(Bit#(8))        idle  <- mkReg(0);

  Wire#(Bool)          rv    <- mkDWire(False);
  Wire#(RegRsp#(32))   rx    <- mkDWire(unpack(0));

  function RegReq#(8, 32) mk(Bool w) =
      RegReq { addr: addr, write: w, wdata: tag, wstrb: w ? 4'hF : 4'h0 };

  rule step (left != 0);
    Bool           nv  = v;
    Bool           nwr = wr;
    Bit#(16)       nl  = left;
    Bool           nb  = badR;
    Bit#(8)        nid = idle;
    RegReq#(8, 32) nrq = rq;

    if (v && rv) begin
      if (!wr) begin
        if (rx.rdata != tag) nb = True;
        nl = left - 1;
      end
      nwr = !wr;
      if (nl == 0)
        nv = False;
      else if (gap == 0) begin
        // 背靠背：答复到手的同一拍就把下一笔顶上去，中间不留空拍
        nrq = mk(nwr);
        nv  = True;
      end else begin
        nv  = False;
        nid = gap;
      end
    end else if (!v) begin
      if (idle != 0) nid = idle - 1;
      else begin
        nrq = mk(wr);
        nv  = True;
      end
    end

    v    <= nv;
    wr   <= nwr;
    left <= nl;
    badR <= nb;
    idle <= nid;
    rq   <= nrq;
  endrule

  interface RegManager m;
    method Bool valid = v;
    method RegReq#(8, 32) req = rq;
    method Action ready(Bool r);
    endmethod
    method Action resp(Bool y, RegRsp#(32) x);
      rv <= y;
      rx <= x;
    endmethod
  endinterface

  method Bool fin = left == 0;
  method Bool bad = badR;
endmodule

endpackage
