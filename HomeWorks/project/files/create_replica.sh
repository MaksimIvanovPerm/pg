#!/bin/bash
v_file="/tmp/dump.txt"
v_count="$#"
v_index="0"

   date >> "$v_file"
   while [ "$v_index" -lt "$v_count" ]; do
         echo "(${v_index}/${v_count}) $1" >> "$v_file"
         shift
         v_index=$((v_index+1))
   done

exit 1
