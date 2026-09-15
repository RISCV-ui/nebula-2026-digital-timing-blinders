# PPA and timing comparison

- **before:** `baseline` · stage `6_final` · 2026-09-14T09:44:17
- **after:**  `openrouter_nemotron-ultra` · stage `6_final` · 2026-09-14T09:44:52

## Area, power, congestion

| metric | before | after | change | |
|---|---|---|---|---|
| Instances | 488,118 | 489,340 | +1,222 (+0.25%) | worse |
| Cell area | 1,914,043 um^2 | 1,905,391 um^2 | -8,652 (-0.45%) | better |
| Nets | 143,367 | 142,790 | -577 (-0.40%) | better |
| Utilisation | 54 % | 54 % | +0 (+0.00%) | same |
| Total power | not reported | not reported | -- | not reported |
| WNS (setup) | -126.6293 ns | -130.0722 ns | -3.4429 (-2.72%) | worse |
| TNS (setup) | -97,704.1328 ns | -97,854.0312 ns | -149.8984 (-0.15%) | worse |
| WNS (hold) | -0.082 ns | -0.1233 ns | -0.0413 (-50.37%) | worse |
| TNS (hold) | -0.4563 ns | -0.4373 ns | +0.019 (+4.16%) | better |
| DRC violations | 0 | 0 | +0 | same |
| Antenna violations | not reported | not reported | -- | not reported |

## Per-clock timing and achievable frequency

Fmax is estimated as `1/(period - WNS)` because no measured period sweep was supplied.

A **generated** clock's Fmax is the speed its own paths could stand, not a speed the design can be run at: it is divided down from a master, so it moves only when the master moves and is capped by the master's own slack. The design frequency is set by the master clocks; the generated rows are there to show where the slack sits, not to be quoted as headroom.

| clock | period | WNS before | WNS after | ΔWNS | Fmax before | Fmax after |
|---|---|---|---|---|---|---|
| `clk1` | 10.0 ns | -126.6293 ns | -130.0722 ns | -3.4429 | 7.3 MHz | 7.1 MHz |
| `clk2` | 20.0 ns | no paths | no paths | -- | -- | -- |
| `clk3` | 12.5 ns | no paths | no paths | -- | -- | -- |
| `clk4` | 25.0 ns | no paths | no paths | -- | -- | -- |
| `clk5` | 40.0 ns | no paths | no paths | -- | -- | -- |
| `clk_s1` | 25.0 ns | +16.9266 ns | +16.8139 ns | -0.1127 | 123.9 MHz | 122.2 MHz |
| `clk_s1_gate` | 25.0 ns | +23.1259 ns | +23.7575 ns | +0.6316 | 533.6 MHz | 804.8 MHz |
| `clk_s2` | 20.0 ns | -27.8000 ns | -26.1916 ns | +1.6084 | 20.9 MHz | 21.6 MHz |
| `clk_s2_gate` | 20.0 ns | +17.9242 ns | +18.2547 ns | +0.3305 | 481.7 MHz | 573.0 MHz |
| `clk_s3` | 10.0 ns | -0.1019 ns | -0.1529 ns | -0.0510 | 99.0 MHz | 98.5 MHz |
| `clk_s4` | 40.0 ns | +0.1477 ns | +0.1690 ns | +0.0213 | 25.1 MHz | 25.1 MHz |
| `clk_s4_gate` | 40.0 ns | +37.8683 ns | +38.1912 ns | +0.3229 | 469.1 MHz | 552.9 MHz |
| `clk_s5` | 12.5 ns | -29.3740 ns | -29.4915 ns | -0.1175 | 23.9 MHz | 23.8 MHz |
| `clk_s5_gate` | 12.5 ns | +10.5934 ns | +10.7228 ns | +0.1294 | 524.5 MHz | 562.7 MHz |
| `clk_s8` | 10.0 ns | -3.3171 ns | -1.9365 ns | +1.3806 | 75.1 MHz | 83.8 MHz |

**6 of 11 constrained clocks meet timing after optimisation** (was 6). 4 clocks reported no path and are excluded from that count -- an unconstrained domain is an open question, not a pass.

Clocks whose slack got worse: `clk1`, `clk_s1`, `clk_s3`, `clk_s5`.
