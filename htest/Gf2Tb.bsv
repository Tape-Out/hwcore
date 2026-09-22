package Gf2Tb;

import HwcoreCfg::*;

// RevEng 目录（https://reveng.sourceforge.io/crc-catalogue/）的校验值：每个模型对
// ASCII "123456789" 算出的 CRC。七个模型覆盖了三种宽度之外的全部组合——反射与否、
// 初值为零与全一、终值异或与否——漏掉任何一个参数，至少有一个模型对不上。

import Vector::*;
import Gf2::*;

function Bit#(8) digit(Integer i) = fromInteger(49 + i);

(* synthesize *)
module mkGf2Tb(Empty);
  Vector#(9, Bit#(8)) msg = genWith(digit);

  function Bit#(n) check(CrcModel#(n) m) provisos (Add#(1, k, n));
    return crcOf(m, msg);
  endfunction

  rule run;
    Bool bad = False;
    if (check(crc7Mmc) != 7'h75) begin
      $display("FAIL CRC-7/MMC got %h want 75", check(crc7Mmc)); bad = True;
    end
    if (check(crc8MaximDow) != 'ha1) begin
      $display("FAIL CRC-8/MAXIM-DOW got %h want a1", check(crc8MaximDow)); bad = True;
    end
    if (check(crc15Can) != 15'h059e) begin
      $display("FAIL CRC-15/CAN got %h want 059e", check(crc15Can)); bad = True;
    end
    if (check(crc16Xmodem) != 'h31c3) begin
      $display("FAIL CRC-16/XMODEM got %h want 31c3", check(crc16Xmodem)); bad = True;
    end
    if (check(crc16Ibm3740) != 'h29b1) begin
      $display("FAIL CRC-16/IBM-3740 got %h want 29b1", check(crc16Ibm3740)); bad = True;
    end
    if (check(crc32IsoHdlc) != 'hcbf43926) begin
      $display("FAIL CRC-32/ISO-HDLC got %h want cbf43926", check(crc32IsoHdlc)); bad = True;
    end
    if (check(crc32Iscsi) != 'he3069283) begin
      $display("FAIL CRC-32/ISCSI got %h want e3069283", check(crc32Iscsi)); bad = True;
    end
    if (bad) $display("FAILED");
    else $display("PASS gf2: seven catalogue CRC models give their check values");
    $finish(bad ? 1 : 0);
  endrule
endmodule

endpackage
