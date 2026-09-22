package Jep106Tb;

import HwcoreCfg::*;

// 期望值取真实芯片公布的数，出处钉了提交：
//   mvendorid：Linux arch/riscv/include/asm/vendorid_list.h（91f815b7）
//   JTAG IDCODE：OpenOCD tcl/board/sifive/hifive1-rev-b.cfg 的 FE310（29826e7f）、
//                tcl/target/stm32f4x.cfg 的两种调试口（a2c6d152）
//   SMCCC SOC_ID：公布的整字找不到，照 Linux drivers/firmware/smccc/soc_id.c 的三个掩码拼（70492cfc）
// 五家厂商的续码个数有 0、2、6、9、11 五种，字段错位一位至少有一行对不上；
// 续码 17 那一行是 IDCODE 只留模 16 的那条规矩

import Jep106::*;

(* synthesize *)
module mkJep106Tb(Empty);
  rule run;
    Bool bad = False;
    if (mvendorid(jep106(9, 'h09)) != 'h489) begin
      $display("FAIL mvendorid SiFive got %h want 489", mvendorid(jep106(9, 'h09))); bad = True;
    end
    if (mvendorid(jep106(11, 'h37)) != 'h5b7) begin
      $display("FAIL mvendorid T-Head got %h want 5b7", mvendorid(jep106(11, 'h37))); bad = True;
    end
    if (mvendorid(jep106(6, 'h1e)) != 'h31e) begin
      $display("FAIL mvendorid Andes got %h want 31e", mvendorid(jep106(6, 'h1e))); bad = True;
    end
    if (mvendorid(jep106(2, 'h27)) != 'h127) begin
      $display("FAIL mvendorid MIPS got %h want 127", mvendorid(jep106(2, 'h27))); bad = True;
    end
    if (mvendorid(jep106(0, 'h29)) != 'h029) begin
      $display("FAIL mvendorid Microchip got %h want 029", mvendorid(jep106(0, 'h29))); bad = True;
    end
    if (idcode(jep106(9, 'h09), 2, 'h0000) != 'h20000913) begin
      $display("FAIL IDCODE FE310 got %h want 20000913", idcode(jep106(9, 'h09), 2, 'h0000)); bad = True;
    end
    if (idcode(jep106(4, 'h3b), 4, 'hba00) != 'h4ba00477) begin
      $display("FAIL IDCODE STM32F4 JTAG-DP got %h want 4ba00477", idcode(jep106(4, 'h3b), 4, 'hba00)); bad = True;
    end
    if (idcode(jep106(4, 'h3b), 2, 'hba01) != 'h2ba01477) begin
      $display("FAIL IDCODE STM32F4 SW-DP got %h want 2ba01477", idcode(jep106(4, 'h3b), 2, 'hba01)); bad = True;
    end
    if (idcode(jep106(17, 'h01), 0, 'h0000) != 'h00000103) begin
      $display("FAIL IDCODE bank 17 got %h want 00000103", idcode(jep106(17, 'h01), 0, 'h0000)); bad = True;
    end
    if (socId(jep106(4, 'h3b), 'h1234) != 'h043b1234) begin
      $display("FAIL SOC_ID Arm got %h want 043b1234", socId(jep106(4, 'h3b), 'h1234)); bad = True;
    end
    if (socId(jep106(127, 'h7e), 'hffff) != 'h7f7effff) begin
      $display("FAIL SOC_ID widest got %h want 7f7effff", socId(jep106(127, 'h7e), 'hffff)); bad = True;
    end
    if (bad) $display("FAILED");
    else $display("PASS jep106: mvendorid, JTAG IDCODE and SMCCC SOC_ID match five vendors' published numbers");
    $finish(bad ? 1 : 0);
  endrule
endmodule

endpackage
