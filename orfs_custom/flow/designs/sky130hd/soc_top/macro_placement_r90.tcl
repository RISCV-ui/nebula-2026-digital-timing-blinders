# Macro floorplan -- soc_top, sky130hd. Ten OpenRAM macros, R90, two rows.
#
# Why R90. Runs 2 and 3 both died with GRT-0116, and the final congestion
# report says where: of 167,419 total congestion, met2 carries 119,223 (71%),
# against 23,060 on met1 and 9,759 on met3. 17,022 of the 20,000 reported hot
# tiles read "capacity:0" -- global routing pushed into gcells a macro had
# already blocked. met2 is the VERTICAL layer in sky130hd (met1 H, met2 V,
# met3 H, met4 V, met5 H). Unrotated, a macro is 2228 um wide and 226 um tall,
# so it blocks vertical routing across its full 2228 um width: the worst shape
# for the one layer that is short. Rotated it is 226 x 2229 and blocks
# vertical routing over only 226 um, moving the pressure onto met1/met3 where
# the headroom is. Both LEFs declare SYMMETRY X Y R90.
#
# Why two rows and not one. MPL-0034's core-bounds check runs BEFORE the
# orientation is applied, so it tests x + 2228.76 (the un-rotated master
# width), not x + 226. Every macro origin therefore has to sit at
# x <= 2946.2 however it is rotated. One row of ten cannot
# satisfy that; two rows of five can, with 400 um between columns.
#
# Rotating also turns the pin edge (originally the bottom, y = 0.0 .. 0.38)
# into the LEFT edge, so every macro's pins face a full-height 400 um
# channel instead of a short horizontal slot.
#
# Rows are grouped by owner -- d-cache low, i-cache high -- so neither cache's
# bus runs the length of the array. Macros occupy x 425 .. 3166,
# leaving x 3166 .. 5175 clear for logic. Sized for
# DIE_AREA 0 0 5200 5200.

# d_cache_0/tag_mem_0/u_macro: spans (425.5, 27.2) - (659.745, 1557.580)
place_macro -macro_name d_cache_0/tag_mem_0/u_macro -location {425.5 27.2} -orientation R90
# d_cache_0/i_mem_0/u_macro: spans (1059.84, 27.2) - (1286.275, 2255.960)
place_macro -macro_name d_cache_0/i_mem_0/u_macro -location {1059.84 27.2} -orientation R90
# d_cache_0/i_mem_1/u_macro: spans (1686.36, 27.2) - (1912.795, 2255.960)
place_macro -macro_name d_cache_0/i_mem_1/u_macro -location {1686.36 27.2} -orientation R90
# d_cache_0/i_mem_2/u_macro: spans (2312.88, 27.2) - (2539.315, 2255.960)
place_macro -macro_name d_cache_0/i_mem_2/u_macro -location {2312.88 27.2} -orientation R90
# d_cache_0/i_mem_3/u_macro: spans (2939.4, 27.2) - (3165.835, 2255.960)
place_macro -macro_name d_cache_0/i_mem_3/u_macro -location {2939.4 27.2} -orientation R90
# processor_0/if_stage/i_cache_0/i_mem_0/u_macro: spans (425.5, 2500.0) - (651.935, 4728.760)
place_macro -macro_name processor_0/if_stage/i_cache_0/i_mem_0/u_macro -location {425.5 2500.0} -orientation R90
# processor_0/if_stage/i_cache_0/i_mem_1/u_macro: spans (1052.02, 2500.0) - (1278.455, 4728.760)
place_macro -macro_name processor_0/if_stage/i_cache_0/i_mem_1/u_macro -location {1052.02 2500.0} -orientation R90
# processor_0/if_stage/i_cache_0/i_mem_2/u_macro: spans (1678.54, 2500.0) - (1904.975, 4728.760)
place_macro -macro_name processor_0/if_stage/i_cache_0/i_mem_2/u_macro -location {1678.54 2500.0} -orientation R90
# processor_0/if_stage/i_cache_0/i_mem_3/u_macro: spans (2305.06, 2500.0) - (2531.495, 4728.760)
place_macro -macro_name processor_0/if_stage/i_cache_0/i_mem_3/u_macro -location {2305.06 2500.0} -orientation R90
# processor_0/if_stage/i_cache_0/tag_mem_0/u_macro: spans (2931.58, 2500.0) - (3165.825, 4030.380)
place_macro -macro_name processor_0/if_stage/i_cache_0/tag_mem_0/u_macro -location {2931.58 2500.0} -orientation R90
