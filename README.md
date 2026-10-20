# HQC-128 Hardware/Software Co-Design Accelerator

[![Target: Artix-7](https://img.shields.io/badge/FPGA-Xilinx%20Artix--7-0052CC.svg)](#resource-utilization)
[![BRAM: 6.0 Tiles](https://img.shields.io/badge/BRAM-6.0%20Tiles%20(Floor)-green.svg)](#memory-architecture)
[![DSP: 0 Slices](https://img.shields.io/badge/DSP-0%20Slices-blue.svg)](#resource-utilization)
[![Standard: NIST Round 4](https://img.shields.io/badge/NIST%20PQC-Round%204%20HQC--128-orange.svg)](#algorithm-overview)
[![Verification: 100% Bit-Exact](https://img.shields.io/badge/KAT%20Verification-100%25%20Bit--Exact-brightgreen.svg)](#verification)

An ultra-compact, high-performance hardware/software co-design accelerator for the **Hamming Quasi-Cyclic (HQC-128)** post-quantum key encapsulation mechanism. Targeting the AMD/Xilinx Artix-7 FPGA family, this architecture achieves the **theoretical memory floor of 6.0 Block RAM (BRAM) tiles** with **0 DSP slices**, delivering a **70.7% BRAM reduction** compared to state-of-the-art designs while maintaining a **282x end-to-end speedup** over embedded ARM Cortex-M4 software.

---

## Architectural Highlights

- **Theoretical Memory Floor ($6.0$ BRAM Tiles):** Eliminates redundant polynomial buffers by time-multiplexing dense state memories ($U \leftrightarrow n$, $V \leftrightarrow mG$) and consolidating ring multiplier accumulators into a single shared dual-port RAM tile ($T_1$).
- **Distributed LUTRAM Compression:** Sparse polynomial index vectors ($w \le 75$) are mapped to distributed LUTRAM (332 LUTs) rather than Block RAM, cutting FPGA memory footprint to 4.5% of device capacity.
- **DSP-Free Cyclic Multiplier:** Evaluates sparse polynomial products in $\mathcal{R} = \mathbb{F}_2[X]/(X^{17669} - 1)$ via a 64-bit barrel shifter and carry accumulator datapath without consuming DSP48 slices.
- **Concatenated Codec Pipeline:** Fully integrated hardware decoder chaining Reed-Solomon $\mathrm{RS}(30, 16)$ with duplicate-encoded Reed-Muller $\mathrm{RM}(1, 7)$ and additive FFT error locator evaluation.
- **Atomic 32-Bit AXI4-Lite Bridge:** Industry-standard MMIO interface converting host bus cycles into 64-bit wide datapath transactions with automated status signaling.

---

## Performance and Resource Benchmarks

### Resource Utilization (Artix-7 `xc7a200tfbg676-2`)

Post-implementation metrics extracted from Vivado Design Suite at $119.0\text{ MHz}$:

| Resource | Used | Available | Utilization (%) |
|---|---|---|---|
| **Slice LUTs** | 8,246 | 134,600 | 6.13% |
| **Slice Registers (FF)** | 7,868 | 269,200 | 2.92% |
| **Block RAM (RAMB36E1)** | 6.0 | 365 | 1.64% |
| **Block RAM (RAMB18E1)** | 0.0 | 730 | 0.00% |
| **DSP48E1 Slices** | 0 | 740 | 0.00% |

### Execution Time and Speedup vs Embedded Software

Benchmark comparison between standalone embedded software running on an ARM Cortex-M4 @ 168 MHz (from the pqm4 evaluation suite) and this HW/SW co-design @ 119 MHz:

| Operation | Software (ARM Cortex-M4 @ 168MHz) | HW/SW Co-Design (@ 119MHz) | Clock Cycles | Speedup |
|---|---|---|---|---|
| **KeyGen** | 31.50 ms | 0.166 ms | 19,796 | **190x** |
| **Encapsulation** | 64.30 ms | 0.384 ms | 45,677 | **167x** |
| **Decapsulation** | 116.10 ms | 0.200 ms | 23,789 | **580x** |
| **Total Cycle / Latency** | 211.90 ms | 0.750 ms | 89,262 | **282x** |
| **Total Energy** | 31.8 mJ | 0.118 mJ | — | **-99.6%** |

---

## Memory Architecture

The HQC-128 parameter set operates in the polynomial ring $\mathcal{R} = \mathbb{F}_2[X]/(X^{17669} - 1)$. Each dense element comprises $n = 17,669$ bits, requiring $\lceil 17669 / 64 \rceil = 277$ 64-bit words.

```
+-------------------------------------------------------------------------------+
|                       Total BRAM Footprint: 6.0 Tiles                         |
+-------------------+-------------------+-------------------+-------------------+
|  BRAM 0 (RAMB36)  |  BRAM 1 (RAMB36)  |  BRAM 2 (RAMB36)  |  BRAM 3 (RAMB36)  |
|  Dense Vector h   |  Dense Vector s   |  Dense U / Dec n  |  Dense V / Enc mG |
+-------------------+-------------------+-------------------+-------------------+
|  BRAM 4 (RAMB36)  |  BRAM 5 (RAMB36)  | Distributed LUTRAM (332 LUTs)         |
|  Dense Vector x   |  Shared Acc (T1)  | Sparse Vectors y, r1, r2, e           |
+-------------------+-------------------+---------------------------------------+
```

### Allocation Breakdown

1. **State Memory $h$ (1 tile):** Public polynomial $h \in \mathcal{R}$.
2. **State Memory $s$ (1 tile):** Public key polynomial $s = x + h \cdot y$.
3. **State Memory $U / n$ (1 tile):** Reused across phases. Holds ciphertext component $u = r_1 + h \cdot r_2$ during encryption; stores received codeword $n = v - u \cdot y$ during decryption.
4. **State Memory $V / mG$ (1 tile):** Reused across phases. Stores encoded message codeword $mG$ prior to masking; stores ciphertext component $v = mG + s \cdot r_2 + e$ after arithmetic accumulation.
5. **State Memory $x$ (1 tile):** KeyGen private seed polynomial $x$.
6. **Shared Datapath Accumulator $T_1$ (1 tile):** Shared across KeyGen, Encryption, and Decryption ring multipliers, eliminating the dedicated second accumulator present in conventional accelerators.
7. **Sparse Memory $y, r_1, r_2, e$ (LUTRAM):** Fixed Hamming weights ($w = 66$, $w_r = 75$, $w_e = 75$). Storing 15-bit index values directly yields 332 LUTs total with single-cycle distributed access.

---

## Repository Structure

```
hqc-128-codesign/
├── hw/
│   ├── core/
│   │   ├── top_full.v                  # Top-level PKE accelerator (6.0 BRAM core)
│   │   ├── KeyGen_datapath_shared.v    # Key generation datapath with shared T1
│   │   ├── Encryption_datapath_shared.v# Encryption datapath with shared T1
│   │   ├── Decryption_datapath_shared.v# Decryption datapath with shared T1
│   │   ├── shift_acc.v                 # Cyclic ring multiplier (DSP-free barrel shifter)
│   │   ├── dense_add_dense.v           # 64-bit vector GF(2) XOR adder
│   │   ├── dense_add_scarse.v          # Sparse-dense bit scatter adder
│   │   ├── Dense_mem.v                 # Synchronous dual-port RAM wrapper
│   │   └── sparce_mem.v                # Distributed LUTRAM memory wrapper
│   ├── axi/
│   │   └── hqc_pke_axi_lite.v          # 32-bit AXI4-Lite slave bridge wrapper
│   ├── codec/                          # Reed-Solomon + Reed-Muller codec RTL
│   │   ├── add_fft.v                   # Additive Fast Fourier Transform
│   │   ├── decoder_adapter.v           # Concatenated decoder integration adapter
│   │   ├── encoder_adapter.v           # Concatenated encoder integration adapter
│   │   ├── hqc_decod_top.v             # Codec top-level decoder
│   │   ├── reed_solomon_encode.v       # RS(30, 16) systematic encoder
│   │   └── rm_encoder.v                # RM(1, 7) encoder
│   ├── sampler/                        # Constant-weight rejection sampler RTL
│   └── tb/
│       ├── tb_top_full.v               # Self-checking full PKE testbench
│       └── tb_top_pke_ref.v            # 100-vector NIST KAT verification testbench
├── sw/
│   ├── include/
│   │   └── hqc_hal.h                   # Hardware abstraction layer (CMSIS MMIO struct)
│   ├── src/
│   │   └── hqc_hal.c                   # Driver implementation (KeyGen, Encap, Decap)
│   ├── test/
│   │   └── main_demo.c                 # Software test harness & NIST KAT verification
│   └── Makefile                        # Native GCC build script
├── sim/
│   └── vectors/                        # NIST Known Answer Test (KAT) memory files
├── scripts/
│   └── run_sim.tcl                     # Vivado batch simulation runner
├── .gitignore
└── README.md
```

---

## Memory-Mapped Register Interface (AXI4-Lite)

The peripheral occupies a 32-bit aligned MMIO aperture:

| Offset | Name | Type | Reset | Description |
|---|---|---|---|---|
| `0x00` | `CR` | R/W | `0x00000000` | Control Register (`[0]` START, `[2:1]` OP_MODE, `[3]` SOFT_RST) |
| `0x04` | `SR` | R | `0x00000002` | Status Register (`[0]` BUSY, `[1]` DONE, `[2]` MSG_VALID) |
| `0x08` | `MAR` | R/W | `0x00000000` | Memory Access Register (`[3:0]` MEM_SEL, `[12:4]` CHUNK_ADDR) |
| `0x0C` | `MDR_L` | R/W | `0x00000000` | Memory Data Register Low (`[31:0]` of 64-bit word) |
| `0x10` | `MDR_H` | R/W | `0x00000000` | Memory Data Register High (`[63:32]` of 64-bit word) |
| `0x14-0x20` | `PINR0-3`| R/W | `0x00000000` | Plaintext Input Registers (128-bit message input) |
| `0x24-0x30` | `POUTR0-3`| R | `0x00000000` | Plaintext Output Registers (128-bit recovered message) |

### Memory Select (`MEM_SEL`) Map

| `MEM_SEL` | Target | Type | Dimension | Description |
|---|---|---|---|---|
| `0x0` | `h` | Dense | $277 \times 64$ bit | Public polynomial |
| `0x1` | `s` | Dense | $277 \times 64$ bit | Public key polynomial |
| `0x2` | `mG` | Dense | $277 \times 64$ bit | Codeword (mapped into $V$) |
| `0x3` | `u` | Dense | $277 \times 64$ bit | Ciphertext component 1 |
| `0x4` | `v` | Dense | $277 \times 64$ bit | Ciphertext component 2 |
| `0x5` | `r1` | Sparse | $75 \times 15$ bit | Encryption ephemeral vector |
| `0x6` | `r2` | Sparse | $75 \times 15$ bit | Encryption ephemeral vector |
| `0x7` | `e` | Sparse | $75 \times 15$ bit | Encryption error vector |
| `0x8` | `y` | Sparse | $66 \times 15$ bit | KeyGen secret vector |
| `0x9` | `n` | Dense | $277 \times 64$ bit | Decryption input (mapped into $U$) |
| `0xA` | `x` | Dense | $277 \times 64$ bit | KeyGen secret dense vector |

---

## Verification and Testing

### 1. Software Verification Harness

The driver verification suite includes a bit-level simulation harness validating against the official NIST Round 4 Known Answer Test (Vector 0):

```bash
cd sw
make
make run
```

Expected output:
```text
HQC-128 PKE Coprocessor Verification Harness
Platform: 32-bit MMIO Bridge | Target: Artix-7 (xc7a200t)

[PASS] KeyGen completed (19,796 cycles | 166 us @ 119 MHz)
[PASS] Encap completed  (45,677 cycles | 384 us @ 119 MHz)
[PASS] Decap completed  (23,789 cycles | 200 us @ 119 MHz)

Test Result: 100% Bit-Exact Match (0 mismatches against NIST KAT)
```

### 2. Vivado RTL Behavioral Simulation

To run the complete hardware simulation with Vivado XSim:

```bash
vivado -mode batch -source scripts/run_sim.tcl
```

For 100-vector extensive NIST KAT verification:
- Open Vivado GUI or run batch mode targeting `hw/tb/tb_top_pke_ref.v`.
- The testbench verifies 100 consecutive pseudo-random vectors across KeyGen, Encap, and Decap.
- Verification status: `S Mismatch: 0`, `U Mismatch: 0`, `V Mismatch: 0`, `M Mismatch: 0`.

---

## License

This project is licensed under the Apache 2.0 License. Reference codec implementations are derived from the Technology Innovation Institute (TII) open-source repository.
