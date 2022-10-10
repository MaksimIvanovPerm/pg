Подготовка вм в YC
В своём каталоге - создать днс-зону, для днс-записей внутренней подсети, которая будет использоваться для интерконнекта, между виртуалками:

![1](/HomeWorks/project/1.png)

Завести в днс-зоне записи, в моём примере - частная подсеть:
![2](/HomeWorks/project/2.png)

При заведении вм - указывать им ip-адреса из внутренней сети:
![3](/HomeWorks/project/3.png)

PTR-записи будут определены автоматически.

Заготовка для выполнения команд на нодах:
```shell
eval "$(ssh-agent -s)"
ssh-add ~/otus/yacloud

export RED='\033[0;31m'
export GREEN='\033[0;32m'
export BLANK='\033[0m'
export v_scpoption="-4 -q -o ServerAliveCountMax=5 -o ServerAliveInterval=15 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
export v_sshoption="-4 -o ServerAliveCountMax=5 -o ServerAliveInterval=15 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PasswordAuthentication=no -o LogLevel=ERROR"
export v_logonuser="student"

runit(){
if [ -z "$v_runuser" ]; then 
   v_runuser="$v_logonuser"
fi

for i in ${!v_hosts[@]}; do
    v_host=${v_hosts[$i]}
	echo "Processing $v_host"
    eval "scp "$v_scpoption" "$v_localfile" ${v_logonuser}@${v_host}:${v_targetfile}"
    v_rc="$?"
	if [ "$v_rc" -eq "0" ]; then
       if [ "$v_logonuser" != "$v_runuser" ]; then
          v_cmd="chmod a+x ${v_targetfile}; sudo -u ${v_runuser} ${v_targetfile}"
       else
          v_cmd="chmod u+x ${v_targetfile}; ${v_targetfile}"
       fi
       #run_remote_ssh "$v_host" "$v_cmd" "ECHO"
	   ssh ${v_sshoption} ${v_logonuser}@${v_host} "$v_cmd"
	else
	   echo "Can not copy ${v_localfile} to ${v_logonuser}@${v_host}:${v_targetfile}"
	fi
done
}


v_hosts=( 158.160.11.130 158.160.5.159 158.160.15.7 )
export v_localfile="/tmp/script.sh"
export v_targetfile="/tmp/script.sh"
export v_runuser="root"

cat << __EOF__ > "$v_localfile"
apt install net-tools etcd -y
apt autoremove -y
systemctl enable etcd
systemctl status etcd

adduser --system --quiet --home /var/lib/postgresql --no-create-home --shell /bin/bash --group --gecos "PostgreSQL administrator" postgres
usermod -u 5113 postgres
groupmod -g 5119 postgres
id postgres
__EOF__
runit

cat << __EOF__ > "$v_localfile"
sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
apt-get update
apt-get install postgresql -y
pg_lsclusters
pg_dropcluster --stop 14 main
__EOF__
runit

export v_runuser="postgres"
cat << __EOF__ > "$v_localfile"
whoami
etcd
__EOF__
runit
```

Далее от `postgres` ОС-аккаунта:
```shell
export ETCD_CONF="${HOME}/etcd.yml"
export ETCD_LOG="${HOME}/etcd_logfile"
export ETCDCTL_API=3

v_hosts=( "192.168.0.12" "192.168.0.11" "192.168.0.10" )
v_names=( "postgresql3" "postgresql2" "postgresql1" )
v_lclip=$( ifconfig eth0 | egrep -o "inet [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | cut -f 2 -d " " )

v_initialcluster=""
cat /dev/null > "$ETCD_CONF"
for i in ${!v_hosts[@]}; do
    v_host=${v_hosts[$i]}
    if [ "$v_lclip" == "$v_host" ]; then
       [ ! -d "$HOME/etcd/data" ] && mkdir -p "$HOME/etcd/data"
       chmod 700 "$HOME/etcd/data"
       [ ! -d "$HOME/etcd/wal" ] && mkdir -p "$HOME/etcd/wal"
       cat << __EOF__ > "$ETCD_CONF"
name: \"${v_names[$i]}\"
listen-peer-urls: \"http://${v_host}:2380\"
listen-client-urls: \"http://${v_host}:2379,http://127.0.0.1:2379\"
initial-advertise-peer-urls: \"http://${v_host}:2380\"
advertise-client-urls: \"http://${v_host}:2379\"
data-dir: '$HOME/etcd/data'
wal-dir: '$HOME/etcd/wal'

__EOF__
    fi
    if [ -z "$v_initialcluster" ]; then
       v_initialcluster="${v_names[$i]}=http://${v_host}:2380"
    else
       v_initialcluster="${v_initialcluster},${v_names[$i]}=http://${v_host}:2380"
    fi
done
echo "initial-cluster: \"$v_initialcluster\"" >> "$ETCD_CONF"
echo "initial-cluster-state: 'new'
initial-cluster-token: 'etcd-cluster-1'" >> "$ETCD_CONF"

echo "`whoami` ${ETCD_CONF}"
cat "$ETCD_CONF"
```

Выполнить на какой то ноде.
```
export ETCD_CONF="${HOME}/etcd.yml"
export ETCD_LOG="${HOME}/etcd_logfile"
export ETCDCTL_API=3
nohup etcd --config-file "$ETCD_CONF" > "$ETCD_LOG" 2>&1 &
```

При запуске процесса - выполнить эту же команду на остальных нодах.
Спросить про состояние кластера:
```shell
export ETCDCTL_API=2
etcdctl cluster-health
etcdctl member list
```

Удалить ноду:
```
etcdctl member remove fce50bcd610e3fb7
```

Добавить новую ноду.
Подойдёт тот же конфиг `$ETCD_CONF` который использовался во время запуска кластера.
Только нужно поправить: `initial-cluster-state: 'existing'`
Выполнить:
```
#at newly added node
#rm -rf $HOME/etcd/data/member; find $HOME/etcd -type f -delete
#somewhere in live part of cluster
export ETCDCTL_API=3
etcdctl member add postgresql3 --peer-urls='http://192.168.0.12:2380'
#	postgres@postgresql2:/home/student$ etcdctl member list
#	10be6d2d401032f8, started, postgresql2, http://192.168.0.11:2380, http://192.168.0.11:2379
#	5b2fd2dd548b9b93, unstarted, , http://192.168.0.12:2380,
#	7a0fb1a3031d4c79, started, postgresql1, http://192.168.0.10:2380, http://192.168.0.10:2379

#at new node
nohup etcd --config-file "$ETCD_CONF" > "$ETCD_LOG" 2>&1 &
```