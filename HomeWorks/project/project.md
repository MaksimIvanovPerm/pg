## Подготовка вм в YC

В своём каталоге - создать днс-зону, для днс-записей внутренней подсети, которая будет использоваться для интерконнекта, между виртуалками:

![1](/HomeWorks/project/1.png)

Завести в днс-зоне записи, в моём примере - частная подсеть:
![2](/HomeWorks/project/2.png)

При заведении вм - указывать им ip-адреса из внутренней сети:
![3](/HomeWorks/project/3.png)

PTR-записи будут определены автоматически.

Заготовка для выполнения команд на нодах.
И установка `postgresql`, etcd-ПО, сборка etcd-кластера совсем вручную.

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
local v_justcopy="$1"
local v_destfile="$2"

if [ -z "$v_runuser" ]; then 
   v_runuser="$v_logonuser"
fi

if [ -z "$v_destfile" ]; then
   v_destfile="$v_targetfile"
fi

for i in ${!v_hosts[@]}; do
    v_host=${v_hosts[$i]}
    echo "Copying ${v_localfile}->${v_logonuser}@${v_host}:${v_destfile}"
    eval "scp "$v_scpoption" "$v_localfile" ${v_logonuser}@${v_host}:${v_destfile}"
    v_rc="$?"
    if [ "$v_rc" -eq "0" ]; then
       if [ ! -z "$v_justcopy" ]; then
          echo "Just copy, successfully copyed"
          continue
       fi
       if [ "$v_logonuser" != "$v_runuser" ]; then
          v_cmd="chmod a+x ${v_destfile}; sudo -u ${v_runuser} ${v_destfile}"
       else
          v_cmd="chmod u+x ${v_destfile}; ${v_destfile}"
       fi
       #run_remote_ssh "$v_host" "$v_cmd" "ECHO"
       ssh ${v_sshoption} ${v_logonuser}@${v_host} "$v_cmd"
    else
       echo "Can not copy ${v_localfile} to ${v_logonuser}@${v_host}:${v_destfile}"
    fi
done
}



v_hosts=( 84.252.141.11 84.252.143.241 84.252.137.176 )
export v_localfile="/tmp/script.sh"
export v_targetfile="/tmp/script.sh"
export v_runuser="root"

cat << __EOF__ > "$v_localfile"
apt update; apt upgrade -y
apt install net-tools etcd unzip zip -y
apt autoremove -y
systemctl enable etcd
systemctl status etcd

adduser --system --quiet --home /var/lib/postgresql --shell /bin/bash --group --gecos "PostgreSQL administrator" postgres
usermod -u 5113 postgres
groupmod -g 5119 postgres
id postgres
__EOF__
runit

cat << __EOF__ > "$v_localfile"
sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
apt-get update; apt-get install postgresql -y
pg_lsclusters
pg_dropcluster --stop 15 main
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

v_hosts=( 130.193.52.202 158.160.11.58 158.160.14.248 )
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
export ETCDCTL_API=2; etcdctl cluster-health
export ETCDCTL_API=3; etcdctl member list -w table
export ETCDCTL_API=2; etcdctl member list
ENDPOINTS=$(etcdctl member list | grep -o "[^ ]\+:2379" | paste -s -d ",")
export ETCDCTL_API=3; etcdctl endpoint status --endpoints=$ENDPOINTS -w table
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

## Сборка etcd-кластера с использованием `systemd` и стандартным расположением кофнигурации, дата-директории.

