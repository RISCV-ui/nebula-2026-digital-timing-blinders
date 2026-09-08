# Manual macro placement -- soc_top, sky130hd.
#
# Why this file exists. Both OpenRAM macros obstruct met1, met2, met3 AND
# met4 across their whole area (met4 alone has 718 OBS rects), so the only
# layer that can cross a macro is met5. Ten macros cover about 5.0e6 um2 of
# a 17.2e6 um2 core, and with automatic placement they landed scattered
# through the middle of it: 17,352 of the 20,000 reported congestion tiles
# were "capacity:0", i.e. global routing pushed nets into gcells the macros
# had already blocked, and the run died with GRT-0116.
#
# So the macros go in one left-hand column instead, and the std cells get
# an unbroken strip to the right. Every signal pin on both macros sits on
# the BOTTOM edge (the LEF rects run y = 0.0 to 0.38), so each macro is R0
# and gets a full-width channel underneath it for the 256-bit data bus and
# the tag comparators to land in.
#
# Macros are grouped by owner -- d_cache_0 low, the i-cache high -- so
# neither cache's bus has to run the length of the column.
# d_cache_0/tag_mem_0/u_macro: 1530.38 x 234.245, spans y 195.84 .. 430.085
place_macro -macro_name d_cache_0/tag_mem_0/u_macro -location {25.3 195.84} -orientation R0
# d_cache_0/i_mem_0/u_macro: 2228.76 x 226.435, spans y 598.4 .. 824.835
place_macro -macro_name d_cache_0/i_mem_0/u_macro -location {25.3 598.4} -orientation R0
# d_cache_0/i_mem_1/u_macro: 2228.76 x 226.435, spans y 992.8 .. 1219.235
place_macro -macro_name d_cache_0/i_mem_1/u_macro -location {25.3 992.8} -orientation R0
# d_cache_0/i_mem_2/u_macro: 2228.76 x 226.435, spans y 1387.2 .. 1613.635
place_macro -macro_name d_cache_0/i_mem_2/u_macro -location {25.3 1387.2} -orientation R0
# d_cache_0/i_mem_3/u_macro: 2228.76 x 226.435, spans y 1781.6 .. 2008.035
place_macro -macro_name d_cache_0/i_mem_3/u_macro -location {25.3 1781.6} -orientation R0
# processor_0/if_stage/i_cache_0/i_mem_0/u_macro: 2228.76 x 226.435, spans y 2176.0 .. 2402.435
place_macro -macro_name processor_0/if_stage/i_cache_0/i_mem_0/u_macro -location {25.3 2176.0} -orientation R0
# processor_0/if_stage/i_cache_0/i_mem_1/u_macro: 2228.76 x 226.435, spans y 2570.4 .. 2796.835
place_macro -macro_name processor_0/if_stage/i_cache_0/i_mem_1/u_macro -location {25.3 2570.4} -orientation R0
# processor_0/if_stage/i_cache_0/i_mem_2/u_macro: 2228.76 x 226.435, spans y 2964.8 .. 3191.235
place_macro -macro_name processor_0/if_stage/i_cache_0/i_mem_2/u_macro -location {25.3 2964.8} -orientation R0
# processor_0/if_stage/i_cache_0/i_mem_3/u_macro: 2228.76 x 226.435, spans y 3359.2 .. 3585.635
place_macro -macro_name processor_0/if_stage/i_cache_0/i_mem_3/u_macro -location {25.3 3359.2} -orientation R0
# processor_0/if_stage/i_cache_0/tag_mem_0/u_macro: 1530.38 x 234.245, spans y 3753.6 .. 3987.845
place_macro -macro_name processor_0/if_stage/i_cache_0/tag_mem_0/u_macro -location {25.3 3753.6} -orientation R0
