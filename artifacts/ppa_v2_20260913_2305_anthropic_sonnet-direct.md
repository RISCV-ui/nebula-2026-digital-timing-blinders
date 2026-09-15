# PPA and timing comparison

- **before:** `baseline` · stage `6_final` · 2026-09-14T09:44:17
- **after:**  `anthropic_sonnet-direct` · stage `6_final` · 2026-09-14T09:43:42

## Area, power, congestion

| metric | before | after | change | |
|---|---|---|---|---|
| Instances | 488,118 | 488,607 | +489 (+0.10%) | worse |
| Cell area | 1,914,043 um^2 | 1,913,142 um^2 | -901 (-0.05%) | better |
| Nets | 143,367 | 143,398 | +31 (+0.02%) | worse |
| Utilisation | 54 % | 54 % | +0 (+0.00%) | same |
| Total power | not reported | not reported | -- | not reported |
| WNS (setup) | -126.6293 ns | -124.116 ns | +2.5133 (+1.98%) | better |
| TNS (setup) | -97,704.1328 ns | -94,156.3203 ns | +3,547.8125 (+3.63%) | better |
| WNS (hold) | -0.082 ns | -0.0583 ns | +0.0237 (+28.90%) | better |
| TNS (hold) | -0.4563 ns | -0.0854 ns | +0.3709 (+81.28%) | better |
| DRC violations | 0 | 0 | +0 | same |
| Antenna violations | not reported | not reported | -- | not reported |

## Per-clock timing and achievable frequency

Fmax is estimated as `1/(period - WNS)` because no measured period sweep was supplied.

A **generated** clock's Fmax is the speed its own paths could stand, not a speed the design can be run at: it is divided down from a master, so it moves only when the master moves and is capped by the master's own slack. The design frequency is set by the master clocks; the generated rows are there to show where the slack sits, not to be quoted as headroom.

| clock | period | WNS before | WNS after | ΔWNS | Fmax before | Fmax after |
|---|---|---|---|---|---|---|
| `clk1` | 10.0 ns | -126.6293 ns | -124.1160 ns | +2.5133 | 7.3 MHz | 7.5 MHz |
| `clk2` | 20.0 ns | no paths | no paths | -- | -- | -- |
| `clk3` | 12.5 ns | no paths | no paths | -- | -- | -- |
| `clk4` | 25.0 ns | no paths | no paths | -- | -- | -- |
| `clk5` | 40.0 ns | no paths | no paths | -- | -- | -- |
| `clk_s1` | 25.0 ns | +16.9266 ns | +16.6978 ns | -0.2288 | 123.9 MHz | 120.5 MHz |
| `clk_s1_gate` | 25.0 ns | +23.1259 ns | +23.1085 ns | -0.0174 | 533.6 MHz | 528.7 MHz |
| `clk_s2` | 20.0 ns | -27.8000 ns | -26.1961 ns | +1.6039 | 20.9 MHz | 21.6 MHz |
| `clk_s2_gate` | 20.0 ns | +17.9242 ns | +17.8225 ns | -0.1017 | 481.7 MHz | 459.2 MHz |
| `clk_s3` | 10.0 ns | -0.1019 ns | -0.1641 ns | -0.0622 | 99.0 MHz | 98.4 MHz |
| `clk_s4` | 40.0 ns | +0.1477 ns | -0.4108 ns | -0.5585 | 25.1 MHz | 24.7 MHz |
| `clk_s4_gate` | 40.0 ns | +37.8683 ns | +37.8132 ns | -0.0551 | 469.1 MHz | 457.3 MHz |
| `clk_s5` | 12.5 ns | -29.3740 ns | -29.4746 ns | -0.1006 | 23.9 MHz | 23.8 MHz |
| `clk_s5_gate` | 12.5 ns | +10.5934 ns | +11.0465 ns | +0.4531 | 524.5 MHz | 688.0 MHz |
| `clk_s8` | 10.0 ns | -3.3171 ns | -2.1431 ns | +1.1740 | 75.1 MHz | 82.4 MHz |

**5 of 11 constrained clocks meet timing after optimisation** (was 6). 4 clocks reported no path and are excluded from that count -- an unconstrained domain is an open question, not a pass.

Clocks whose slack got worse: `clk_s1`, `clk_s1_gate`, `clk_s2_gate`, `clk_s3`, `clk_s4`, `clk_s4_gate`, `clk_s5`.
