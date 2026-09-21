# hwcore

![maturity](https://img.shields.io/badge/maturity-simulated-yellow) ![license](https://img.shields.io/badge/license-MIT%20OR%20Apache--2.0%20OR%20MulanPSL--2.0-blue)

Bus-neutral contracts and shared primitives for the Tape-Out IP library, written in Bluespec.

Every IP in the library depends on this package and on nothing else. Bus protocols
(`amba`, `tilelink`, `wishbone`) also depend on it. Dependencies only ever point here,
so adding a bus costs one adapter instead of a wrapper in every IP.

## Contracts

| Plane | Contract | File |
| :--: | :--: | :--: |
| Control | `RegIf#(aw, dw)` — one `access(RegReq) -> RegRsp` method | `hwsrc/RegIf.bsv` |
| Data | `Get#(t)` / `Put#(t)` from the BSV standard library | — |
| Interrupt | `Bool`, gathered by the fabric | `hwsrc/Fabric.bsv` |

An IP implements `RegIf` and knows nothing about any bus. Binding to APB4, AXI4-Lite,
Wishbone or TL-UL happens at integration time, in the bus package.

## Fabric

`mkFabric` takes a vector of `Device` records and returns a single `RegIf`, decoding
addresses at elaboration time. Interrupts are collected with `irqsOf`.

```bsv
Vector#(2, Device#(32, 32)) devs =
    cons(device(32'h1000_0000, 32'h100, gpio.regs, tagged Valid gpio.pins.irq),
    cons(device(32'h1000_1000, 32'h100, uart.regs, tagged Invalid),
    nil));

RegIf#(32, 32) bus <- mkFabric(devs);
```

Overlapping ranges are caught by `overlaps` at compile time rather than in simulation.

## License

任选其一：

- [MIT](LICENSE-MIT)
- [Apache 2.0](LICENSE-APACHE)
- [木兰宽松许可证 第2版](LICENSE-MULAN)

`SPDX-License-Identifier: MIT OR Apache-2.0 OR MulanPSL-2.0`

除非另行说明，你提交的贡献按上述三者同时授权，不附加其他条件。
