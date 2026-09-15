# Timing by clock domain

Baseline: `baseline`. Fmax is 1/(period - WNS) for that domain alone.

## anthropic_sonnet-direct

| clock | period ns | WNS before | WNS after | Fmax before | Fmax after | delta |
|---|---|---|---|---|---|---|
| `clk1` | 10.000 | -126.6293 | -124.1160 | 7.32 | 7.46 | +0.14 MHz |
| `clk2` | 20.000 | -- | -- | -- | -- | slack near period; Fmax not quoted |
| `clk3` | 12.500 | -- | -- | -- | -- | slack near period; Fmax not quoted |
| `clk4` | 25.000 | -- | -- | -- | -- | slack near period; Fmax not quoted |
| `clk5` | 40.000 | -- | -- | -- | -- | slack near period; Fmax not quoted |
| `clk_s1` | 25.000 | 16.9266 | 16.6978 | 123.86 | 120.45 | -3.41 MHz |
| `clk_s1_gate` | 25.000 | 23.1259 | 23.1085 | -- | -- | slack near period; Fmax not quoted |
| `clk_s2` | 20.000 | -27.8000 | -26.1961 | 20.92 | 21.65 | +0.73 MHz |
| `clk_s2_gate` | 20.000 | 17.9242 | 17.8225 | -- | -- | slack near period; Fmax not quoted |
| `clk_s3` | 10.000 | -0.1019 | -0.1641 | 98.99 | 98.39 | -0.61 MHz |
| `clk_s4` | 40.000 | 0.1477 | -0.4108 | 25.09 | 24.75 | -0.35 MHz |
| `clk_s4_gate` | 40.000 | 37.8683 | 37.8132 | -- | -- | slack near period; Fmax not quoted |
| `clk_s5` | 12.500 | -29.3740 | -29.4746 | 23.88 | 23.82 | -0.06 MHz |
| `clk_s5_gate` | 12.500 | 10.5934 | 11.0465 | -- | -- | slack near period; Fmax not quoted |
| `clk_s8` | 10.000 | -3.3171 | -2.1431 | 75.09 | 82.35 | +7.26 MHz |

Design WNS: -126.6293 -> -124.116 ns (governed by the worst domain, not by the domains above).

Domains that improved: `clk1` +0.14 MHz, `clk_s2` +0.73 MHz, `clk_s8` +7.26 MHz.

## openrouter_nemotron-ultra

| clock | period ns | WNS before | WNS after | Fmax before | Fmax after | delta |
|---|---|---|---|---|---|---|
| `clk1` | 10.000 | -126.6293 | -130.0722 | 7.32 | 7.14 | -0.18 MHz |
| `clk2` | 20.000 | -- | -- | -- | -- | slack near period; Fmax not quoted |
| `clk3` | 12.500 | -- | -- | -- | -- | slack near period; Fmax not quoted |
| `clk4` | 25.000 | -- | -- | -- | -- | slack near period; Fmax not quoted |
| `clk5` | 40.000 | -- | -- | -- | -- | slack near period; Fmax not quoted |
| `clk_s1` | 25.000 | 16.9266 | 16.8139 | 123.86 | 122.16 | -1.71 MHz |
| `clk_s1_gate` | 25.000 | 23.1259 | 23.7575 | -- | -- | slack near period; Fmax not quoted |
| `clk_s2` | 20.000 | -27.8000 | -26.1916 | 20.92 | 21.65 | +0.73 MHz |
| `clk_s2_gate` | 20.000 | 17.9242 | 18.2547 | -- | -- | slack near period; Fmax not quoted |
| `clk_s3` | 10.000 | -0.1019 | -0.1529 | 98.99 | 98.49 | -0.50 MHz |
| `clk_s4` | 40.000 | 0.1477 | 0.1690 | 25.09 | 25.11 | +0.01 MHz |
| `clk_s4_gate` | 40.000 | 37.8683 | 38.1912 | -- | -- | slack near period; Fmax not quoted |
| `clk_s5` | 12.500 | -29.3740 | -29.4915 | 23.88 | 23.81 | -0.07 MHz |
| `clk_s5_gate` | 12.500 | 10.5934 | 10.7228 | -- | -- | slack near period; Fmax not quoted |
| `clk_s8` | 10.000 | -3.3171 | -1.9365 | 75.09 | 83.78 | +8.69 MHz |

Design WNS: -126.6293 -> -130.0722 ns (governed by the worst domain, not by the domains above).

Domains that improved: `clk_s2` +0.73 MHz, `clk_s4` +0.01 MHz, `clk_s8` +8.69 MHz.