[etcd-дока](https://etcd.io/docs/v3.5/)
Дефолтный конфиг расположен в `/etc/default/etcd`, это месторасположение угадывается из вывода `systemctl edit etcd.service --full`, по настройке `EnvironmentFile`;
[дока](https://etcd.io/docs/v3.5/op-guide/configuration/) по пар-рам конфигурации `etcd`.
Делаем такой файл, на первой ноде:
```shell
egrep "^[^#].*" /etc/default/etcd | sort -k 1 -t "="
ETCD_ADVERTISE_CLIENT_URLS="http://192.168.0.10:2379"
ETCD_DATA_DIR="/var/lib/etcd/default"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://192.168.0.10:2380"
ETCD_INITIAL_CLUSTER="postgresql3=http://192.168.0.12:2380,postgresql2=http://192.168.0.11:2380,postgresql1=http://192.168.0.10:2380"
ETCD_INITIAL_CLUSTER_STATE="new"
ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster-1"
ETCD_LISTEN_CLIENT_URLS="http://192.168.0.10:2379,http://127.0.0.1:2379"
ETCD_LISTEN_PEER_URLS="http://192.168.0.10:2380"
ETCD_NAME="postgresql1"
```

Папка `/var/lib/etcd/default` - уже есть и с правильными модами (700);
На остальных нодах - конфигурационный файл: будет такой же, с точностью до ip-адреса ноды и имени ноды и списка нод в `ETCD_INITIAL_CLUSTER`
Запуск службы: 
```shell
systemctl start etcd.service; systemctl status etcd.service
```
Смотреть логи сервиса оформленого с помощью systemd-службы придётся так: `journalctl -u etcd -f`
Поменять дефолтный редактор для systemctl-я можно так:
`export SYSTEMD_EDITOR="/usr/bin/vim"`

Если всё хорошо: задаём автозапуск etcd-службы: `systemctl enable etcd.service`
Готовим etcd-конфиг на следующей ноде, например - вторая нода, т.е.: `ETCD_NAME="postgresql2"`
На этой ноде, в т.ч., будет другое значение пар-ров:
```
ETCD_INITIAL_CLUSTER_STATE="existing"
ETCD_INITIAL_CLUSTER="postgresql2=http://192.168.0.11:2380,postgresql1=http://192.168.0.10:2380"
```
Анонсируем ноду в кластере, на стороне уже работающей в кластере ноды:

```
export ETCDCTL_API=2; etcdctl cluster-health
export ETCDCTL_API=3; etcdctl member add postgresql2 --peer-urls="http://192.168.0.11:2380"
export ETCDCTL_API=3; etcdctl member list -w table
```
На стороне вновь добавляемой ноды - контролировать, что в `ETCD_DATA_DIR` - нет образа бд, удалить, если есть.
Запускаем etcd-сервис на добавляемой ноде.
Контролируем статус ноды в кластере что вместо: `unstarted` стало: `started`;
Если всё хорошо: задаём автозапуск etcd-службы: `systemctl enable etcd.service`

Затем, таким же образом, добавляем третью ноду.
```
ETCD_INITIAL_CLUSTER_STATE="existing"
ETCD_INITIAL_CLUSTER="postgresql3=http://192.168.0.12:2380,postgresql2=http://192.168.0.11:2380,postgresql1=http://192.168.0.10:2380"
```
И так далее, сколько нужно нод.
В моём случае - три.

```shell
ENDPOINTS=$(export ETCDCTL_API=3; etcdctl member list | grep -o "[^ ]\+:2379" | paste -s -d ",")
export ETCDCTL_API=3; etcdctl --user=root:qaz endpoint status --endpoints=$ENDPOINTS -w table
export ETCDCTL_API=3; etcdctl --user=root:qaz endpoint health --endpoints=$ENDPOINTS -w table
+--------------------------+------------------+---------+---------+-----------+-----------+------------+
|         ENDPOINT         |        ID        | VERSION | DB SIZE | IS LEADER | RAFT TERM | RAFT INDEX |
+--------------------------+------------------+---------+---------+-----------+-----------+------------+
| http://192.168.0.10:2379 | 7a0fb1a3031d4c79 |  3.3.25 |   20 kB |      true |       136 |         12 |
| http://192.168.0.11:2379 | 863e81c7efce4cd9 |  3.3.25 |   16 kB |     false |       136 |         12 |
| http://192.168.0.12:2379 | fcad0adfab6c7da4 |  3.3.25 |   20 kB |     false |       136 |         12 |
+--------------------------+------------------+---------+---------+-----------+-----------+------------+
+--------------------------+--------+-------------+-------+
|         ENDPOINT         | HEALTH |    TOOK     | ERROR |
+--------------------------+--------+-------------+-------+
| http://192.168.0.11:2379 |   true | 11.054524ms |       |
| http://192.168.0.10:2379 |   true | 10.907459ms |       |
| http://192.168.0.12:2379 |   true | 26.894254ms |       |
+--------------------------+--------+-------------+-------+
```

После добавления всех нод в кластер:  привести конфигурацию нод к одному состоянию: всем нодам задать одинаковый список в `ETCD_INITIAL_CLUSTER` 
И выставить значение `ETCD_INITIAL_CLUSTER_STATE="existing"`

Если необходимо сменить лидера, выполнить, на текущем лидере:
```shell
export ETCDCTL_API=2; etcdctl member list
7a0fb1a3031d4c79: name=postgresql1 peerURLs=http://192.168.0.10:2380 clientURLs=http://192.168.0.10:2379 isLeader=false
863e81c7efce4cd9: name=postgresql2 peerURLs=http://192.168.0.11:2380 clientURLs=http://192.168.0.11:2379 isLeader=true
fcad0adfab6c7da4: name=postgresql3 peerURLs=http://192.168.0.12:2380 clientURLs=http://192.168.0.12:2379 isLeader=false
export ETCDCTL_API=3; etcdctl --user=root:qqq1 move-leader 7a0fb1a3031d4c79
Leadership transferred from 863e81c7efce4cd9 to 7a0fb1a3031d4c79
export ETCDCTL_API=2; etcdctl member list
7a0fb1a3031d4c79: name=postgresql1 peerURLs=http://192.168.0.10:2380 clientURLs=http://192.168.0.10:2379 isLeader=true
863e81c7efce4cd9: name=postgresql2 peerURLs=http://192.168.0.11:2380 clientURLs=http://192.168.0.11:2379 isLeader=false
fcad0adfab6c7da4: name=postgresql3 peerURLs=http://192.168.0.12:2380 clientURLs=http://192.168.0.12:2379 isLeader=false
```

### Включаем авторизованный доступ в etcd, пример работы с ключами

[Authentication Guide](https://etcd.io/docs/v3.5/op-guide/authentication/)

[Interaction guide](https://etcd.io/docs/v3.5/dev-guide/interacting_v3/)

```shell
export ETCDCTL_API=3
etcdctl user add root
# type password, whet it will ask about it

etcdctl --user=root:qqq1  auth enable
etcdctl --user=root:qqq1 user get root --detail=true
etcdctl --user=root:qqq1 role list
# shows role "guest"

#etcdctl --user=root:qqq1 role delete role1
etcdctl --user=root:qqq1 role add role1
etcdctl --user=root:qqq1 role grant-permission --prefix=true role1 readwrite /keys1
etcdctl --user=root:qqq1 role get role1
#Role: role1
#KV Read:
#        /keys1/*
#KV Write:
#        /keys1/*

#etcdctl --user=root:qqq1 user del user1
etcdctl --user=root:qqq1 user add user1:qqq1
etcdctl --user=root:qqq1 user grant-role user1 role1
etcdctl --user=root:qqq1 user get user1 --detail=true

etcdctl --user=user1:qqq1 put /keys1/key1 value1
#OK
etcdctl --user=user1:qqq1 get /keys1/key1
#/keys1/key1
#value1

etcdctl --user=root:qaz del --prefix /service/
etcdctl --user=root:qaz get --prefix /service/
```

## Сборка патрони-менеджмент кластера.
[Программная, очень подробная, статья от 1С](https://its.1c.ru/db/metod8dev/content/5971/hdoc)
[Про systemd-оснастку](https://timeweb.cloud/blog/kak-ispolzovat-systemctl-dlya-upravleniya-sluzhbami-systemd)

Установка необходимого ПО:
```shell
cat << __EOF__ > "$v_localfile"
python3 --version
id postgres
__EOF__
runit

cat << __EOF__ > "$v_localfile"
apt install -y python3-pip python3-dev gcc
python3 -m pip install psycopg2-binary
python3 -m pip install patroni[etcd]
patroni --version
__EOF__
runit

cat << __EOF__ > "$v_localfile"
[ ! -d "/etc/patroni" ] && mkdir /etc/patroni
chown postgres:postgres /etc/patroni
chmod 700 /etc/patroni
ls -lthr /etc | grep "patroni"
if [ ! -d "/var/lib/postgresql" ]; then
   mkdir /var/lib/postgresql
   chown -R postgres:postgres /var/lib/postgresql
   chmod 750 /var/lib/postgresql
else
   ls -lthr /var/lib/ | grep "postgres"
fi
__EOF__
runit
```

Выложить на сервер файлы.
```shell
cat << __EOF__ > "$v_localfile"
cd
[ -d "./pg" ] && rm -rf ./pg; wget -O 1.zip https://github.com/MaksimIvanovPerm/pg/archive/refs/heads/main.zip; unzip -q 1.zip -d ./pg; rm -f ./1.zip
v_dir="/etc/systemd/system"
v_file="\${v_dir}/patroni.service"
cp -v ./pg/pg-main/HomeWorks/project/files/patroni.service "\$v_dir"
chmod 644 "\$v_file"

v_dir=\$( getent passwd "postgres" | cut -f 6 -d ":" )
v_file="\${v_dir}/post_init.sh"
cp -v ./pg/pg-main/HomeWorks/project/files/post_init.sh "\$v_dir"
chown postgres:postgres "\$v_file"; chmod u+x "\$v_file"

v_file="\${v_dir}/.pgtab"
if [ ! -f "\$v_file" ]; then
   cp -v ./pg/pg-main/HomeWorks/project/files/.pgtab "\$v_dir"
   chown postgres:postgres "\$v_file"; chmod 664 "\$v_file"
fi

v_file="\${v_dir}/.vimrc"
if [ ! -f "\$v_file" ]; then
   cp -v ./pg/pg-main/HomeWorks/project/files/.vimrc "\$v_dir"
   chown postgres:postgres "\$v_file"; chmod 664 "\$v_file"
fi

v_file="\${v_dir}/.bashrc"
cp -v ./pg/pg-main/HomeWorks/project/files/.bashrc "\$v_dir"
chown postgres:postgres "\$v_file"; chmod 664 "\$v_file"

v_file="\${v_dir}/callback.sh"
cp -v ./pg/pg-main/HomeWorks/project/files/callback.sh "\$v_dir"
chown postgres:postgres "\$v_file"; chmod u+x "\$v_file"

v_dir="/etc/patroni"
v_file="\${v_dir}/patroni.yml"
cp -v ./pg/pg-main/HomeWorks/project/files/patroni.yml "\$v_dir"
chown postgres:postgres "\$v_file"
chmod 644 "\$v_file"
v_hostname=\$(hostname -s)
v_ip=\$( ifconfig eth0 | grep "inet " | awk '{printf "%s", \$2;}' )
#sed -i -r "s/^name: .*/name: \$v_hostname/" "/etc/patroni/patroni.yml"; egrep "^name: " /etc/patroni/patroni.yml
sed -i -r "s/postgresql1/\$v_hostname/g" "/etc/patroni/patroni.yml"
sed -i -r "s/192.168.0.10/\$v_ip/g" "/etc/patroni/patroni.yml"
#sed -i -r "s/connect_address: .*/connect_address: \${v_ip}:8080/g" /etc/patroni/patroni.yml; egrep "connect_address: " /etc/patroni/patroni.yml
__EOF__
runit
```

1. Шелл-скрипт `post_init.sh` как `/var/lib/postgresql/post_init.sh`
   Образ скрипта: [post_init.sh](/HomeWorks/project/files/post_init.sh)
   Скрипт будет использоваться в `post_init` параметре патрони-конфига, и будет вести файл [$HOME/.pgtab](/HomeWorks/project/files/.pgtab), в домашней дир-рии ОС-аккаунта `postgres`;
   В файле `$HOME/.pgtab` - будут сохраняться данные до заплоенной, ч/з патрони, пг-базе, на данной машине.
   Соотв-но: файл `$HOME/.pgtab` будет использоваться для инициализации env-а, для более комфортной работы с данной бд из CLI;
   Инициализация env-а - по шелл-функции `set_pgcluster` в [.bashrc](/HomeWorks/project/files/.bashrc)
   
   P.S.: поправка: позже понял что это всё - бред, не правильное понимание назначения пар-ра `post_init`;
   То, о чём я, в этом пункте пишу: делается с помощью callback-секции в yaml-конфиге патрони.
   См. файлы:
   [callback.sh](/HomeWorks/project/files/callback.sh)
   [patroni.yml](/HomeWorks/project/files/patroni.yml)
2. Скрипт [patroni.yml](/HomeWorks/project/files/patroni.yml) выкладывается как `/etc/patroni/patroni.yml`
   [Дока по пар-рам yaml-конфига](https://patroni.readthedocs.io/en/latest/SETTINGS.html)
3. Скрипт [patroni.service](/HomeWorks/project/files/patroni.service) - для оформления патриони-демона как системного сервиса.
   Выкладывается в `/etc/systemd/system/patroni.service`
   Свойство Restart - может принимать значения: no, on-success, on-failure, on-abnormal, on-watchdog, on-abort, или always. 
   Определяет политику перезапуска сервиса в случае, если он завершает работу не по команде от systemd.
   Решил не рестартить патрони-сервис вообще, если он, сам умер, или его убили по kill-команде, не пользуясь systemd-службой.

Замечания по пар-рам патрони, в его конфиге.
1. Пар-р `pgpass` - это оказывается файл который патрони ведёт именно сам и именно под свои нужды.
   Ведёт обозначает что - буквально: ведёт, сам добавляет/удаляет записи при бутстрапе ноды.
   Если файл уже был и в нём были записи - всё перетрёт своими записями.
2. Пар-ры `post_init, post_bootstrap`; `post_init` - отрабатывает как часы, после каждого инита.
   `post_bootstrap` - не работает.
   
   P.S.: опять же - со временем понял что: и не должно работать так как я ожидал, в то время когда набирал эти строки.
   Эти параметры: срабатывают во время первой инициализации мастер-бд, во время создания патрони-менеджмент кластера.
   И нужны если это создание - надо переопределить на что то своё, например - патрони-менеджмент кластер поднимается как тестовый кластер, от уже существующей продовой мастер-бд и из её бэкапов.
   А то что я хотел тут, когда, впервые, набирал этот пункт, делается вызовами которые определяются в секции `callback` yml-файла патрони.

Запуск/остановка патрони-демона, если ч/з systemd-оснастку:
```shell
# sudo systemctl daemon-reload после добавления unit-скрипта.
systemctl start patroni.service
systemctl status patroni.service
systemctl enable patroni.service
systemctl stop patroni.service
```
```
root@postgresql1:~# sudo systemctl daemon-reload
root@postgresql1:~# sudo systemctl start patroni.service
root@postgresql1:~# sudo systemctl status patroni.service
● patroni.service - Runners to orchestrate a high-availability PostgreSQL
     Loaded: loaded (/etc/systemd/system/patroni.service; disabled; vendor preset: enabled)
     Active: active (running) since Sun 2022-10-16 12:42:54 UTC; 6s ago
   Main PID: 2563 (patroni)
      Tasks: 14 (limit: 2236)
     Memory: 66.6M
        CPU: 502ms
     CGroup: /system.slice/patroni.service
             ├─2563 /usr/bin/python3 /usr/local/bin/patroni /etc/patroni/patroni.yml
             ├─2575 /usr/lib/postgresql/15/bin/postgres -D /var/lib/postgresql/15/main --config-file=/var/lib/postgresql/15/main/p>
             ├─2577 "postgres: postgres: logger " "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "">
             ├─2578 "postgres: postgres: checkpointer " "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "">
             ├─2579 "postgres: postgres: background writer " "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" >
             ├─2585 "postgres: postgres: postgres postgres 127.0.0.1(47116) idle" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" >
             ├─2590 "postgres: postgres: walwriter " "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "">
             ├─2591 "postgres: postgres: autovacuum launcher " "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" ">
             └─2592 "postgres: postgres: logical replication launcher " "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" ">

Oct 16 12:42:56 postgresql1 patroni[2581]: localhost:5432 - accepting connections
Oct 16 12:42:56 postgresql1 patroni[2583]: localhost:5432 - accepting connections
Oct 16 12:42:56 postgresql1 patroni[2563]: 2022-10-16 12:42:56,174 INFO: establishing a new patroni connection to the postgres clu>
Oct 16 12:42:56 postgresql1 patroni[2563]: 2022-10-16 12:42:56,229 WARNING: Could not activate Linux watchdog device: "Can't open >
Oct 16 12:42:56 postgresql1 patroni[2563]: 2022-10-16 12:42:56,280 INFO: promoted self to leader by acquiring session lock
Oct 16 12:42:56 postgresql1 patroni[2588]: server promoting
Oct 16 12:42:56 postgresql1 patroni[2563]: 2022-10-16 12:42:56,283 INFO: cleared rewind state after becoming the leader
Oct 16 12:42:56 postgresql1 patroni[2563]: 2022-10-16 12:42:56,281 INFO: Lock owner: postgresql1; I am postgresql1
Oct 16 12:42:56 postgresql1 patroni[2563]: 2022-10-16 12:42:56,431 INFO: updated leader lock during promote
Oct 16 12:42:57 postgresql1 patroni[2563]: 2022-10-16 12:42:57,433 INFO: no action. I am (postgresql1), the leader with the lock
```

Смотреть лог работы сервиса: `journalctl -u patroni -f`
Запуск/остановка патрони-сервиса, если всё вручную:
```shell
sudo postgres
/usr/local/bin/patroni --validate-config /etc/patroni/patroni.yml; echo "$?"
/usr/local/bin/patroni /etc/patroni/patroni.yml > /tmp/patroni_member_1.log 2>&1 &
kill -s HUP $MAINPID # == patronictl reload
kill -s INT $MAINPID # остановка патрони-демона + инстанса пг. по kill -9 - не сможет оттрапить и сделать остановку бд
/usr/local/bin/patronictl -c /etc/patroni/patroni.yml list
```

В процессах можно будет увидеть что то вроде такого:
```
postgres    7519  0.0  1.4 218972 29660 ?        S    19:42   0:00 /usr/lib/postgresql/15/bin/postgres -D /var/lib/postgresql/15/main --config-file=/var/lib/postgresql/15/main/postgresql.conf --listen_addresses=0.0.0.0 --port=5432 --cluster_name=postgres --wal_level=replica --hot_standby=on --max_connections=100 --max_wal_senders=10 --max_prepared_transactions=0 --max_locks_per_transaction=64 --track_commit_timestamp=off --max_replication_slots=10 --max_worker_processes=8 --wal_log_hints=on
```

Поспрашивать состояние пг-базы можно так, если напрямую и не занимаясь настройкой env-а под более комофртную работу с патрони-менеджмент бд:
```shell
pg_ctl status -D /var/lib/postgresql/15/main -m i
pg_ctl stop -D /var/lib/postgresql/15/main -m i
```

### Как удалить патрини-менеджмент кластер пг-баз

```shell
echo -ne "postgres\nYes I am aware\n" | patronictl -c /etc/patroni/patroni.yml remove postgres
#+ удалить датадир.
rm -rf $PGATA
```

### Добавление ноды в патрони-кластер.

Ровно таким же образом: готовится такой же yml-файл с конфигурацией, именно для этой ноды.
Т.е., проще всего - взять yaml-конфиг c ноды и с кластера которая - уже в патрони-менеджменте, откопировать его на вновь добавляему ноду и там поправить, под местные реалии.
yml-файл выкладывается на ноду.
Возможно - прописывается systemctl-юнит.
Делается запуск патрони-сервиса, на новой ноде.
При этом патрони автоматически выполняет бутстрап пг-кластера, на данной ноде, используя утилиту `pg_basebackup` для снятия образа с текущего мастера.
Отдельный вопрос - насколько именно такое, дефолтное поведение бустрапа: приемлемо.
Можно переопределить бустраппинг, своим шелл-скриптом (`bootstrap:` `method`), который будет выкладывать образ реплики из уже существующего бэкапа.

### Как добавляем в патрони уже существующую стандалон-бд

[Статья от ibm](https://www.ibm.com/docs/en/cabi/1.1.5?topic=cluster-migrating-stand-alone-postgresql-instance-node)

[Официальная дока про такой вариант создания патрони-менеджмент кластера](https://patroni.readthedocs.io/en/latest/existing_data.html)

Дополнительно, для случая использования `pg_rewind` (это дефолтный мех-м получения реплики из бывшего мастера, при свичовере), патрони создаёт бд-учётку `rewind_user`
Про неё [сказано](https://patroni.readthedocs.io/en/latest/SETTINGS.html) что права/роли у неё д.б. [такие](https://www.postgresql.org/docs/15/app-pgrewind.html#id-1.9.5.8.8):
```sql
CREATE USER rewind_user LOGIN;
GRANT EXECUTE ON function pg_catalog.pg_ls_dir(text, boolean, boolean) TO rewind_user;
GRANT EXECUTE ON function pg_catalog.pg_stat_file(text, boolean) TO rewind_user;
GRANT EXECUTE ON function pg_catalog.pg_read_binary_file(text) TO rewind_user;
GRANT EXECUTE ON function pg_catalog.pg_read_binary_file(text, bigint, bigint, boolean) TO rewind_user;
```

План-программа добавления стандалон-бд, в патрони-менеджмент выглядит так.
1. Готовим стандалон-бд:
   ```shell
   mkdir -p /var/lib/postgresql/15/standalondb/
   #pg_dropcluster --stop 15 standalondb
   v_dir=$( getent passwd "postgres" | cut -f 6 -d ":" )
   echo "qaz1" > $v_dir/password.txt; chown postgres:postgres $v_dir/password.txt
   pg_createcluster --datadir=/var/lib/postgresql/15/standalondb --port=5433 --logfile=/var/lib/postgresql/15/standalondb/log.txt --start --start-conf=auto 15 standalondb -- --pwfile=$v_dir/password.txt --username=postgres
   ```
3. Готовится yml-конфигурационный файл, учитывающий расположение и конфигурацию этой стандалон-бд.
   Например: [standalonedb.yml](/HomeWorks/project/files/standalonedb.yml)
   В файле уточняются специфичные именно для этой стандалон бд атрибуты: дата-директория, бинари-директория, конфигураиця пг-кластера, порт который прослушивает патрони и т.п.
   Особо обратить внимание на пар-р: `config_dir`, где патрони ищет конфигурацию для сопровождаемой пг-базы.
   И что он применяет из конфигурации пг-базы, а что - из своего yaml-конфига описано [Patroni configuration](https://patroni.readthedocs.io/en/latest/dynamic_configuration.html)
   Кратко: патрони, при инициации ноды копирует нативный `postgresql.conf` в `postgresql.base.conf`, в ту же жиректорию.
   А нативный `postgresql.conf` правит, оставляя в нём только явно заданные параметры и директиву:
   ```
   # Do not edit this file manually!
   # It will be overwritten by Patroni!
   include 'postgresql.base.conf'
   ```
   ```shell
   egrep -o "^[^#][^#]+" /etc/postgresql/15/standalondb/postgresql.conf | sed -r "/^\W+$/d" | sort -k 1 -t "="
   ```
   Так же выверяем что параметры необходимые для работы реплик - прописаны в конфигурации бд (или хотя бы будут в работе, начиная с момента жизни этой бд под патрони-менеджментом)
4. Создать (если ещё не создано) пользователей, и програнтовать (если ещё не програнтовано) в стандалон-бд такие учётки:
   ```sql
   CREATE USER postgres WITH SUPERUSER ENCRYPTED PASSWORD 'qaz1';
   CREATE USER replicator WITH REPLICATION ENCRYPTED PASSWORD 'qaz2';
   CREATE USER rewind_user LOGIN;
   alter user rewind_user ENCRYPTED PASSWORD 'qaz3';
   GRANT EXECUTE ON function pg_catalog.pg_ls_dir(text, boolean, boolean) TO rewind_user;
   GRANT EXECUTE ON function pg_catalog.pg_stat_file(text, boolean) TO rewind_user;
   GRANT EXECUTE ON function pg_catalog.pg_read_binary_file(text) TO rewind_user;
   GRANT EXECUTE ON function pg_catalog.pg_read_binary_file(text, bigint, bigint, boolean) TO rewind_user;
   ```
   Контролировать, что эти логопассы - прописаны в `authentication` в `postgresql` yml-файла;
5. Остановить стандалон-бд: `pg_ctlcluster stop 15 standalondb` 
   Остановка нужна для того чтобы порт пг-кластера не был занят, порт - д.б. прописан в yaml-конфиге.
   Стандалон-бд, если была под управлением systemctl, или какого то другого оркестратора ОС-сервисов: надо вывести из под этого оркестратора.
   С момента добавления в патрони: бд будет управляться патрони.
   Проверить корректность yaml-конфига, попробовать запустить патрони-сервис
   ```shell
   /usr/local/bin/patroni --validate-config /etc/patroni/standalonedb.yml; echo "$?"
   pg_ctlcluster start 15 standalondb
   /usr/local/bin/patroni /etc/patroni/standalonedb.yml > /tmp/standalonedb_node1.log 2>&1 &
   ```

```shell
   3132 pts/5    S+     0:00  |                   |   \_ sudo su postgres
   3133 pts/6    Ss     0:00  |                   |       \_ sudo su postgres
   3134 pts/6    S      0:00  |                   |           \_ su postgres
   3135 pts/6    S+     0:00  |                   |               \_ bash
   6670 pts/6    Sl     0:01  |                   |                   \_ /usr/bin/python3 /usr/local/bin/patroni /etc/patroni/stand
   5957 pts/7    Ss     0:00  |                   \_ /bin/bash
   6709 ?        S      0:00 /usr/lib/postgresql/15/bin/postgres -D /var/lib/postgresql/15/standalondb --config-file=/etc/postgresql/15/standalondb/postgresql.conf --listen_addresses=0.0.0.0 --port=5433 --cluster_name=standalondb --wal_level=replica --hot_standby=on --max_connections=100 --max_wal_senders=10 --max_prepared_transactions=0 --max_locks_per_transaction=64 --track_commit_timestamp=off --max_replication_slots=10 --max_worker_processes=8 --wal_log_hints=on
postgres@postgresql1:~$ patronictl list -e
+--------+-------------------+--------+---------+----+-----------+-----------------+-------------------+------+
| Member | Host              | Role   | State   | TL | Lag in MB | Pending restart | Scheduled restart | Tags |
+ Cluster: standalondb (7157344067292274707) ---+----+-----------+-----------------+-------------------+------+
| node1  | 192.168.0.10:5433 | Leader | running |  4 |           |                 |                   |      |
+--------+-------------------+--------+---------+----+-----------+-----------------+-------------------+------+
postgres@postgresql1:~$ patronictl restart --force --scheduled now standalondb node1
+--------+-------------------+--------+---------+----+-----------+
| Member | Host              | Role   | State   | TL | Lag in MB |
+ Cluster: standalondb (7157344067292274707) ---+----+-----------+
| node1  | 192.168.0.10:5433 | Leader | running |  4 |           |
+--------+-------------------+--------+---------+----+-----------+
Success: restart on member node1
postgres@postgresql1:~$
```

Продолжая пример: добавим теперь, к этой ноде с лидером, ноду с репликой.

И пусть, на вновь добавляемой ноде-реплике, мы не хотим получать реплику от лидера дефолтным образом.
Т.е., по умолчанию, патрони будет, с пом-ю `pg_basebackup`, подкючаться, со стороны новой ноды к ноде с лидером и тянуть с неё образ бд на вновь добавляему ноду.
Что, конечно, не здорово, в общем случае.
Потому как - мастер-пг может быть большой бд, нагруженной бд и вот её ещё грузить отдачей всего её образа на сторону новой реплики.
Можно переопределить этот процесс, если есть какой то вариант получить реплику не нагружая мастера, например - уже есть актуальные бэкапы мастера.
Или если реплика - уже есть, в виде вручную подготовленного standby;

Статьи на это есть, с примерами, как именно это делается, например [Patroni and pgBackRest combined](https://pgstef.github.io/2022/07/12/patroni_and_pgbackrest_combined.html).
Суть в том что патрони, для кастомизации процесса лепления реплики, позволяет определить свои методы в пар-ре `postgresql.create_replica_methods` своего yml-файла.
Подрбнее тут: [Building replicas](https://patroni.readthedocs.io/en/latest/replica_bootstrap.html#building-replicas)
Так же можно переопределить бутстрапинг, это параметр `bootstrap.method`;
[Хорошая статья](https://community.pivotal.io/s/article/How-to-Use-pgbackrest-to-bootstrap-or-add-replica-to-HA-Patroni?language=en_US) поясняющая разницу между кастомным мтодом бутстрапинга и кстомным методом лепления реплики.

Два слова по методам в `postgresql.create_replica_methods`
Патрони тут тоже продуман и, для дефолтного метода получения реплик, можно кастомизировать опции вызова `pg_basebackup`:
```
postgresql:
    basebackup:
        - verbose
        - max-rate: '100M'
        - waldir: /pg-wal-mount/external-waldir
```
Но особый цимес в том что в этих параметрах, для `basebackup` метода можно указать опицю `clonefrom`;
Тогда `pg_basebackup` будет тянуть образ не с мастер-пг.
А с какой то уже существующей реплики (ноды) у которой в tag-ах, в её (ноды) yaml-конфиге патрони сказано что: `clonefrom: true`
Причём патрони ещё проверит - а эта реплика, она реально подходит для этой процедуры, по своему состоянию.
И если нет и/или если таких реплик (с clonefrom-тэгом) несколько - выберет более подходящую реплику, будет с неё тянуть образ.
В 15-й версии `pg_basebackup` поддерживает компрессию, при передаче данных по сети, из ман-а на утилиту:
```
-Z level
-Z [{client|server}-]method[:detail]
--compress=level
--compress=[{client|server}-]method[:detail]
    Requests compression of the backup. If client or server is included, it specifies where the compression is to be
    performed. Compressing on the server will reduce transfer bandwidth but will increase server CPU consumption. The
    default is client except when --target is used. In that case, the backup is not being sent to the client, so only
    server compression is sensible. When -Xstream, which is the default, is used, server-side compression will not be
    applied to the WAL. To compress the WAL, use client-side compression, or specify -Xfetch.
```

У меня не особо много времени изучать специализированные средства бэкапирования постгреса.
Поэтому я сэмулирую, использование специализирванного средства, в своём шелл-скрипта, который я впишу в `bootstrap.method`, в виде использования, в нём, всё того же `pg_basebackup`
Пример секции `postgresql.create_replica_methods` в моём случае (см. файл: [standalonedb.yml](/HomeWorks/project/files/standalonedb.yml)):
```
  create_replica_methods:
    - pgbackrest
    - basebackup
  pgbackrest:
    command: /var/lib/postgresql/create_replica.sh --scope --datadir --connstring
    keep_data: True
    #no_params: True
  basebackup:
    checkpoint: 'fast'
    verbose:
    progress:
    compress: 'server-gzip:1'
```

Патрони обрабатывает методы лепления реплики сверху вниз, в списке который указан непосредственно узле `create_replica_methods`
Если метод выдал нулевой статус завершения - считается что он отработал успешно и нижеследующие методы: не будут выполняться патрони.
В противном случае: патрони будет пробовать выполнить следующий, по списку, метод.
Этим обстоятельством можно воспользоваться для того чтобы выполнить какой то свой, кастомный скрипт.
Который - ничего делать не будет с физ-компонентой бд-реплики (у нас она - уже есть, по легенде).
См. скрипт: [standalonedb.yml](/HomeWorks/project/files/standalonedb.yml)

```shell
#Процедура получения бэкапа, на стороне вновь добавляемой ноды:
v_backupdir="/mnt/sharedstorage/backup"
[ -d "$v_backupdir" ] && rm -rf "$v_backupdir"; mkdir -p "$v_backupdir"
pg_basebackup -D "$v_backupdir" -F t --wal-method=stream -c fast -l "backup1" -P -v 
```
```shell
#Выкладка бэкапа на стороне новой реплики
v_datadir="/var/lib/postgresql/15/standalondb"
#[ ! -d "$v_datadir" ] && mkdir -p "$v_datadir"; chmod 700 "$v_datadir"
cd "$v_datadir"
find ./ -not -name . -delete 2>/dev/null 
cp -v /mnt/sharedstorage/backup/* ./
tar -xf ./base.tar; rm -f ./base.tar
mv -v ./pg_wal.tar ./pg_wal; cd ./pg_wal; tar -xf ./pg_wal.tar; rm -f ./pg_wal.tar
```

Проконтролировать наличие `data_dir, bin_dir, config_dir` на стороне вновь создаваемой реплики.
Проложить `postgresql.base.conf`, со стороны ноды с лидером, на сторону реплики, как `postgresql.conf` (в папку которая, в патрони-терминах: `config_dir`).
Создать на стороне реплики, в `config_dir` ,подпапку `conf.d` для наварки `postgresql.base.conf`

```shell
find /etc/postgresql/15/standalondb/ -type f -name 'postgresql.*' -delete
cp -v /etc/postgresql/15/standalondb/postgresql.base.conf /mnt/sharedstorage/
mv -v /mnt/sharedstorage/postgresql.base.conf /etc/postgresql/15/standalondb/postgresql.conf
```

Т.о., на этот момент времени, на стороне добавляемой в кластер ноды: уже есть копия бд со стороны лидера.
Она (копия) была выложена из бэкапов.
Копия могла быть получена и как standby-база, ну, тогда опять же - это тоже копия.
Пытаемся запустить, на стороне добавляемой реплики, патрони-демона:
```shell
/usr/local/bin/patroni --validate-config /etc/patroni/standalonedb.yml; echo "$?"
/usr/local/bin/patroni /etc/patroni/standalonedb.yml > /tmp/patroni.log 2>&1 &
kill -s HUP $MAINPID # == patronictl reload
kill -s INT $MAINPID # остановка патрони-демона + инстанса пг. по kill -9 - не сможет оттрапить и сделать остановку бд
```

Как это всё выглядит.
На стороне ноды с лидером:
```shell
postgres@postgresql1:~$ export PATRONICTL_CONFIG_FILE=/etc/patroni/standalonedb.yml
postgres@postgresql1:~$ patronictl list
+--------+------+------+-------+----+-----------+
| Member | Host | Role | State | TL | Lag in MB |
+ Cluster: standalondb (7157344067292274707) ---+
+--------+------+------+-------+----+-----------+
postgres@postgresql1:~$ /usr/local/bin/patroni --validate-config /etc/patroni/standalonedb.yml; echo "$?"
postgresql.listen 0.0.0.0:5433 didn't pass validation: 'Port 5433 is already in use.'
0
postgres@postgresql1:~$ /usr/local/bin/patroni /etc/patroni/standalonedb.yml > /tmp/patroni.log 2>&1 &
[1] 1420
postgres@postgresql1:~$ patronictl list
+--------+-------------------+--------+---------+----+-----------+
| Member | Host              | Role   | State   | TL | Lag in MB |
+ Cluster: standalondb (7157344067292274707) ---+----+-----------+
| node1  | 192.168.0.10:5433 | Leader | running |  4 |           |
+--------+-------------------+--------+---------+----+-----------+
postgres@postgresql1:~$
```

На стороне вновь добавляемой, как реплики, ноды - выполняем процедуру получения физ-компоненты бд, с лидера, в дата-директорию.
Изображая, таким образом, что - копия у нас уже, каким то образом, есть, на вновь добавляемой ноде.
И выполняем:
```shell
postgres@postgresql2:~$ /usr/local/bin/patroni --validate-config /etc/patroni/standalonedb.yml; echo "$?"
0
postgres@postgresql2:~$ /usr/local/bin/patroni /etc/patroni/standalonedb.yml > /tmp/patroni.log 2>&1 &
[1] 1588
```
В `/tmp/patroni.log` оно пишет:
```
2022-10-23 14:55:40,152 INFO: Trying to authenticate on Etcd...
2022-10-23 14:55:40,289 INFO: No PostgreSQL configuration items changed, nothing to reload.
2022-10-23 14:55:40,339 WARNING: Postgresql is not running.
2022-10-23 14:55:40,339 INFO: Lock owner: node1; I am node2
2022-10-23 14:55:40,340 INFO: pg_controldata:
  pg_control version number: 1300
  Catalog version number: 202209061
  Database system identifier: 7157344067292274707
  Database cluster state: in production
  pg_control last modified: Sun Oct 23 14:54:35 2022
  Latest checkpoint location: 0/19000060
  Latest checkpoint's REDO location: 0/19000028
...
  Data page checksum version: 0
  Mock authentication nonce: 6739653add17f62350a8daeec4a94ef853f59b8a11f9c989b5dd4c00d9910974

2022-10-23 14:55:40,341 INFO: Lock owner: node1; I am node2
2022-10-23 14:55:40,341 INFO: starting as a secondary
2022-10-23 14:55:40,492 INFO: postmaster pid=1600
localhost:5433 - no response
2022-10-23 14:55:40.503 UTC [1600] LOG:  redirecting log output to logging collector process
2022-10-23 14:55:40.503 UTC [1600] HINT:  Future log output will appear in directory "log".
localhost:5433 - accepting connections
localhost:5433 - accepting connections
2022-10-23 14:55:41,546 INFO: Lock owner: node1; I am node2
2022-10-23 14:55:41,547 INFO: establishing a new patroni connection to the postgres cluster
2022-10-23 14:55:41,694 INFO: no action. I am (node2), a secondary, and following a leader (node1)
```

И можно спросить про состояние патрони-кластера:
```shell
postgres@postgresql2:~$ hostname -f; date
postgresql2.ru-central1.internal
Sun Oct 23 03:00:07 PM UTC 2022
postgres@postgresql2:~$ export PATRONICTL_CONFIG_FILE=/etc/patroni/standalonedb.yml
postgres@postgresql2:~$ patronictl topology
+---------+-------------------+---------+---------+----+-----------+
| Member  | Host              | Role    | State   | TL | Lag in MB |
+ Cluster: standalondb (7157344067292274707) -----+----+-----------+
| node1   | 192.168.0.10:5433 | Leader  | running |  4 |           |
| + node2 | 192.168.0.11:5433 | Replica | running |  4 |         0 |
+---------+-------------------+---------+---------+----+-----------+
```

Из любопытства и чтобы показать как патрони перебирает, заданные ему, методы лепления реплики, вписал в `/var/lib/postgresql/create_replica.sh` - `exit 1`
Остановил патрони-процесс, на стороне ноды-реплики `node2`, удалил её физ-компоненту пг-реплики, снова запустил патрони-процесс.
Лог `/tmp/patroni.log`:
```
2022-10-23 16:40:08,212 INFO: Trying to authenticate on Etcd...
2022-10-23 16:40:08,349 INFO: No PostgreSQL configuration items changed, nothing to reload.
2022-10-23 16:40:08,398 INFO: Lock owner: node1; I am node2
2022-10-23 16:40:08,446 INFO: trying to bootstrap from leader 'node1'
2022-10-23 16:40:08,450 ERROR: Error creating replica using method pgbackrest: /var/lib/postgresql/create_replica.sh --scope --datadir --connstring exited with code=1
2022-10-23 16:40:10,253 INFO: replica has been created using basebackup
2022-10-23 16:40:10,254 INFO: bootstrapped from leader 'node1'
2022-10-23 16:40:10,394 INFO: postmaster pid=5276
localhost:5433 - no response
2022-10-23 16:40:10.405 UTC [5276] LOG:  redirecting log output to logging collector process
2022-10-23 16:40:10.405 UTC [5276] HINT:  Future log output will appear in directory "log".
2022-10-23 16:40:10,815 INFO: Lock owner: node1; I am node2
2022-10-23 16:40:10,862 INFO: bootstrap from leader 'node1' in progress
localhost:5433 - accepting connections
localhost:5433 - accepting connections
2022-10-23 16:40:11,450 INFO: Lock owner: node1; I am node2
2022-10-23 16:40:11,450 INFO: establishing a new patroni connection to the postgres cluster
2022-10-23 16:40:11,514 INFO: no action. I am (node2), a secondary, and following a leader (node1)
2022-10-23 16:40:21,495 INFO: no action. I am (node2), a secondary, and following a leader (node1)
2022-10-23 16:40:31,449 INFO: no action. I am (node2), a secondary, and following a leader (node1)
```
Любопытно что в файле `/tmp/dump.txt`, куда скрипт фейкового рестора выписывает свои аргументы, видно такое:
```
Sun Oct 23 04:40:08 PM UTC 2022
(0/8) --scope
(1/8) --datadir
(2/8) --connstring
(3/8) --keep_data=True
(4/8) --scope=standalondb
(5/8) --role=replica
(6/8) --datadir=/var/lib/postgresql/15/standalondb
(7/8) --connstring=dbname=postgres user=replicator host=192.168.0.10 port=5433
```
Об этом говорится в [док-ции патрони](https://patroni.readthedocs.io/en/latest/replica_bootstrap.html#building-replicas): патрини, командам реализущим выполнение метода восстановления реплики - сливает, автоматом и сам, контекстную информацию про эту реплику, которую ему (патрони) задали в его конфигурации.

[Забавная статья](https://pgconf.ru/media/2020/02/17/1Pavel_Konotopov_-_storage_of_regulated_data.pdf)
В ней есть пример на прикручивание probackup-утилиты, для лепления реплики.
И пример на переопределение бустрапа кластера, с помощью probackup-утилиты, с примером настроек рековера.
Т.е., из этой статьи получается что: методов лепления реплик - может быть много.
![9](/HomeWorks/project/9.png)

### Полезности
#### Плавающий ip-шник.

[Статья с примером орг-ции "плавающего" ip-шника](https://imamyshev.wordpress.com/2022/05/29/dns-connection-point-for-patroni/) и [гитхаб-скрипт](https://github.com/IlgizMamyshev/dnscp/blob/main/dnscp.sh), который упоминается в этой статье.

[ENV-переменные, которые понимает и учитывает патрони](https://patroni.readthedocs.io/en/latest/ENVIRONMENT.html)


```shell
VIP="192.168.0.13"
IFNAME="eth0"
PREFIX="24"
ip address add $VIP/$PREFIX dev $IFNAME
ip address del $VIP/$PREFIX dev $IFNAME
```

С перемещаемым ip - не выгорело. YC не позволяет такого.

На одной из прошлой работ, в проде, использовалась субд oracle которая имела одну-две реплики (physical standby-базы, в терминах oracle), на отдельных, от primary-стороны, машинах.
Соотв-но, при свичоверах/файловерах, активная oracle-субд: "ездила" но разным нодам.
Для того чтобы организовать подключение в активную oracle-субд по какому то одному ip/fqdn использовали такую архитектуру.
На все машины, на которых выполнялись активная бд, или реплики - ставился corosunc/pacemaker.
Ноды объекдинялись в corosync-кластер, в кластере конфигурировался vip, перемещение vip-а по нодам кластера - выполнялось ч/з picemaker-команды (т.е.: это команды в bash-е).

Таким образом, для пострескл-субд, под патрони-менеджментом, можно сделать тоже самое.
А перемещение vip-а организовать в callback-скриптах патрони, которые он будет вызывать по событиям `on_stop on_start`.
Патрони - будет сливать callback-скрипту роль пг-кластера, который он запускает (или стопает) на какой то ноде.
Ну и, в callback-скрипте, глядя на эту роль - выдавать команду перемещения/подьёма vip-а, на данную ноду, где срабатывает данный callback-скрипт (если запускается пг-лидер), или не выдавать (если запускается пг-реплика).

Попробую пояснить всё это: более развёрнуто.
Есть такой проект: [Corosync](http://corosync.github.io/corosync/) - это фреймворк, опенсорс-софтваре, реализующее функционал коммуникационной системы, на нескольких машинах.
К ней есть [Pacemaker](https://clusterlabs.org/pacemaker/) - ресурсный менеджер, для построения, управления ресурсами в кластере, работает поверх corosync-ка.
И над этим всем есть ещё одна надстройка, в виде cli-утилиты, с помощью команд которой можно рулить corosync/pacemaker-кластером.

Как пример как можно создать кластер, например на вот этих же, трёх, нодах: `postgresql1 postgresql2 postgresql3` и определить в нём кластерный ресурс в виде ip-адреса.
На всех трёх нодах выполняем, от рута:
```shell
echo "192.168.0.10 postgresql1
192.168.0.11 postgresql2
192.168.0.12 postgresql3" >> /etc/hosts

apt install pacemaker corosync pcs -y
echo "hacluster:wsx1" | chpasswd
systemctl enable pcsd; systemctl status pcsd;
```

Далее, на какой то одной ноде, от рута:
```shell
pcs host auth postgresql1 addr=192.168.0.10 postgresql2 addr=192.168.0.11 postgresql3 addr=192.168.0.12 -u hacluster -p wsx1
```

Если не получили ошибки, то: создаём кластер:
```shell
pcs cluster setup --force myhacluster postgresql1 addr=192.168.0.10 postgresql2 addr=192.168.0.11 postgresql3 addr=192.168.0.12
Warning: postgresql1: The host seems to be in a cluster already as the following services are found to be running: 'corosync', 'pacemaker'. If the host is not part of a cluster, stop the services and retry
Warning: postgresql1: The host seems to be in a cluster already as cluster configuration files have been found on the host. If the host is not part of a cluster, run 'pcs cluster destroy' on host 'postgresql1' to remove those configuration files
Warning: postgresql3: The host seems to be in a cluster already as the following services are found to be running: 'corosync', 'pacemaker'. If the host is not part of a cluster, stop the services and retry
Warning: postgresql3: The host seems to be in a cluster already as cluster configuration files have been found on the host. If the host is not part of a cluster, run 'pcs cluster destroy' on host 'postgresql3' to remove those configuration files
Warning: postgresql2: The host seems to be in a cluster already as the following services are found to be running: 'corosync', 'pacemaker'. If the host is not part of a cluster, stop the services and retry
Warning: postgresql2: The host seems to be in a cluster already as cluster configuration files have been found on the host. If the host is not part of a cluster, run 'pcs cluster destroy' on host 'postgresql2' to remove those configuration files
Destroying cluster on hosts: 'postgresql1', 'postgresql2', 'postgresql3'...
postgresql1: Successfully destroyed cluster
postgresql3: Successfully destroyed cluster
postgresql2: Successfully destroyed cluster
Requesting remove 'pcsd settings' from 'postgresql1', 'postgresql2', 'postgresql3'
postgresql1: successful removal of the file 'pcsd settings'
postgresql2: successful removal of the file 'pcsd settings'
postgresql3: successful removal of the file 'pcsd settings'
Sending 'corosync authkey', 'pacemaker authkey' to 'postgresql1', 'postgresql2', 'postgresql3'
postgresql1: successful distribution of the file 'corosync authkey'
postgresql1: successful distribution of the file 'pacemaker authkey'
postgresql2: successful distribution of the file 'corosync authkey'
postgresql2: successful distribution of the file 'pacemaker authkey'
postgresql3: successful distribution of the file 'corosync authkey'
postgresql3: successful distribution of the file 'pacemaker authkey'
Sending 'corosync.conf' to 'postgresql1', 'postgresql2', 'postgresql3'
postgresql1: successful distribution of the file 'corosync.conf'
postgresql2: successful distribution of the file 'corosync.conf'
postgresql3: successful distribution of the file 'corosync.conf'
Cluster has been successfully set up.
cat /etc/corosync/corosync.conf | grep "logfile"
```

Разрешаем участие всех нод, в кластере и запускаем кластер:
```shell
pcs cluster enable --all
pcs cluster start --all
pcs status
```
![21](/HomeWorks/project/21.png)

[Дока, по св-вам кластера](https://clusterlabs.org/pacemaker/doc/deprecated/en-US/Pacemaker/1.1/html/Pacemaker_Explained/s-cluster-options.html)
Определять и прописывать в кластер механизм отстрела зависшей ноды кластера - я быстро не вспомнил/не разобрался, поэтому: просто запретил делать `stonith`:
```shell
pcs property set stonith-enabled=false
pcs property config --all | sort -k 1 -t ":" | column -t
```
```
...
startup-fencing:            true
stonith-action:             reboot
stonith-enabled:            false
stonith-max-attempts:       10
stonith-timeout:            60s
stonith-watchdog-timeout:   0
...
```

Дальше, посмотреть список всех поддерживаемых типов ресурсов в кластере можно по `pcs resource list`
Нас интересует ресурс такого типа: `ocf:heartbeat:IPaddr2 - Manages virtual IPv4 and IPv6 addresses (Linux specific version)`

[Дока на тип `ocf:heartbeat:IPaddr2`](http://www.linux-ha.org/doc/man-pages/re-ra-IPaddr2.html), ресурса.

[Дока на свойство meta ресурсов](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/high_availability_add-on_reference/s1-resourceopts-haar), в частности - тут важно свойство `migration-threshold`

Определяем ресурс типа `ocf:heartbeat:IPaddr2`, в кластере:
```shell
pcs resource create universal_ip ocf:heartbeat:IPaddr2 ip=192.168.0.14 cidr_netmask=24 meta migration-threshold="0" op monitor timeout="60s" interval="10s" on-fail="restart" op stop timeout="60s" interval="0s" on-fail="ignore" op start timeout="60s" interval="0s" on-fail="stop
```

Смотрим и двигаем кластерный ресурс, по нодам кластера - куда надо.
```shell
pcs resource status
pcs status
ip -f inet addr show eth0
pcs resource move universal_ip postgresql2
ip -f inet addr show eth0
```
![22](/HomeWorks/project/22.png)
![23](/HomeWorks/project/23.png)

Собственно, вот - у нас есть ip-шник, который, как кластерный ресурс, можно двигать по кластеру, туда и тогда куда перемещается лидер, в патрони-менеджмент кластере.

Отдельный вопрос, что это, именно в таком виде несколько оверинжиниринг.
Потому что тот же самый функционал можно получить и просто выполняя команды по навешиванию/убиранию дополнительного ip-адреса, на/с сетевой интерфейс, во время и в соответствии переездам пг-лидера, в патрони-менеджмент кластере.

Вкручивать ip-адрес, как кластерный ресурс становится много больше смысла, если в corosync/pacemaker-кластер засовывается, как кластерный сервис вся пг-база.

Тогда сама пг-база, как кластерный ресурс, и то что её нужно для работы например - ip-адрес(а), дисковые ресурсы, файлы, и прочее и прочее и прочее: тоже могут быть определены как группа взаимозависимых кластерных ресурсов (и/или как несколько групп, зависящих друг от друга)
Тогда можно определять всякие кудрявости, типа того что - если какой то ресурс, из данной группы, или из группы от которой есть зависимость - не запустился, то всё, ошибка: не запускать данную группу.

[Интересный доклад](https://www.youtube.com/watch?v=fOB49y2vGso), в котором в corosync/pacemaker-кластерваре, засунули вообще всю пг-базу как кластерный сервис.
[Большая статья на ClusterLab](https://wiki.clusterlabs.org/wiki/PgSQL_Replicated_Cluster#Operations) о инсталяции пг-кластера, как кластерного сервиса, в corosync/pacemaker-кластерваре, в виде 2-х нодового кластера.
Активный пг-кластер работает на одной ноде, и если, по каким то причинам, активный экземпляр - становится не доступен, кластерваре промоутит реплику от этого пг-кластера, на второй ноде.
[Ещё статья](https://support.itrium.ru/pages/viewpage.action?pageId=962643819), руссокязычная, на эту тему.
[Короткий видосик](https://www.youtube.com/watch?v=8IhZ43LCC3o) про определение группы из двух кластерных ресурсов.

Что у меня не получилось, с этим плавающим ip-шником.
Пусть есть такая обстановка:
![24](/HomeWorks/project/24.png)

При этом, с отдельно стоящей вм:
![25](/HomeWorks/project/25.png)

Файрволлов нет, на обоих сторонах, и локально (в смысле - с `postgresql2` - подключается):
![26](/HomeWorks/project/26.png)
![27](/HomeWorks/project/27.png)


Ну, и раз такая заполдянка от YC, с коннективити, только только haproxy сделаю, как некое изображение подключения к патрони-менеджмент бд, по единому адресу.

#### haproxy

По причинам, пояснённым в пункте выше, в рамках этой работы ограничусь только: haproxy, как средством, пусть и не отказоустойчивым, организации доступа в патрони-менеджмент пг-базу, клиентам, по одному ip/fqdn.
Подготовка отдельной ubuntu-вм c haproxy:
```shell
cd
apt update; apt upgrade -y
apt install net-tools unzip zip lynx hatop -y
apt autoremove -y
adduser --system --quiet --home /var/lib/postgresql --shell /bin/bash --group --gecos "PostgreSQL administrator" postgres
ls -lthr /var/lib/postgresql
usermod -u 5113 postgres
groupmod -g 5119 postgres
id postgres
sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
apt-get update; apt-get install postgresql -y
pg_lsclusters
pg_dropcluster --stop 15 main

apt install haproxy -y
haproxy -v
mv /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.conf.def

cat << __EOF__ > /etc/haproxy/haproxy.cfg
global
 maxconn 100
 stats socket /var/run/haproxy.stat mode 660 group haproxy expose-fd listeners
defaults
 log global
 mode tcp
 retries 2
 timeout client 30m
 timeout connect 4s
 timeout server 30m
 timeout check 5s
listen stats
 mode http
 bind *:7000
 stats enable
 stats uri /
 stats hide-version
 stats auth hap:poi1
listen postgres
 bind *:5432
 option httpchk
 http-check expect status 200
 default-server inter 3s fastinter 1s fall 2 rise 2 on-marked-down shutdown-sessions
 server postgresql1 192.168.0.10:5432 maxconn 100 check port 8008
 server postgresql2 192.168.0.11:5432 maxconn 100 check port 8008
 server postgresql3 192.168.0.12:5432 maxconn 100 check port 8008
__EOF__
vim /etc/haproxy/haproxy.cfg
systemctl stop haproxy.service; systemctl start haproxy.service; 
# systemctl enable haproxy.service
systemctl status haproxy.service

usermod -a -G haproxy postgres

lynx http://192.168.0.13:7000
```

Нашёл замечательную утилитку: `hatop`
Позволяет из командной строки получать, ч/з локальный сокет (см. `stats socket` в конфиге выше), опрашивать информацию о хапрокси и выдавать ему какие то команды управления.
Запуск hatop-утилиты и подключение, ч/з `haproxy`, к пг-кластеру в патрини:
```shell
hatop -s /var/run/haproxy.stat -i 2
```
```shell
export PGPASSWORD="qqq"
psql -h localhost -p 5432 -U postgres << __EOF__
\conninfo
select inet_server_addr();
\q
__EOF__
```
![8](/HomeWorks/project/8.png)
![5](/HomeWorks/project/5.png)

Ну и, титульные процедуры, по патрони-поддержке пг-кластера.

### Свичовер в патрони:

Фиксируем текущее состояние патрони-кластера, в терминах хапрокси (в верхнем правом углу скриншота: время):

![10](/HomeWorks/project/10.png)

Подключаемся, с хапрокcи-вм, к пг-базе, спрашиваем - куда подключились и что нибудь делаем в пг-бд:
![11](/HomeWorks/project/11.png)

Выполняем свичовер:
```shell
patronictl switchover --master postgresql3 --candidate postgresql1 --scheduled now --force
```
![13](/HomeWorks/project/13.png)

В логе патрони, на стороне `postgresql3` ноды:
```
Oct 29 14:38:52 postgresql3 patroni[738]: 2022-10-29 14:38:52,388 INFO: no action. I am (postgresql3), the leader with the lock
Oct 29 14:39:02 postgresql3 patroni[738]: 2022-10-29 14:39:02,388 INFO: no action. I am (postgresql3), the leader with the lock
Oct 29 14:39:08 postgresql3 patroni[738]: 2022-10-29 14:39:08,310 INFO: received switchover request with leader=postgresql3 candidate=postgresql1 scheduled_at=None
Oct 29 14:39:08 postgresql3 patroni[738]: 2022-10-29 14:39:08,313 INFO: Got response from postgresql1 http://192.168.0.10:8008/patroni: {"state": "running", "postmaster_start_time": "2022-10-29 14:22:42.207541+00:00", "role": "replica", "server_version": 150000, "xlog": {"received_location": 394543176, "replayed_location": 394543176, "replayed_timestamp": "2022-10-29 14:36:37.500227+00:00", "paused": false}, "timeline": 31, "dcs_last_seen": 1667054342, "database_system_identifier": "7154796699611842821", "patroni": {"version": "2.1.4", "scope": "postgres"}}
Oct 29 14:39:08 postgresql3 patroni[738]: 2022-10-29 14:39:08,410 INFO: Got response from postgresql1 http://192.168.0.10:8008/patroni: {"state": "running", "postmaster_start_time": "2022-10-29 14:22:42.207541+00:00", "role": "replica", "server_version": 150000, "xlog": {"received_location": 394543176, "replayed_location": 394543176, "replayed_timestamp": "2022-10-29 14:36:37.500227+00:00", "paused": false}, "timeline": 31, "dcs_last_seen": 1667054342, "database_system_identifier": "7154796699611842821", "patroni": {"version": "2.1.4", "scope": "postgres"}}
Oct 29 14:39:08 postgresql3 patroni[738]: 2022-10-29 14:39:08,362 INFO: Lock owner: postgresql3; I am postgresql3
Oct 29 14:39:08 postgresql3 patroni[738]: 2022-10-29 14:39:08,461 INFO: manual failover: demoting myself
Oct 29 14:39:08 postgresql3 patroni[738]: 2022-10-29 14:39:08,461 INFO: Demoting self (graceful)
Oct 29 14:39:09 postgresql3 patroni[738]: 2022-10-29 14:39:09,987 INFO: Leader key released
Oct 29 14:39:09 postgresql3 patroni[738]: 2022-10-29 14:39:09,988 INFO: Lock owner: postgresql1; I am postgresql3
Oct 29 14:39:09 postgresql3 patroni[738]: 2022-10-29 14:39:09,988 INFO: manual failover: demote in progress
Oct 29 14:39:11 postgresql3 patroni[738]: 2022-10-29 14:39:11,178 INFO: Lock owner: postgresql1; I am postgresql3
Oct 29 14:39:11 postgresql3 patroni[738]: 2022-10-29 14:39:11,178 INFO: manual failover: demote in progress
Oct 29 14:39:11 postgresql3 patroni[738]: 2022-10-29 14:39:11,654 INFO: Lock owner: postgresql1; I am postgresql3
Oct 29 14:39:11 postgresql3 patroni[738]: 2022-10-29 14:39:11,654 INFO: manual failover: demote in progress
Oct 29 14:39:11 postgresql3 patroni[738]: 2022-10-29 14:39:11,988 INFO: closed patroni connection to the postgresql cluster
Oct 29 14:39:12 postgresql3 patroni[738]: 2022-10-29 14:39:12,109 INFO: postmaster pid=1611
Oct 29 14:39:12 postgresql3 patroni[1612]: localhost:5432 - no response
Oct 29 14:39:12 postgresql3 patroni[1611]: 2022-10-29 14:39:12.122 UTC [1611] LOG:  redirecting log output to logging collector process
Oct 29 14:39:12 postgresql3 patroni[1611]: 2022-10-29 14:39:12.122 UTC [1611] HINT:  Future log output will appear in directory "log".
Oct 29 14:39:13 postgresql3 patroni[1622]: localhost:5432 - accepting connections
Oct 29 14:39:13 postgresql3 patroni[1624]: localhost:5432 - accepting connections
```
В логе ноды `postgresql1`:
```
Oct 29 14:39:02 postgresql1 patroni[793]: 2022-10-29 14:39:02,465 INFO: no action. I am (postgresql1), a secondary, and following a leader (postgresql3)
Oct 29 14:39:09 postgresql1 patroni[793]: 2022-10-29 14:39:09,918 INFO: no action. I am (postgresql1), a secondary, and following a leader (postgresql3)
Oct 29 14:39:09 postgresql1 patroni[793]: 2022-10-29 14:39:09,969 INFO: Cleaning up failover key after acquiring leader lock...
Oct 29 14:39:10 postgresql1 patroni[793]: 2022-10-29 14:39:10,015 WARNING: Could not activate Linux watchdog device: "Can't open watchdog device: [Errno 2] No such file or directory: '/dev/watchdog'"
Oct 29 14:39:10 postgresql1 patroni[793]: 2022-10-29 14:39:10,059 INFO: promoted self to leader by acquiring session lock
Oct 29 14:39:10 postgresql1 patroni[1881]: server promoting
Oct 29 14:39:10 postgresql1 patroni[793]: 2022-10-29 14:39:10,061 INFO: cleared rewind state after becoming the leader
Oct 29 14:39:11 postgresql1 patroni[793]: 2022-10-29 14:39:11,540 INFO: no action. I am (postgresql1), the leader with the lock
Oct 29 14:39:11 postgresql1 patroni[793]: 2022-10-29 14:39:11,679 INFO: no action. I am (postgresql1), the leader with the lock
```

Что на стороне клиента:
![14](/HomeWorks/project/14.png)

### Файловер в патрони:

После свичовера, выше, лидером стал пг-кластер, на ноде `postgresql1`
Грубо остановим эту вм, в YC:
![15](/HomeWorks/project/15.png)

Новым лидером стал пг-кластер на `postgresql3`:
![16](/HomeWorks/project/16.png)
записи в логе патрони-сервиса:
```
Oct 29 14:46:11 postgresql3 patroni[738]: 2022-10-29 14:46:11,655 INFO: no action. I am (postgresql3), a secondary, and following a leader (postgresql1)
Oct 29 14:46:21 postgresql3 patroni[738]: 2022-10-29 14:46:21,700 INFO: no action. I am (postgresql3), a secondary, and following a leader (postgresql1)
Oct 29 14:46:31 postgresql3 patroni[738]: 2022-10-29 14:46:31,654 INFO: Lock owner: postgresql1; I am postgresql3
Oct 29 14:46:31 postgresql3 patroni[738]: 2022-10-29 14:46:31,699 ERROR: Invalid auth token: eThDupovgVksWAnx.2395
Oct 29 14:46:31 postgresql3 patroni[738]: 2022-10-29 14:46:31,699 INFO: Trying to authenticate on Etcd...
Oct 29 14:46:31 postgresql3 patroni[738]: 2022-10-29 14:46:31,823 ERROR: watchprefix failed: ProtocolError("Connection broken: InvalidChunkLength(got length b'', 0 bytes read)", InvalidChunkLength(got length b'', 0 bytes read))
Oct 29 14:46:31 postgresql3 patroni[738]: 2022-10-29 14:46:31,828 INFO: no action. I am (postgresql3), a secondary, and following a leader (postgresql1)
Oct 29 14:46:32 postgresql3 patroni[738]: 2022-10-29 14:46:32,538 INFO: Got response from postgresql2 http://192.168.0.11:8008/patroni: {"state": "running", "postmaster_start_time": "2022-10-29 14:22:27.668497+00:00", "role": "replica", "server_version": 150000, "xlog": {"received_location": 394544104, "replayed_location": 394544104, "replayed_timestamp": "2022-10-29 14:36:37.500227+00:00", "paused": false}, "timeline": 32, "cluster_unlocked": true, "dcs_last_seen": 1667054792, "database_system_identifier": "7154796699611842821", "patroni": {"version": "2.1.4", "scope": "postgres"}}
Oct 29 14:46:32 postgresql3 patroni[738]: 2022-10-29 14:46:32,632 WARNING: Request failed to postgresql1: GET http://192.168.0.10:8008/patroni (HTTPConnectionPool(host='192.168.0.10', port=8008): Max retries exceeded with url: /patroni (Caused by ProtocolError('Connection aborted.', ConnectionResetError(104, 'Connection reset by peer'))))
Oct 29 14:46:32 postgresql3 patroni[738]: 2022-10-29 14:46:32,724 INFO: promoted self to leader by acquiring session lock
Oct 29 14:46:32 postgresql3 patroni[1799]: server promoting
Oct 29 14:46:32 postgresql3 patroni[738]: 2022-10-29 14:46:32,725 INFO: cleared rewind state after becoming the leader
Oct 29 14:46:33 postgresql3 patroni[738]: 2022-10-29 14:46:33,957 INFO: no action. I am (postgresql3), the leader with the lock
Oct 29 14:46:43 postgresql3 patroni[738]: 2022-10-29 14:46:43,870 INFO: no action. I am (postgresql3), the leader with the lock
```
Что на стороне клиента и что показывает хапрокси:
![17](/HomeWorks/project/17.png)
![18](/HomeWorks/project/18.png)

После запуск виртуалки `postgresql1` в YC, по логу патрони-сервиса, на `postgresql1` видно что патрони, автоматически, переделал пг-кластер, на этой машине, в реплику, от текущего лидера:
```
Oct 29 14:46:11 postgresql1 patroni[793]: 2022-10-29 14:46:11,585 INFO: no action. I am (postgresql1), the leader with the lock
Oct 29 14:46:21 postgresql1 patroni[793]: 2022-10-29 14:46:21,585 INFO: no action. I am (postgresql1), the leader with the lock
Oct 29 14:46:30 postgresql1 systemd[1]: Stopping Runners to orchestrate a high-availability PostgreSQL...
Oct 29 14:46:32 postgresql1 patroni[793]: 2022-10-29 14:46:32,392 ERROR: Invalid auth token: XhozbODIjZbfgGCa.2398
Oct 29 14:46:32 postgresql1 patroni[793]: 2022-10-29 14:46:32,392 INFO: Trying to authenticate on Etcd...
Oct 29 14:46:32 postgresql1 patroni[793]: 2022-10-29 14:46:32,507 ERROR: watchprefix failed: ProtocolError("Connection broken: InvalidChunkLength(got length b'', 0 bytes read)", InvalidChunkLength(got length b'', 0 bytes read))
Oct 29 14:46:32 postgresql1 systemd[1]: patroni.service: Deactivated successfully.
Oct 29 14:46:32 postgresql1 systemd[1]: Stopped Runners to orchestrate a high-availability PostgreSQL.
Oct 29 14:46:32 postgresql1 systemd[1]: patroni.service: Consumed 2.767s CPU time.
-- Boot 9cb5f9b7690a4e519f9e0fef3e8870cb --
Oct 29 14:56:04 postgresql1 systemd[1]: Started Runners to orchestrate a high-availability PostgreSQL.
Oct 29 14:56:07 postgresql1 patroni[800]: 2022-10-29 14:56:07,546 INFO: Trying to authenticate on Etcd...
Oct 29 14:56:07 postgresql1 patroni[800]: 2022-10-29 14:56:07,823 INFO: No PostgreSQL configuration items changed, nothing to reload.
Oct 29 14:56:08 postgresql1 patroni[800]: 2022-10-29 14:56:08,050 WARNING: Postgresql is not running.
Oct 29 14:56:08 postgresql1 patroni[800]: 2022-10-29 14:56:08,051 INFO: Lock owner: postgresql3; I am postgresql1
Oct 29 14:56:08 postgresql1 patroni[800]: 2022-10-29 14:56:08,052 INFO: pg_controldata:
Oct 29 14:56:08 postgresql1 patroni[800]:   pg_control version number: 1300
Oct 29 14:56:08 postgresql1 patroni[800]:   Catalog version number: 202209061
Oct 29 14:56:08 postgresql1 patroni[800]:   Database system identifier: 7154796699611842821
Oct 29 14:56:08 postgresql1 patroni[800]:   Database cluster state: shut down
Oct 29 14:56:08 postgresql1 patroni[800]:   pg_control last modified: Sat Oct 29 14:46:31 2022
Oct 29 14:56:08 postgresql1 patroni[800]:   Latest checkpoint location: 0/17844370
Oct 29 14:56:08 postgresql1 patroni[800]:   Latest checkpoint's REDO location: 0/17844370
Oct 29 14:56:08 postgresql1 patroni[800]:   Latest checkpoint's REDO WAL file: 000000200000000000000017
Oct 29 14:56:08 postgresql1 patroni[800]:   Latest checkpoint's TimeLineID: 32
Oct 29 14:56:08 postgresql1 patroni[800]:   Latest checkpoint's PrevTimeLineID: 32
Oct 29 14:56:08 postgresql1 patroni[800]:   Latest checkpoint's full_page_writes: on
Oct 29 14:56:08 postgresql1 patroni[800]:   Latest checkpoint's NextXID: 0:748
Oct 29 14:56:08 postgresql1 patroni[800]:   Latest checkpoint's NextOID: 16393
Oct 29 14:56:08 postgresql1 patroni[800]:   Latest checkpoint's NextMultiXactId: 1
Oct 29 14:56:08 postgresql1 patroni[800]:   Latest checkpoint's NextMultiOffset: 0
Oct 29 14:56:08 postgresql1 patroni[800]:   Latest checkpoint's oldestXID: 717
Oct 29 14:56:08 postgresql1 patroni[800]:   Latest checkpoint's oldestXID's DB: 1
Oct 29 14:56:08 postgresql1 patroni[800]:   Latest checkpoint's oldestActiveXID: 0
Oct 29 14:56:08 postgresql1 patroni[800]:   Latest checkpoint's oldestMultiXid: 1
Oct 29 14:56:08 postgresql1 patroni[800]:   Latest checkpoint's oldestMulti's DB: 1
Oct 29 14:56:08 postgresql1 patroni[800]:   Latest checkpoint's oldestCommitTsXid: 0
Oct 29 14:56:08 postgresql1 patroni[800]:   Latest checkpoint's newestCommitTsXid: 0
Oct 29 14:56:08 postgresql1 patroni[800]:   Time of latest checkpoint: Sat Oct 29 14:46:31 2022
Oct 29 14:56:08 postgresql1 patroni[800]:   Fake LSN counter for unlogged rels: 0/3E8
Oct 29 14:56:08 postgresql1 patroni[800]:   Minimum recovery ending location: 0/0
Oct 29 14:56:08 postgresql1 patroni[800]:   Min recovery ending loc's timeline: 0
Oct 29 14:56:08 postgresql1 patroni[800]:   Backup start location: 0/0
Oct 29 14:56:08 postgresql1 patroni[800]:   Backup end location: 0/0
Oct 29 14:56:08 postgresql1 patroni[800]:   End-of-backup record required: no
Oct 29 14:56:08 postgresql1 patroni[800]:   wal_level setting: replica
Oct 29 14:56:08 postgresql1 patroni[800]:   wal_log_hints setting: on
Oct 29 14:56:08 postgresql1 patroni[800]:   max_connections setting: 100
Oct 29 14:56:08 postgresql1 patroni[800]:   max_worker_processes setting: 8
Oct 29 14:56:08 postgresql1 patroni[800]:   max_wal_senders setting: 10
Oct 29 14:56:08 postgresql1 patroni[800]:   max_prepared_xacts setting: 0
Oct 29 14:56:08 postgresql1 patroni[800]:   max_locks_per_xact setting: 64
Oct 29 14:56:08 postgresql1 patroni[800]:   track_commit_timestamp setting: off
Oct 29 14:56:08 postgresql1 patroni[800]:   Maximum data alignment: 8
Oct 29 14:56:08 postgresql1 patroni[800]:   Database block size: 8192
Oct 29 14:56:08 postgresql1 patroni[800]:   Blocks per segment of large relation: 131072
Oct 29 14:56:08 postgresql1 patroni[800]:   WAL block size: 8192
Oct 29 14:56:08 postgresql1 patroni[800]:   Bytes per WAL segment: 16777216
Oct 29 14:56:08 postgresql1 patroni[800]:   Maximum length of identifiers: 64
Oct 29 14:56:08 postgresql1 patroni[800]:   Maximum columns in an index: 32
Oct 29 14:56:08 postgresql1 patroni[800]:   Maximum size of a TOAST chunk: 1996
Oct 29 14:56:08 postgresql1 patroni[800]:   Size of a large-object chunk: 2048
Oct 29 14:56:08 postgresql1 patroni[800]:   Date/time type storage: 64-bit integers
Oct 29 14:56:08 postgresql1 patroni[800]:   Float8 argument passing: by value
Oct 29 14:56:08 postgresql1 patroni[800]:   Data page checksum version: 1
Oct 29 14:56:08 postgresql1 patroni[800]:   Mock authentication nonce: fbe977cca9a36a39fc697a64e357173f6674aabc6970265fefc9a5ee6476822b
Oct 29 14:56:08 postgresql1 patroni[800]: 2022-10-29 14:56:08,053 INFO: Lock owner: postgresql3; I am postgresql1
Oct 29 14:56:08 postgresql1 patroni[800]: 2022-10-29 14:56:08,053 INFO: starting as a secondary
Oct 29 14:56:08 postgresql1 patroni[800]: 2022-10-29 14:56:08,317 INFO: postmaster pid=875
Oct 29 14:56:08 postgresql1 patroni[877]: localhost:5432 - no response
Oct 29 14:56:08 postgresql1 patroni[875]: 2022-10-29 14:56:08.358 UTC [875] LOG:  redirecting log output to logging collector process
Oct 29 14:56:08 postgresql1 patroni[875]: 2022-10-29 14:56:08.358 UTC [875] HINT:  Future log output will appear in directory "log".
Oct 29 14:56:09 postgresql1 patroni[890]: localhost:5432 - accepting connections
Oct 29 14:56:09 postgresql1 patroni[892]: localhost:5432 - accepting connections
Oct 29 14:56:09 postgresql1 patroni[800]: 2022-10-29 14:56:09,455 INFO: Lock owner: postgresql3; I am postgresql1
Oct 29 14:56:09 postgresql1 patroni[800]: 2022-10-29 14:56:09,455 INFO: establishing a new patroni connection to the postgres cluster
Oct 29 14:56:10 postgresql1 patroni[800]: 2022-10-29 14:56:10,810 INFO: no action. I am (postgresql1), a secondary, and following a leader (postgresql3)
Oct 29 14:56:19 postgresql1 patroni[800]: 2022-10-29 14:56:19,545 INFO: no action. I am (postgresql1), a secondary, and following a leader (postgresql3)
```
![19](/HomeWorks/project/19.png)

Хапрокси: перестаёт показывать что нода `postgresql1` в аут-е:
![20](/HomeWorks/project/20.png)