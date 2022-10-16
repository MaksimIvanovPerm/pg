#!/bin/bash
v_roster="$HOME/.pgtab"
v_count="$#"
v_index="0"
v_str=""
v_cmd=""

##############################################
if [ -f "$v_roster" ]; then
   echo "SCOPE,NODENAME,DATA_DIR,LISTEN,BIN_DIR,PGPASS" > "$v_roster"
fi

v_count=$((v_count-1))
if [ "$v_count" -gt "0" ]; then
   while [ "$v_index" -lt "$v_count" ]; do
         #echo "(${v_index}/${v_count}) $1"
         if [ -z "$v_str" ]; then
            v_str="$1"
         else
            v_str="${v_str},$1"
         fi
         shift
         v_index=$((v_index+1))
   done
   v_cmd="cat \"$v_roster\" | egrep -m 1 -q \"^$v_str\$\""
#   echo "$v_cmd"
#   cat "$v_roster" | egrep -m 1 -q -- "$v_str"
   eval "$v_cmd"
   [ "$?" -ne "0" ] && echo "$v_str" >> "$v_roster"
fi
