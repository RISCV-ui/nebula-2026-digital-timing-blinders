# PPA and timing comparison

- **before:** `baseline_signoff` · stage `6_final` · 2026-09-10T12:26:28
- **after:**  `final_candidate_signoff` · stage `6_final` · 2026-09-10T18:55:57

## Area, power, congestion

| metric | before | after | change | |
|---|---|---|---|---|
| Instances | 480,545 | 475,618 | -4,927 (-1.03%) | better |
| Cell area | 1,746,071 um^2 | 1,718,209 um^2 | -27,862 (-1.60%) | better |
| Nets | 121,589 | 116,411 | -5,178 (-4.26%) | better |
| Utilisation | 49 % | 49 % | +0 (+0.00%) | same |
| Total power | not reported | not reported | -- | not reported |
| WNS (setup) | -25.2539 ns | -0.1659 ns | +25.088 (+99.34%) | better |
| TNS (setup) | -3,384.4421 ns | -1.9487 ns | +3,382.4934 (+99.94%) | better |
| WNS (hold) | -0.1329 ns | -0.0117 ns | +0.1212 (+91.20%) | better |
| TNS (hold) | -2.5864 ns | -0.0357 ns | +2.5507 (+98.62%) | better |
| DRC violations | 0 | 0 | +0 | same |
| Antenna violations | not reported | not reported | -- | not reported |

## Per-clock timing and achievable frequency

Fmax is measured by binary search over each clock's SDC period with extracted parasitics and propagated clocks.

A **generated** clock's Fmax is the speed its own paths could stand, not a speed the design can be run at: it is divided down from a master, so it moves only when the master moves and is capped by the master's own slack. The design frequency is set by the master clocks; the generated rows are there to show where the slack sits, not to be quoted as headroom.

| clock | period | WNS before | WNS after | ΔWNS | Fmax before | Fmax after |
|---|---|---|---|---|---|---|
| `clk1` | 10.0 ns | -0.9670 ns | -0.1659 ns | +0.8011 | 86.8 MHz | 95.9 MHz |
| `clk2` | 20.0 ns | no paths | no paths | -- | -- | -- |
| `clk3` | 12.5 ns | no paths | no paths | -- | -- | -- |
| `clk4` | 25.0 ns | no paths | no paths | -- | -- | -- |
| `clk5` | 40.0 ns | no paths | no paths | -- | -- | -- |
| `clk_s1` | 25.0 ns | +18.5562 ns | +17.2714 ns | -1.2848 | 154.7 MHz | 126.7 MHz |
| `clk_s1_gate` | 25.0 ns | +23.8439 ns | +23.0861 ns | -0.7578 | 800.0 MHz | 510.9 MHz |
| `clk_s2` | 20.0 ns | +11.7365 ns | +11.9371 ns | +0.2006 | 117.5 MHz | 123.5 MHz |
| `clk_s2_gate` | 20.0 ns | +17.9100 ns | +17.8441 ns | -0.0659 | 473.9 MHz | 450.9 MHz |
| `clk_s3` | 10.0 ns | -0.1499 ns | +0.1248 ns | +0.2747 | 95.9 MHz | 100.8 MHz |
| `clk_s4` | 40.0 ns | +32.9459 ns | +31.1937 ns | -1.7522 | 137.0 MHz | 112.3 MHz |
| `clk_s4_gate` | 40.0 ns | +38.1878 ns | +38.3260 ns | +0.1382 | 500.0 MHz | 500.0 MHz |
| `clk_s5` | 12.5 ns | -25.2539 ns | +1.4876 ns | +26.7415 | 25.6 MHz | 89.1 MHz |
| `clk_s5_gate` | 12.5 ns | +10.5825 ns | +10.6704 ns | +0.0879 | 508.9 MHz | 534.8 MHz |
| `clk_s8` | 10.0 ns | -1.1998 ns | -0.1494 ns | +1.0504 | 86.8 MHz | 95.9 MHz |

**9 of 11 constrained clocks meet timing after optimisation** (was 7). 4 clocks reported no path and are excluded from that count -- an unconstrained domain is an open question, not a pass.

Clocks whose slack got worse: `clk_s1`, `clk_s1_gate`, `clk_s2_gate`, `clk_s4`.
