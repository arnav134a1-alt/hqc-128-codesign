# A Memory-Efficient FPGA Implementation and Hardware/Software Co-Design of Post-Quantum HQC-128 for Resource-Constrained Edge Devices

[![Target: Artix-7](https://img.shields.io/badge/FPGA-AMD%20Artix--7%20(xc7a35t--1%20%2F%20xc7a200t--2)-0052CC.svg)](#post-route-implementation-and-saif-power-metrics)
[![BRAM: 6.0 Tiles](https://img.shields.io/badge/BRAM-6.0%20RAMB36E1%20Tiles%20(12.0%25%20of%20xc7a35t)-green.svg)](#memory-lifetime-conflict-graph-and-6-bram-allocation)
[![DSP: 0 Slices](https://img.shields.io/badge/DSP-0%20Slices-blue.svg)](#post-route-implementation-and-saif-power-metrics)
[![Standard: NIST HQC-128](https://img.shields.io/badge/NIST%20PQC-HQC--128%20(Selected%20Mar%202025)-orange.svg)](#architectural-highlights)
[![Verification: 100 NIST Vectors](https://img.shields.io/badge/KAT%20Verification-100%20PQClean%20Vectors%20(0%20Mismatches)-brightgreen.svg)](#verification-and-reproducibility)

This repository contains the complete Verilog RTL, AXI4-Lite slave wrapper, C99 Hardware Abstraction Layer (HAL) driver, 100-vector NIST Round 4 PQClean verification suite, Vivado utilization reports, and manuscript source for the paper:

> **Arnav Pillai**, *"A Memory-Efficient FPGA Implementation and Hardware/Software Co-Design of Post-Quantum HQC-128 for Resource-Constrained Edge Devices,"* submitted to **IEEE Embedded Systems Letters (ESL)**, 2026.  
> 📄 **Manuscript:** [`paper/esl_paper.pdf`](paper/esl_paper.pdf) | **LaTeX Source:** [`paper/esl_paper.tex`](paper/esl_paper.tex)

---

## Architectural Highlights

- **Chromatic Memory Lower Bound ($\chi(G) = \omega(G) = 6$):** Models all 14 logical buffers across the five HQC-128 PKE phases ($\Phi_{\text{kg}} \rightarrow \Phi_{\text{enc-codec}} \rightarrow \Phi_{\text{enc-arith}} \rightarrow \Phi_{\text{dec-arith}} \rightarrow \Phi_{\text{dec-codec}}$) as a chordal interval conflict graph $G$. In-place lifetime aliasing ($\mathbf{u} \leftrightarrow \mathbf{n}$ in BRAM 2, $\mathbf{v} \leftrightarrow \mathbf{mG}$ in BRAM 3), a single time-shared dual-port accumulator ($\mathbf{T}_1$ in BRAM 5), and distributed LUTRAM storage fit the entire unified PKE core into **6.0 RAMB36E1 tiles** and **0 RAMB18E1 tiles** (only **12.0%** of an entry-level Artix-7 `xc7a35t`).
- **Distributed LUTRAM Compression (408 LUTs, 0 BRAMs):** Maps the four sparse index banks ($\mathbf{y}$ of weight $\omega=66$; $\mathbf{r}_1, \mathbf{r}_2, \mathbf{e}$ of weight $\omega_r=\omega_e=75$) into **120 LUTRAMs** (30 per bank), alongside **128 LUTRAMs** for the duplicated Reed-Muller (RM) codeword buffer and **160 LUTRAMs** for the 7-layer Fast Walsh-Hadamard Transform (FWHT) butterfly pipeline FIFOs.
- **64-Bit DSP-Free Cyclic Ring Multiplier:** Evaluates sparse polynomial products in $\mathcal{R} = \mathbb{F}_2[X]/(X^{17,669} - 1)$ in $W \times 282$ cycles ($W \in \{66, 75\}$) using wire-sliced 15-bit index addressing (`pos[j][14:6]` word offset, `pos[j][5:0]` shift), a 128-bit funnel shifter, and 5-bit residual ring folding (`0x1F` mask at word 276) with **0 DSP48E1 slices**.
- **Concatenated RS-RM Hardware Codec:** Integrates shortened Reed-Solomon $\mathrm{RS}[46, 16, 31]$ and duplicated Reed-Muller $\mathrm{RM}[384, 8, 192]$ (multiplicity 3) encoding and decoding, featuring 64-to-128-bit RM prefetching, a 7-layer pipelined FWHT decoder, Berlekamp-Massey error-locator updates, iterative Chien search (`hqc_rsdecod_roots.v`), and a two-stage pipelined $\mathbb{F}_{2^8}$ Forney error evaluator (`hqc_rsdecod_forney.v`).
- **32-Bit AXI4-Lite SoC Bridge & C99 HAL Driver:** A lightweight AXI4-Lite slave wrapper (**153 LUTs, 293 FFs, 0 BRAMs**) interfaces the 64-bit core with a 32-bit host processor (e.g., RISC-V `CV32E40P`) via atomic 64-bit write-commit strobes.

---

## Post-Route Implementation and SAIF Power Metrics

Synthesized, placed, and routed in **AMD Vivado 2025.2** with post-route power annotated from a 100-vector NIST Round 4 PQClean behavioral switching activity file (`hqc_pke_100vec.saif`, matching 5,115 / 19,285 routed nets):

| Metric | Artix-7 `xc7a200t-2` | Artix-7 `xc7a35t-1` (Edge Target) |
| :--- | ---: | ---: |
| **Slice LUTs (Logic / LUTRAM)** | 8,246 (7,838 / 408) | **8,246 (7,838 / 408)** |
| **Slice Registers (FF)** | 7,868 (2.9%) | **7,868 (18.9%)** |
| **Block RAM (`RAMB36E1` / `RAMB18E1`)** | **6.0 (1.6%) / 0.0** | **6.0 (12.0%) / 0.0** |
| **DSP48E1 Slices** | **0 (0.0%)** | **0 (0.0%)** |
| **Routed WNS (@ 100.0 MHz)** | $+2.410\text{ ns}$ ($T_{\text{crit}} = 7.590\text{ ns}$) | $+1.641\text{ ns}$ ($T_{\text{crit}} = 8.359\text{ ns}$) |
| **Post-Route Extrapolated $F_{\max}$ (Sweep)** | 131.8 MHz (eval. @ 131.0 MHz) | **119.6 MHz (eval. @ 119.0 MHz)** |
| **Power @ 100 MHz (Dyn / Stat)** | 0.202 W (0.080 / 0.122 W) | 0.146 W (0.078 / 0.069 W) |
| **Power @ Swept $F_{\max}$ (Dyn / Stat)** | 0.222 W (0.100 / 0.122 W) | **0.158 W (0.089 / 0.069 W)** |
| **PKE Energy (@ 100 MHz)** | 180.3 µJ (0.893 ms) | 130.3 µJ (0.893 ms) |
| **PKE Energy (@ Swept $F_{\max}$)** | 151.3 µJ (0.681 ms) | **118.5 µJ (0.750 ms)** |

---

## Cycle & Latency Comparison vs. 32-Bit RISC-V Software

Comparison against the official HQC-128 reference implementation on a 32-bit embedded **RISC-V processor (`CV32E40P`, `-O3`)** [Ras et al., *Euromicro DSD 2025*]:

| Primitive / Scope | Official HQC-128 SW (32-Bit RISC-V) | Our PKE Coprocessor (`xc7a35t-1` @ 119.0 MHz) | Compute Cycle Reduction |
| :--- | ---: | ---: | ---: |
| **KeyGen** | 43,592,464 cyc | 19,796 cyc (0.166 ms) | **2,202×** |
| **Encap / Encrypt** | 87,574,395 cyc | 45,677 cyc (0.384 ms) | **1,917×** |
| **PKE Decrypt (Core Only)** | 132,101,254 cyc | 23,789 cyc (0.200 ms) | **5,553×** |
| **FO-KEM Decap (Dec + Re-Enc)** | 132,101,254 cyc | 69,466 cyc (0.584 ms) | **1,902×** |
| **Total (PKE Core Only)** | **263,268,113 cyc** | **89,262 cyc (0.750 ms)** | **2,949×** |
| **Total (FO-KEM Core Compute)** | **263,268,113 cyc** | **134,939 cyc (1.134 ms)** | **1,951×** |

---

## Memory-Lifetime Conflict Graph and 6-BRAM Allocation

Each dense polynomial in $\mathcal{R} = \mathbb{F}_2[X]/(X^{17,669} - 1)$ requires $\lceil 17,669 / 64 \rceil = 277$ words of 64 bits. At step $t^*$ of encryption ($\mathbf{T}_1 \leftarrow \mathbf{T}_1 \oplus \mathbf{mG}$), six dense buffers $\{\mathbf{h}, \mathbf{s}, \mathbf{x}, \mathbf{u}, \mathbf{mG}, \mathbf{T}_1\}$ are simultaneously live, forming a 6-clique $K_6 \subseteq G$ ($\chi(G) = \omega(G) = 6$).

```text
+-------------------------------------------------------------------------------+
|             Total Block RAM Footprint: 6.0 RAMB36E1 (0 RAMB18E1)              |
+-------------------------+-------------------------+---------------------------+
| BRAM 0 (RAMB36E1, 64-b) | BRAM 1 (RAMB36E1, 64-b) | BRAM 2 (RAMB36E1, 64-b)   |
| Bank 0: Public poly h   | Bank 1: Public key s    | Banks 3, 9: u <-> n       |
+-------------------------+-------------------------+---------------------------+
| BRAM 3 (RAMB36E1, 64-b) | BRAM 4 (RAMB36E1, 64-b) | BRAM 5 (RAMB36E1, 64-b)   |
| Banks 2, 4: v <-> mG    | Bank 10: Secret poly x  | Shared Accumulator T1     |
+-------------------------+-------------------------+---------------------------+
|                     Distributed LUTRAM: 408 LUTs (0 BRAMs)                    |
|  - Sparse Index Banks (y: 66x15b; r1, r2, e: 75x15b): 120 LUTRAMs (30/bank)   |
|  - Duplicated RM Codeword Buffer (384x8b):            128 LUTRAMs             |
|  - 7-Layer FWHT Butterfly Pipeline FIFOs:             160 LUTRAMs             |
+-------------------------------------------------------------------------------+
```

---

## Repository Structure

```text
hqc-128-codesign/
├── hw/
│   ├── axi/
│   │   └── hqc_pke_axi_lite.v          # 32-bit AXI4-Lite slave bridge (153 LUTs, 293 FFs)
│   ├── core/
│   │   ├── top_full.v                  # Unified 6.0-BRAM HQC-128 PKE coprocessor top
│   │   ├── KeyGen_datapath_shared.v    # KeyGen datapath sharing accumulator T1
│   │   ├── Encryption_datapath_shared.v# Encrypt datapath sharing accumulator T1
│   │   ├── Decryption_datapath_shared.v# Decrypt datapath sharing accumulator T1
│   │   ├── shift_acc.v                 # 64-bit DSP-free cyclic barrel-shifter multiplier
│   │   ├── dense_add_dense.v           # 64-bit word-wise GF(2) polynomial XOR unit
│   │   ├── dense_add_scarse.v          # Sparse-to-dense bit scatter XOR unit
│   │   ├── Dense_mem.v                 # Simple Dual-Port (SDP) RAMB36E1 wrapper (277x64b)
│   │   └── sparce_mem.v                # Distributed LUTRAM wrapper for sparse indices
│   ├── codec/
│   │   ├── encoder_adapter.v           # 64-bit BRAM adapter for concatenated RS-RM encoder
│   │   ├── concat_code.v               # Concatenated RS[46,16,31] + RM[384,8,192] encoder
│   │   ├── reed_solomon_encode.v       # Systematic shortened RS[46,16,31] encoder
│   │   ├── cdw_xor_tmp.v               # RS LFSR feedback stage
│   │   ├── reed_muller_encode.v        # Duplicated RM[384,8,192] encoder controller
│   │   ├── rm_encoder.v                # RM(1,7) generator matrix encoder
│   │   ├── mem_single.v                # Distributed LUTRAM buffer for RM codeword blocks
│   │   ├── decoder_adapter.v           # 64-to-128-bit prefetch adapter for RS-RM decoder
│   │   ├── hqc_decod_top.v             # Concatenated RM + RS decoder top
│   │   ├── hqc_rmdecod_top.v           # Duplicated RM(1,7) decoder top
│   │   ├── hqc_rmdecod_ctrl.v          # RM decoder state machine
│   │   ├── hqc_rmdecod_expnsum.v       # Multiplicity-3 block expansion and accumulation
│   │   ├── hqc_rmdecod_hadamard.v      # 7-layer pipelined Fast Walsh-Hadamard Transform (FWHT)
│   │   ├── hqc_rmdecod_findpeaks.v     # Maximum-likelihood peak detector
│   │   ├── syncfifo.v                  # Distributed LUTRAM FIFO for FWHT pipeline stages
│   │   ├── hqc_rsdecod_top.v           # Shortened RS[46,16,31] decoder top
│   │   ├── hqc_rsdecod_syndromes.v     # 30-syndrome parallel evaluator over GF(2^8)
│   │   ├── hqc_rsdecod_elp.v           # Berlekamp-Massey error-locator polynomial (ELP) solver
│   │   ├── hqc_rsdecod_roots.v         # Iterative Chien search root finder over GF(2^8)
│   │   ├── hqc_rsdecod_forney.v        # Two-stage pipelined Forney error magnitude evaluator
│   │   ├── gf_mul.v / gfmul.v          # GF(2^8) finite-field multipliers
│   │   └── clog2.v                     # Ceiling log2 macro definitions
│   └── tb/
│       ├── tb_top_full.v               # Single-vector self-checking PKE testbench
│       └── tb_top_pke_ref.v            # 100-vector NIST Round 4 PQClean KAT testbench
├── sw/
│   ├── include/
│   │   └── hqc_hal.h                   # C99 Hardware Abstraction Layer (MMIO register struct)
│   ├── src/
│   │   └── hqc_hal.c                   # Driver routines (KeyGen, Encrypt/Encap, Decrypt/Decap)
│   ├── test/
│   │   └── main_demo.c                 # Host driver verification harness
│   └── Makefile                        # GCC build script for host driver verification
├── sim/
│   └── vectors/                        # 100 NIST Round 4 PQClean reference test vectors (*.mem)
├── scripts/
│   ├── run_sim.tcl                     # Vivado XSim batch behavioral simulation script
│   └── run_impl.tcl                    # Vivado batch synthesis, placement, and routing script
├── reports/
│   ├── hqc_pke_100vec_pass.log         # 100-vector NIST PQClean simulation verification log
│   ├── fwht_lutram_query.rpt           # Vivado hierarchical breakdown of 408 distributed LUTRAMs
│   └── fwht_lutram_utilization.rpt     # Post-route Artix-7 xc7a35t-1 utilization report
├── paper/
│   ├── esl_paper.tex                   # Self-contained IEEE ESL LaTeX manuscript source
│   └── esl_paper.pdf                   # Camera-ready 4-page IEEE ESL PDF
└── README.md
```

---

## Memory-Mapped Register Interface (AXI4-Lite)

The [`hqc_pke_axi_lite`](hw/axi/hqc_pke_axi_lite.v) slave peripheral exposes a 32-bit word-aligned register aperture (`C_S_AXI_ADDR_WIDTH = 7`):

| Byte Offset | Register | Access | Description |
| :--- | :--- | :---: | :--- |
| `0x00` | `CR` | R/W | Control Register (`[0]` `START` auto-clearing pulse, `[2:1]` `OP_MODE`, `[3]` `SOFT_RST`) |
| `0x04` | `SR` | R | Status Register (`[0]` `BUSY`, `[1]` `DONE`, `[2]` `MSG_VALID`) |
| `0x08` | `MAR` | R/W | Memory Access Register (`[3:0]` `MEM_SEL` bank ID, `[12:4]` `WORD_ADDR` offset `0..276`) |
| `0x0C` | `MDR_L` | R/W | Memory Write Data Low (`host_wdata[31:0]`) |
| `0x10` | `MDR_H` | R/W | Memory Write Data High (`host_wdata[63:32]`); writing `MDR_H` pulses `core_we` atomically |
| `0x14` | `MRR_L` | R | Memory Read Data Low (`host_rdata[31:0]`) |
| `0x18` | `MRR_H` | R | Memory Read Data High (`host_rdata[63:32]`) |
| `0x20–0x2C` | `PINR[0..3]` | R/W | 128-bit Plaintext Input Registers (`msg_in[127:0]`) |
| `0x30–0x3C` | `POUTR[0..3]` | R | 128-bit Recovered Plaintext Output Registers (`msg_out[127:0]`) |

### Memory Bank Select (`MEM_SEL`) Routing

| `MEM_SEL` | Logical Buffer | Physical Storage | Dimensions | Description |
| :---: | :--- | :--- | :---: | :--- |
| `0x0` | $\mathbf{h}$ | BRAM 0 (`RAMB36E1`) | $277 \times 64\text{-b}$ | Public generator polynomial |
| `0x1` | $\mathbf{s}$ | BRAM 1 (`RAMB36E1`) | $277 \times 64\text{-b}$ | Public key polynomial $\mathbf{s} = \mathbf{x} + \mathbf{h}\cdot\mathbf{y}$ |
| `0x2` | $\mathbf{mG}$ | BRAM 3 (`RAMB36E1`) | $277 \times 64\text{-b}$ | Concatenated RS-RM codeword (aliased with $\mathbf{v}$) |
| `0x3` | $\mathbf{u}$ | BRAM 2 (`RAMB36E1`) | $277 \times 64\text{-b}$ | Ciphertext polynomial $\mathbf{u} = \mathbf{r}_1 + \mathbf{h}\cdot\mathbf{r}_2$ |
| `0x4` | $\mathbf{v}$ | BRAM 3 (`RAMB36E1`) | $277 \times 64\text{-b}$ | Ciphertext polynomial $\mathbf{v} = \mathbf{mG} + \mathbf{s}\cdot\mathbf{r}_2 + \mathbf{e}$ |
| `0x5` | $\mathbf{r}_1$ | Distributed LUTRAM | $75 \times 15\text{-b}$ | Ephemeral encryption sparse support |
| `0x6` | $\mathbf{r}_2$ | Distributed LUTRAM | $75 \times 15\text{-b}$ | Ephemeral encryption sparse support |
| `0x7` | $\mathbf{e}$ | Distributed LUTRAM | $75 \times 15\text{-b}$ | Ephemeral encryption error support |
| `0x8` | $\mathbf{y}$ | Distributed LUTRAM | $66 \times 15\text{-b}$ | Secret key sparse support |
| `0x9` | $\mathbf{n}$ | BRAM 2 (`RAMB36E1`) | $277 \times 64\text{-b}$ | Demasked noisy codeword $\mathbf{n} = \mathbf{v} - \mathbf{u}\cdot\mathbf{y}$ (aliased with $\mathbf{u}$) |
| `0xA` | $\mathbf{x}$ | BRAM 4 (`RAMB36E1`) | $277 \times 64\text{-b}$ | Secret key dense polynomial |

---

## Verification and Reproducibility

### 1. C99 HAL Driver Verification Harness
```bash
cd sw
make
make run
```

### 2. Vivado RTL Behavioral Simulation (Single-Vector & 100-Vector NIST PQClean KATs)
```bash
vivado -mode batch -source scripts/run_sim.tcl
```
To run the full 100-vector NIST Round 4 PQClean regression (`hw/tb/tb_top_pke_ref.v`), set `TOP_MODULE` to `tb_top_pke_ref` in `scripts/run_sim.tcl` (see [`reports/hqc_pke_100vec_pass.log`](reports/hqc_pke_100vec_pass.log) for the complete verification log).

### 3. Vivado Synthesis, Placement & Routing
```bash
vivado -mode batch -source scripts/run_impl.tcl
```

---

## Citation

If you use this hardware architecture, RTL, or co-design framework in your research, please cite:

```bibtex
@article{pillai2026memory,
  author  = {Pillai, Arnav},
  title   = {A Memory-Efficient {FPGA} Implementation and Hardware/Software Co-Design of Post-Quantum {HQC-128} for Resource-Constrained Edge Devices},
  journal = {IEEE Embedded Systems Letters},
  year    = {2026},
  note    = {Submitted for publication}
}
```

## License

This project is released under the Apache-2.0 License (with third-party Reed-Solomon and Reed-Muller baseline codec modules retaining their respective open-source headers from TII and Yale University).
