#!/bin/bash
LOCK_FILE="$HOME/pg_profile/pg_profile.lck"
LOG_FILE="$HOME/pg_profile/pg_profile.log"
SILENT=${VERBOSE_LVL:-0}
PG_HOST="localhost"
PG_PORT="5432"

##### functions
output(){
local v_msg="$1"
local v_ts

if [ ! -z "$v_msg" ]; then
   v_ts=$(date +%Y%m%d:%H%M%S)
   [ "$SILENT" -ne "0" ] && echo "${v_ts} ${v_msg}"
   [ -f "$LOG_FILE" ] echo "${v_ts} ${v_msg}" >> "$LOG_FILE"
fi
}
##### main
if [ -f "$LOCK_FILE" ]; then
     output "lock file ${LOCK_FILE} already is;"
     exit
else
    echo "$$" > "$LOCK_FILE"
    [ ! -f "$LOG_FILE" ] && touch "$LOG_FILE"
    pg_isready -t 1 -q -h "$PG_HOST" -p "$PG_PORT"
    rc="$?"
    if [ "$rc" -ne "0" ]; then
         output "for some reason pg-cluster at ${PG_HOST}:${PG_PORT} is not available"
         exit
    else
         output "taking sample;"
         psql -c 'SELECT take_sample()' 1>>"$LOG_FILE" 2>>"$LOG_FILE"
    fi
    rm -f "$LOCK_FILE" 2>/dev/null
fi
