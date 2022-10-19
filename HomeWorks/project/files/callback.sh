#!/bin/bash
v_roster="$HOME/.pgtab"
v_count="$#"
v_index="0"
v_file="/tmp/dump.txt"
VIP="192.168.0.13"

   date >> "$v_file"
#   while [ "$v_index" -lt "$v_count" ]; do
#         echo "(${v_index}/${v_count}) $1" >> "$v_file"
#         shift
#         v_index=$((v_index+1))
#   done

unset_vip(){
local vip="$VIP"
}

set_vip(){
local vip="$VIP"
}
update_pgtab(){
local v_str="$1"
local v_cmd=""

v_cmd="cat \"$v_roster\" | egrep -m 1 -q \"^$v_str\$\""
eval "$v_cmd"
[ "$?" -ne "0" ] && echo "$v_str" >> "$v_roster"
}
##################################################
# "postgres" "postgresql1" "/var/lib/postgresql/15/main" "0.0.0.0:5432" "/usr/lib/postgresql/15/bin" "qaz1"
readonly v_scope="$1"
readonly v_nodename="$2"
readonly v_datadir="$3"
readonly v_pglisten="$4"
readonly v_bindir="$5"
readonly v_supwd="$6"
readonly v_cbname="$7"
readonly v_role="$8"
readonly v_scope2="$9"
readonly v_line="${v_scope2},${v_nodename},${v_datadir},${v_pglisten},${v_bindir},${v_supwd},${v_role}"

case "$v_cbname" in
     "on_stop")
       unset_vip
     ;;
     "on_start"|"on_role_change")
       update_pgtab "$v_line"
       if [ "$v_role" == "master" ]; then
          set_vip
       else
          unset_vip
       fi
     ;;
esac
