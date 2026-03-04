# FP16 ALU — IEEE 754 Half-Precision Floating Point ALU

A pipelined floating point ALU I built from scratch in Verilog,
targeting Intel Cyclone V FPGA. It supports 12 operations and
is designed around the same number format used in modern AI chips.

---

## Why I Built This

Modern AI accelerators like Nvidia GPUs and Google TPUs do
billions of floating point operations per second. Almost all
of them use FP16 — 16-bit half precision — because it is fast,
compact, and accurate enough for neural network inference.

I wanted to understand how this actually works at the hardware
level. So I built one from scratch — not just the math, but
the actual pipelined RTL that could run on real FPGA silicon.

---

## What It Does

Takes two FP16 numbers as input, performs one of 12 operations,
and produces a FP16 result — all in a pipelined architecture
that produces one result every clock cycle.

| Code | Operation | Notes |
|---|---|---|
| 0000 | ADD | FP16 Addition |
| 0001 | SUB | FP16 Subtraction |
| 0010 | MUL | FP16 Multiplication |
| 0011 | AND | Bitwise AND |
| 0100 | OR | Bitwise OR |
| 0101 | XOR | Bitwise XOR |
| 0110 | MIN | Returns smaller of A, B |
| 0111 | ABS | Absolute value |
| 1000 | NEG | Negate sign |
| 1001 | CMP | Compare A and B |
| 1010 | MAX | Returns larger of A, B |
| 1011 | FP2INT | Convert FP16 to integer |

---

## How It Is Built

I split the design into separate modules, each handling one
group of operations. They all run in parallel — the output
mux at the end picks the right result based on which operation
was requested.
```
A[15:0] ──┐
          ├──► fp16_addsub  (3 pipeline stages) ──┐
B[15:0] ──┤                                       │
          ├──► fp16_mul     (3 pipeline stages) ──┤
op[3:0] ──┤                                       ├──► MUX ──► Result
          ├──► fp16_logic   (1 pipeline stage)  ──┤
          │                                       │
          └──► fp16_to_int  (2 pipeline stages) ──┘
```

The pipeline means a new result comes out every clock cycle
even though each individual operation takes 2-3 cycles to
complete. This is the same principle used in real processors.

---

## Synthesis Results

I synthesized both a baseline (non-optimized) version and
my optimized version on Cyclone V to measure the improvement.

| Metric | Baseline | Optimized |
|---|---|---|
| Logic (ALMs) | 337 | 315 |
| Registers | — | 213 |
| DSP Blocks | — | 1 |
| Improvement | — | 6.5% fewer ALMs |

The reduction comes from three main things I did differently
from the baseline:

**Shared unpacking** — The baseline unpacks sign, exponent
and mantissa separately for every operation. My design unpacks
once and shares the result across all modules.

**One adder for ADD and SUB** — Subtraction is just addition
with the sign bit flipped. So I used one adder with an XOR
gate on the sign instead of two separate adders.

**Shared comparator** — MIN, MAX and CMP all need the same
greater-than comparison. The baseline duplicates this logic
three times. My design computes it once and shares it.

---

## How I Verified It

I used a two-level approach. First I wrote a Python model
using numpy float16 to generate the correct expected outputs
for every test case. Then I wrote self-checking Verilog
testbenches that compare the RTL output against those
expected values automatically.

Any mismatch prints FAIL immediately so bugs are caught
without manually reading waveforms.

| Module | Tests | Status |
|---|---|---|
| fp16_unpack | 8 | All Pass |
| fp16_addsub | 5 | All Pass |
| fp16_mul | 8 | All Pass |
| fp16_logic | 10 | All Pass |
| fp16_to_int | 8 | All Pass |
| fp16_alu_top | 11 | All Pass |

---

## What I Learned

Going through this project I got a much deeper understanding
of how floating point hardware actually works. The tricky
parts were the normalization logic after addition (handling
carry and leading zeros), the exponent alignment before
adding, and making sure special cases like NaN, Infinity
and negative zero were handled correctly throughout.

Pipelining also taught me that latency and throughput are
two completely different things — and that you can have
high throughput even with high latency if you pipeline
the stages correctly.

---

## Project Structure
```
fp16_alu/
├── rtl/                    ← All synthesizable Verilog
│   ├── fp16_alu_top.v      ← Top level with output mux
│   ├── fp16_addsub.v       ← Pipelined add and subtract
│   ├── fp16_mul.v          ← Pipelined multiply
│   ├── fp16_logic.v        ← Logic and comparison ops
│   ├── fp16_to_int.v       ← FP16 to integer converter
│   ├── fp16_unpack.v       ← Shared unpack utility
│   └── fp16_alu_baseline.v ← Non-optimized for comparison
├── tb/                     ← Self checking testbenches
├── python_model/           ← numpy golden reference model
├── reports/                ← Synthesis screenshots
└── README.md
```

---

## Tools

- Verilog HDL
- Quartus Prime Lite 25.3.1 (Synthesis)
- ModelSim (Simulation)
- Python 3.12 + numpy (Golden reference model)
- Intel Cyclone V FPGA

---

## About

**Dunna Dilip Kumar**
B.Tech Electronics and Communication Engineering

Built this project to understand FP hardware from the ground
up and to have something concrete to talk about in interviews.
The MAC (multiply-accumulate) module is next — that is the
core operation behind every neural network layer.
