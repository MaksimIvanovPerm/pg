cd
PGCONF=""
PGCONF=$( psql -t -c "show config_file;" 2>/dev/null | tr -d [:cntrl:] | sed -r "s/^ +//" )
export PGCONF="$PGCONF"

HBAFILE=""
HBAFILE=$( psql -t -c "show hba_file;" 2>/dev/null | tr -d [:cntrl:] | sed -r "s/^ +//" )
export HBAFILE="$HBAFILE"

PGDATA=""
PGDATA=$( psql -t -c "show data_directory;" 2>/dev/null | tr -d [:cntrl:] | sed -r "s/^ +//" )
export PGDATA="$PGDATA"

CLUSTER=$( psql -c "show cluster_name" -t --csv )
CLUSTER_VERSION=$( echo -n "$CLUSTER" | cut -f 1 -d "/" )
CLUSTER_NAME=$( echo -n "$CLUSTER" | cut -f 2 -d "/" )
#PGLOG="/var/log/postgresql/postgresql-${CLUSTER_VERSION}-${CLUSTER_NAME}.log"
PGLOG=$( pg_lsclusters -h | awk -v cv="$CLUSTER_VERSION" -v cn="$CLUSTER_NAME" '{ if ( ( $1 == cv ) && ( $2 == cn ) ) {printf "%s", $7;} }' )
if [ ! -f "$PGLOG" ]; then
   echo "Can not find out log file of ${CLUSTER}"
   PGLOG=""
fi

if [ ! -z "$PGCONF" ]; then
   v_recovermode="unknown"
   v_str=$( psql -tc "select pg_is_in_recovery();" | tr -d [:space:] | tr [:upper:] [:lower:] )
   [ "$v_str" == "t" ] && v_recovermode="In_Recovery"
   [ "$v_str" == "f" ] && v_recovermode="Not_in_recovery"
fi

cat << __EOF__ | column -t
PGCONF "$PGCONF"
HBAFILE "$HBAFILE"
CLUSTER "$CLUSTER"
PGLOG "$PGLOG"
PGDATA "$PGDATA"
RecoverMode "$v_recovermode"
__EOF__

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

restart_cluster(){
local v_cversion=${1:-14}
local v_cname=${2:-"main"}
local v_delay=${3:-5}
local PG_HOST=${4:-"127.0.0.1"}
local PG_PORT=${5:-5432}
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

