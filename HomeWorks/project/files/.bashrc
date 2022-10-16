#cd
#export PATH=$PATH:/usr/lib/postgresql/15/bin

v_roster="$HOME/.pgtab"
### subroutines
set_pgenv_to_default(){
export PGDATABASE=""
export PGHOST=""
export PGPORT=""
export PGUSER=""
export PGCONF=""
export PGPASSFILE=""

export BIN_DIR=""
export HBAFILE=""
export PGDATA=""
export CLUSTER=""
export CLUSTER_VERSION=""
export CLUSTER_NAME=""
export PGLOG=""
export V_RECOVERMODE="Unknown"
}
export -f set_pgenv_to_default

set_pgenv_to_givencluster(){
if [ "$#" -ne "2" ]; then
   echo "Usage: set_pgenv_to_givencluster <scope> <nodename>"
   return 1
fi

local v_scope="$1"
local v_nodename="$2"
local v_str=$( cat "$v_roster" | egrep "^${v_scope},${v_nodename}.*" )
local v_rc

set_pgenv_to_default
PGDATA=$( echo -n "$v_str" | cut -f 3 -d "," )
export PGDATA="$PGDATA"

PGHOST=$( echo -n "$v_str" | cut -f 4 -d "," | cut -f 1 -d ":" )
case "$PGHOST" in
     "0.0.0.0") PGHOST="localhost"
     ;;
esac
export PGHOST="$PGHOST"

PGPORT=$( echo -n "$v_str" | cut -f 4 -d "," | cut -f 2 -d ":" )
export PGPORT="$PGPORT"

BIN_DIR=$( echo -n "$v_str" | cut -f 5 -d "," )
export BIN_DIR="$BIN_DIR"
export PATH=$PATH:$BIN_DIR

PGPASSFILE=$( echo -n "$v_str" | cut -f 6 -d "," )
export PGPASSFILE="$PGPASSFILE"

pg_isready -h $PGHOST -p $PGPORT -t 5 -q
v_rc="$?"

if [ "$v_rc" -eq "0" ]; then
   PGCONF=$( psql -tc "show config_file;" 2>/dev/null | tr -d [:cntrl:] | sed -r "s/^ +//" )
   export PGCONF="$PGCONF"
   HBAFILE=$( psql -tc "show hba_file;" 2>/dev/null | tr -d [:cntrl:] | sed -r "s/^ +//" )
   export HBAFILE="$HBAFILE"
#   PGDATA=$( psql -t -c "show data_directory;" 2>/dev/null | tr -d [:cntrl:] | sed -r "s/^ +//" )
#   export PGDATA="$PGDATA"
   CLUSTER=$( psql -c "show cluster_name" -t --csv )
   export CLUSTER="$CLUSTER"
   CLUSTER_VERSION=$( psql -tc "SHOW server_version_num;" 2>/dev/null | sed -r "s/^ +//" | sed -r "s/ +/ /g" )
   export CLUSTER_VERSION="$CLUSTER_VERSION"
   CLUSTER_NAME=$( psql -tc "show cluster_name;" 2>/dev/null | tr -d [:cntrl:] | sed -r "s/^ +//" )
   export CLUSTER_NAME="$CLUSTER_NAME"

   PGLOG=$( psql -tc "show logging_collector;" 2>/dev/null | tr -d [:cntrl:] | sed -r "s/^ +//" )
   if [ "$PGLOG" == 'off' ]; then
       PGLOG="syslog"
   else
      PGLOG=$( psql -tc "SELECT  pg_current_logfile();" 2>/dev/null | tr -d [:cntrl:] | sed -r "s/^ +//" )
      PGLOG="${PGDATA}/${PGLOG}"
   fi
   export PGLOG="$PGLOG"
   if [ ! -z "$PGCONF" ]; then
      v_str=$( psql -tc "select pg_is_in_recovery();" | tr -d [:space:] | tr [:upper:] [:lower:] )
      [ "$v_str" == "t" ] && V_RECOVERMODE="In_Recovery"
      [ "$v_str" == "f" ] && V_RECOVERMODE="Not_in_recovery"
   fi
#   if [ -f "$PGCONF" ]; then
#      alias epconf='vim "$PGCONF"'
#      alias show_pgconf='egrep "^[^#]\w+.*" $PGCONF | sort -k 1'
#   fi
#   if [ -f "$HBAFILE" ]; then
#      alias ehbafile='vim "$HBAFILE"'
#   fi
#   if [ -f "$PGLOG" ]; then
#      alias lesspglog='less "$PGLOG"'
#   fi
else
    echo "Database in $PGDATA and ${PGHOST}:${PGPORT} is not ready right now;"
    echo "So: it is not possible to find out and initialize all env-variables related to this database"
fi
}

show_pgenv(){
cat << __EOF__ | column -t
PGDATABASE "$PGDATABASE"
PGHOST "$PGHOST"
PGPORT "$PGPORT"
PGUSER "$PGUSER"
PGCONF "$PGCONF"
PGPASSFILE "$PGPASSFILE"
HBAFILE "$HBAFILE"
PGDATA "$PGDATA"
CLUSTER "$CLUSTER"
CLUSTER_VERSION "$CLUSTER_VERSION"
CLUSTER_NAME "$CLUSTER_NAME"
PGLOG "$PGLOG"
V_RECOVERMODE "$V_RECOVERMODE"
BIN_DIR "$BIN_DIR"
__EOF__
}
export -f show_pgenv

set_pgcluster(){
local v_count=""

if [ ! -f "$v_roster" ]; then
   echo "There is no file ${v_roster}"
   echo "It is supposed to be and contains info about inited patroni-management pg-clusters"
   return 1
fi

v_count=$( cat "$v_roster" | wc -l )
if [ "$v_count" -eq "0" ]; then
   echo "File ${v_roster} does not conain any data"
   return 1
fi

if [ "$#" -ne "2" ]; then
   echo "Usage: set_pgcluster <scope> <nodename>"
   echo "There is the following information abount inited patroni-management pg-clusters here"
   cat "$v_roster" | column -t -s ","
   return 1
fi

local v_scope="$1"
local v_nodename="$2"
set_pgenv_to_givencluster "$v_scope" "$v_nodename"
show_pgenv
}
export -f set_pgcluster
### main
cd
export PATRONI_CONF="/etc/patroni/patroni.yml"
set_pgcluster
