#!/bin/sh
export OPENRAM_TECH="/home/shubhanshu/eda/OpenRAM/technology:/home/shubhanshu/eda/OpenRAM/compiler/../technology"
echo "$(date): Starting LVS using Netgen /nix/store/h3crgmx1w7h86qjpr131igi7p576mp3x-netgen-1.5.318/bin/netgen"
/nix/store/h3crgmx1w7h86qjpr131igi7p576mp3x-netgen-1.5.318/bin/netgen -noconsole << EOF
lvs {tag_memory_92x64.spice tag_memory_92x64} {tag_memory_92x64.lvs.sp tag_memory_92x64} setup.tcl tag_memory_92x64.lvs.report -full -json
quit
EOF
magic_retcode=$?
echo "$(date): Finished ($magic_retcode) LVS using Netgen /nix/store/h3crgmx1w7h86qjpr131igi7p576mp3x-netgen-1.5.318/bin/netgen"
exit $magic_retcode
