### subroutines
set_pgenv_to_default(){
export PGDATABASE="postgres"
export PGHOST=""
export PGPORT="5432"
export PGUSER="postgres"
export PGCONF=""

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
   echo "Usage: set_pgenv_to_givencluster <version> <cluster_name>"
   return 1
fi

local v_version="$1"
local v_clustername="$2"
local v_cname="${v_version}/${v_clustername}"
local v_flag=0

case "${v_cname}" in
     "14/main" )
     export PGPORT="5432"
     v_flag=1
     ;;
     "14/main_clone" )
     export PGPORT="5433"
     v_flag=1
     ;;
     * ) echo "Unknown pg-cluster: ${v_cname}, env has not been changed;";;
esac

if [ "$v_flag" -eq "1" ]; then
   PGCONF=$( psql -t -c "show config_file;" 2>/dev/null | tr -d [:cntrl:] | sed -r "s/^ +//" )
   export PGCONF="$PGCONF"
   HBAFILE=$( psql -t -c "show hba_file;" 2>/dev/null | tr -d [:cntrl:] | sed -r "s/^ +//" )
   export HBAFILE="$HBAFILE"
   PGDATA=$( psql -t -c "show data_directory;" 2>/dev/null | tr -d [:cntrl:] | sed -r "s/^ +//" )
   export PGDATA="$PGDATA"
   CLUSTER=$( psql -c "show cluster_name" -t --csv )
   CLUSTER_VERSION=$( echo -n "$CLUSTER" | cut -f 1 -d "/" )
   CLUSTER_NAME=$( echo -n "$CLUSTER" | cut -f 2 -d "/" )
   PGLOG=$( pg_lsclusters -h | awk -v cv="$CLUSTER_VERSION" -v cn="$CLUSTER_NAME" '{ if ( ( $1 == cv ) && ( $2 == cn ) ) {printf "%s", $7;} }' )
   if [ ! -f "$PGLOG" ]; then
       echo "Can not find out log file of ${CLUSTER}"
       PGLOG=""
   fi
   if [ ! -z "$PGCONF" ]; then
      v_str=$( psql -tc "select pg_is_in_recovery();" | tr -d [:space:] | tr [:upper:] [:lower:] )
      [ "$v_str" == "t" ] && V_RECOVERMODE="In_Recovery"
      [ "$v_str" == "f" ] && V_RECOVERMODE="Not_in_recovery"
   fi
   if [ -f "$PGCONF" ]; then
      alias epconf='vim "$PGCONF"'
      alias show_pgconf='egrep "^[^#]\w+.*" $PGCONF | sort -k 1'
   fi
   if [ -f "$HBAFILE" ]; then
      alias ehbafile='vim "$HBAFILE"'
   fi
   if [ -f "$PGLOG" ]; then
      alias lesspglog='less "$PGLOG"'
   fi
fi
}

restart_cluster(){
local v_cversion=${1:-"$CLUSTER_VERSION"}
local v_cname=${2:-"$CLUSTER_NAME"}
local v_delay=${3:-5}
local PG_HOST=${4:-"$PGHOST"}
local PG_PORT=${5:-"$PGPORT"}
echo "Trying to restart ${v_cversion} ${v_cname}, with delay between iteration: ${v_delay}"

pg_ctlcluster "$v_cversion" "$v_cname" stop
sleep 2
pg_ctlcluster "$v_cversion" "$v_cname" start
sleep 2
pg_isready -t 1 -q -h "$PG_HOST" -p "$PG_PORT"
rc="$?"
while [ "$rc" -ne "0" ]; do
      echo "wait for cluster shutdowning"
      sleep "$v_delay"
      pg_ctlcluster "$v_cversion" "$v_cname" start
      sleep 1
      pg_isready -t 1 -q -h "$PG_HOST" -p "$PG_PORT"
      rc="$?"
done
echo "cluster ${v_cversion} ${v_cname} restarted"
}

show_pgenv(){
cat << __EOF__ | column -t
PGDATABASE "$PGDATABASE"
PGHOST "$PGHOST"
PGPORT "$PGPORT"
PGUSER "$PGUSER"
PGCONF "$PGCONF"
HBAFILE "$HBAFILE"
PGDATA "$PGDATA"
CLUSTER "$CLUSTER"
CLUSTER_VERSION "$CLUSTER_VERSION"
CLUSTER_NAME "$CLUSTER_NAME"
PGLOG "$PGLOG"
V_RECOVERMODE "$V_RECOVERMODE"
__EOF__
}
export -f show_pgenv

set_pgcluster(){
if [ "$#" -ne "2" ]; then
   echo "Usage: set_pgcluster <version> <cluster_name>"
   return 1
fi

local v_version="$1"
local v_clustername="$2"
set_pgenv_to_givencluster "$v_version" "$v_clustername"
show_pgenv
}
export -f set_pgcluster
### main
cd
set_pgenv_to_default
pg_lsclusters
