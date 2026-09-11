# PPA and timing comparison

- **before:** `baseline_signoff` · stage `6_final` · 2026-09-10T12:26:28
- **after:**  `audit_signoff_opt` · stage `6_final` · 2026-09-10T00:37:06

## Area, power, congestion

| metric | before | after | change | |
|---|---|---|---|---|
| Instances | 480,545 | 476,324 | -4,221 (-0.88%) | better |
| Cell area | 1,746,071 um^2 | 1,718,957 um^2 | -27,114 (-1.55%) | better |
| Nets | 121,589 | 115,964 | -5,625 (-4.63%) | better |
| Utilisation | 49 % | 49 % | +0 (+0.00%) | same |
| Total power | not reported | not reported | -- | not reported |
| WNS (setup) | -25.2539 ns | -0.2274 ns | +25.0265 (+99.10%) | better |
| TNS (setup) | -3,384.4421 ns | -4.082 ns | +3,380.3601 (+99.88%) | better |
| WNS (hold) | -0.1329 ns | -0.0512 ns | +0.0817 (+61.47%) | better |
| TNS (hold) | -2.5864 ns | -0.5316 ns | +2.0548 (+79.45%) | better |
| DRC violations | 0 | 0 | +0 | same |
| Antenna violations | not reported | not reported | -- | not reported |

## Per-clock timing and achievable frequency

Fmax is measured by binary search over each clock's SDC period with extracted parasitics and propagated clocks.

A **generated** clock's Fmax is the speed its own paths could stand, not a speed the design can be run at: it is divided down from a master, so it moves only when the master moves and is capped by the master's own slack. The design frequency is set by the master clocks; the generated rows are there to show where the slack sits, not to be quoted as headroom.

| clock | period | WNS before | WNS after | ΔWNS | Fmax before | Fmax after |
|---|---|---|---|---|---|---|
| `clk1` | 10.0 ns | -0.9670 ns | -0.2274 ns | +0.7396 | 86.8 MHz | 95.9 MHz |
| `clk2` | 20.0 ns | no paths | no paths | -- | -- | -- |
| `clk3` | 12.5 ns | no paths | no paths | -- | -- | -- |
| `clk4` | 25.0 ns | no paths | no paths | -- | -- | -- |
| `clk5` | 40.0 ns | no paths | no paths | -- | -- | -- |
| `clk_s1` | 25.0 ns | +18.5562 ns | +17.3372 ns | -1.2190 | 154.7 MHz | 126.7 MHz |
| `clk_s1_gate` | 25.0 ns | +23.8439 ns | +22.8394 ns | -1.0045 | 800.0 MHz | 462.4 MHz |
| `clk_s2` | 20.0 ns | +11.7365 ns | +12.5832 ns | +0.8467 | 117.5 MHz | 129.8 MHz |
| `clk_s2_gate` | 20.0 ns | +17.9100 ns | +18.0074 ns | +0.0974 | 473.9 MHz | 498.0 MHz |
| `clk_s3` | 10.0 ns | -0.1499 ns | +0.2514 ns | +0.4013 | 95.9 MHz | 100.8 MHz |
| `clk_s4` | 40.0 ns | +32.9459 ns | +33.3002 ns | +0.3543 | 137.0 MHz | 144.0 MHz |
| `clk_s4_gate` | 40.0 ns | +38.1878 ns | +37.9392 ns | -0.2486 | 500.0 MHz | 476.2 MHz |
| `clk_s5` | 12.5 ns | -25.2539 ns | +1.9054 ns | +27.1593 | 25.6 MHz | 93.6 MHz |
| `clk_s5_gate` | 12.5 ns | +10.5825 ns | +10.2824 ns | -0.3001 | 508.9 MHz | 438.4 MHz |
| `clk_s8` | 10.0 ns | -1.1998 ns | -0.1858 ns | +1.0140 | 86.8 MHz | 95.9 MHz |

**9 of 11 constrained clocks meet timing after optimisation** (was 7). 4 clocks reported no path and are excluded from that count -- an unconstrained domain is an open question, not a pass.

Clocks whose slack got worse: `clk_s1`, `clk_s1_gate`, `clk_s4_gate`, `clk_s5_gate`.
