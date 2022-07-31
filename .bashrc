PGCONF=$( psql -t -c "show config_file;" 2>/dev/null | tr -d [:cntrl:] | sed -r "s/^ +//" )
export PGCONF="$PGCONF"

HBAFILE=$( psql -t -c "show hba_file;" 2>/dev/null | tr -d [:cntrl:] | sed -r "s/^ +//" )
export HBAFILE="$HBAFILE"

CLUSTER=$( psql -c "show cluster_name" -t --csv )
CLUSTER_VERSION=$( echo -n "$CLUSTER" | cut -f 1 -d "/" )
CLUSTER_NAME=$( echo -n "$CLUSTER" | cut -f 2 -d "/" )
#PGLOG="/var/log/postgresql/postgresql-${CLUSTER_VERSION}-${CLUSTER_NAME}.log"
PGLOG=$( pg_lsclusters -h | awk -v cv="$CLUSTER_VERSION" -v cn="$CLUSTER_NAME" '{ if ( ( $1 == cv ) && ( $2 == cn ) ) {printf "%s", $7;} }' )
if [ ! -f "$PGLOG" ]; then
   echo "Can not find out log file of ${CLUSTER}"
   PGLOG=""
fi


cat << __EOF__ | column -t
PGCONF "$PGCONF"
HBAFILE "$HBAFILE"
CLUSTER "$CLUSTER"
PGLOG "$PGLOG"
__EOF__

if [ -f "$PGCONF" ]; then
   alias epconf='vim "$PGCONF"'
fi
if [ -f "$HBAFILE" ]; then
   alias ehbafile='vim "$HBAFILE"'
fi

if [ -f "$PGLOG" ]; then
   alias lesspglog='less "$PGLOG"'
fi
