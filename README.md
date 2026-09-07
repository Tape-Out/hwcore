# hwcore

Bus-neutral contracts and shared primitives for the Tape-Out IP library, written in Bluespec.

Every IP in the library depends on this package and on nothing else. Bus protocols
(`amba`, `tilelink`, `wishbone`) also depend on it. Dependencies only ever point here,
so adding a bus costs one adapter instead of a wrapper in every IP.

## Contracts

| Plane | Contract | File |
| :--: | :--: | :--: |
| Control | `RegIf#(aw, dw)` — one `access(RegReq) -> RegRsp` method | `bsv/RegIf.bsv` |
| Data | `Get#(t)` / `Put#(t)` from the BSV standard library | — |
| Interrupt | `Bool`, gathered by the fabric | `bsv/Fabric.bsv` |

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

Mulan PSL v2.
