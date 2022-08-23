 
# Бэкапирование-тема
Кучка тематических ссылок
[http://www.interdb.jp/pg/pgsql10.html](http://www.interdb.jp/pg/pgsql10.html)
[ttps://dbsguru.com/restore-backup-using-pg_basebackup-postgresql/](ttps://dbsguru.com/restore-backup-using-pg_basebackup-postgresql/)
[ttps://www.percona.com/blog/2019/07/10/wal-retention-and-clean-up-pg_archivecleanup/](ttps://www.percona.com/blog/2019/07/10/wal-retention-and-clean-up-pg_archivecleanup/)
[ttps://www.highgo.ca/2021/10/01/postgresql-14-continuous-archiving-and-point-in-time-recovery/](ttps://www.highgo.ca/2021/10/01/postgresql-14-continuous-archiving-and-point-in-time-recovery/)

Вообще говоря: тут надо расшариваемый и физически отдельный, от серверов субд, сторидж, для хранения бэкапов.
И, лучше, не один.
Проще всего: нфс-шара.
С нфс-шарой немедленно вылезет проблема uid|gid ОС-аккаунтов, которые, с нфс-клиентов, должны читать/писать с/на шару.

1. Подготовка виртуалки, под нфс-сервер, создание, монтирование нфс-шары в вм с пг-кластером:
   ```shell
   sudo su root
   apt update; apt upgrade -y
   apt install nfs-kernel-server net-tools -y
   SHAREDSTORAGE="/mnt/sharedstorage"
   mkdir -p "$SHAREDSTORAGE"
   chown -R nobody:nogroup "$SHAREDSTORAGE"
   chmod 777 "$SHAREDSTORAGE"
   
   grep -q -i -m 1 -- "$SHAREDSTORAGE" /etc/exports
   [ "$?" -ne "0" ] && echo "$SHAREDSTORAGE 158.160.0.89/24(rw,sync,no_subtree_check)" >> /etc/exports
   
   exportfs -a -v
   systemctl restart nfs-server.service
   systemctl status nfs-server.service
   ```
2. Подготовка пг-сервера.
   ```shell
   sudo su root
   apt update; apt upgrade -y
   adduser --system --quiet --home /var/lib/postgresql --no-create-home --shell /bin/bash --group --gecos "PostgreSQL administrator" postgres
   usermod -u 5113 postgres
   groupmod -g 5119 postgres
   id postgres
   
   apt install nfs-common net-tools -y
   sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
   wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
   apt-get update
   apt-get install postgresql -y
   pg_lsclusters
   pg_dropcluster --stop 14 main
   
   SHAREDSTORAGE="/mnt/sharedstorage"
   mkdir -p "$SHAREDSTORAGE"
   #mount -o proto=udp 10.129.0.11:/mnt/sharedstorage /mnt/sharedstorage
   #umount /mnt/sharedstorage
   grep -q -i -m 1 -- "$SHAREDSTORAGE" /etc/fstab
   [ "$?" -ne "0" ] && echo "10.129.0.11:/mnt/sharedstorage $SHAREDSTORAGE nfs defaults 0 0" >> /etc/fstab
   mount -a
   cat /proc/mounts | grep [s]haredstorage
   pg_createcluster --start --start-conf=manual 14 main
   ```
   Дальше, от OC-аккаунта `postgress`
   ```shell
   [ ! -d "/mnt/sharedstorage/backup" ] && mkdir -p "/mnt/sharedstorage/backup"
   [ ! -d "/mnt/sharedstorage/archivelogs" ] && mkdir -p "/mnt/sharedstorage/archivelogs"
   ```
   Готовим скрипт, который будем вписывать в `archive_command` параметр бэкапируемого пг-кластера:
   ```shell
   cat __EOF__ > /var/lib/postgresql/archive.sh 
   #!/bin/bash 
   ARCHIVEDIR="$1" 
   WALLOGNAME="$2" 
   WALLOGPATH="$3" 
   LOGFILE="/var/log/postgresql/postgresql-14-main.log" 
    
   output(){ 
   local v_msg="$1" v_ts 
   if [ ! -z "$v_msg" ]; then 
      v_ts=$(date +%Y:%m:%d-%H:%M:%S) 
      echo "${v_ts} $v_msg" 
   fi 
   } 
   #### Main routine 
   output "Trying to archive ${WALLOGPATH} to ${ARCHIVEDIR}/${WALLOGNAME}" 
   if [ ! -d "$ARCHIVEDIR" ]; then 
      output "There is not directory ${ARCHIVEDIR}" 
      exit 1 
   fi 
    
   if [ ! -f "${WALLOGPATH}" ]; then 
      output "There is no file ${WALLOGPATH}" 
      exit 2 
   fi 
    
   if [ -f "${ARCHIVEDIR}/${WALLOGNAME}" ]; then 
       output "Archive file ${ARCHIVEDIR}/${WALLOGNAME} already is" 
       v_rc="0" 
   else 
       cp "$WALLOGPATH" "${ARCHIVEDIR}/${WALLOGNAME}" 
       v_rc="$?" 
   fi 
    
   if [ "$v_rc" -eq "0" ]; then 
       output "archived successfully" 
   else 
       output "error: ${v_rc}" 
   fi 
   exit "$v_rc" 
   __EOF__ 
   chmod u+x  /var/lib/postgresql/archive.sh 
   ```
   Проставляем параметры, перестартуем пг-кластер, смотрим что параметры применились, свичим оперативный вал-лог:
   ```shell
   psql << __EOF__ 
   alter system set wal_level='replica'; 
   alter system set archive_mode=on; 
   alter system set archive_command='/var/lib/postgresql/archive.sh "/mnt/sharedstorage/archivelogs" "%f" "%p"'; 
   alter system set restore_command = 'cp /mnt/sharedstorage/archivelogs/%f "%p"' 
   __EOF__ 
   restart_cluster 
   psql -c "select name, setting from pg_settings where name in ('wal_level','archive_mode','archive_command','restore_command','full_page_writes') order by name;" 
   psql -c "select pg_switch_wal();" 
   ``` 
3. Создание бэкапа, ротирование obsolete-архивлогов:
   ```shell
   [ ! -d "/mnt/sharedstorage/backup" ] && mkdir -p "/mnt/sharedstorage/backup" 
   [ ! -d "/mnt/sharedstorage/archivelogs" ] && mkdir -p "/mnt/sharedstorage/archivelogs" 
   cd /mnt/sharedstorage/backup; find ./ -delete 2>/dev/null 
   find /mnt/sharedstorage/archivelogs -name '*.backup' -delete 
   cd 
   psql -c "select pg_switch_wal();" 
   # pg_basebackup - может подключаться к удалённому пг-кластеру, и тянуть данные от него, ч/з сеть.
   pg_basebackup -D /mnt/sharedstorage/backup/ -F p --wal-method=stream -c fast -l "backup1" -P -v 
   if [ "$?" -eq "0" ]; then
      # Надо бы автоматизировать поиск последнего *.backup-файла.
      pg_archivecleanup -d /mnt/sharedstorage/archivelogs 00000001000000000000002B.00000028.backup 
   fi
   ```
4. Именно после создания бэкапа: скриптик для каких то изменений в бд и выполнение этого скрипта.
   ```shell
   psql -c "create table testtab(col1 integer);" 
   cat /dev/null > $HOME/journal.txt 
   v_count="1" 
   while [ 1 ]; do 
        v_val=$(date +%s) 
        psql -v ON_ERROR_STOP=1 -c "insert into testtab(col1) values($v_val);" 1>/dev/null 2>&1 
        [ "$?" -ne "0" ] && echo "psql failed" 
        echo "$v_val" | tee -a "$HOME/journal.txt" 
        v_count=$((v_count+1)) 
        if [ "$v_count" -gt "20" ]; then 
           psql -c "select pg_switch_wal();" 
           v_count="1" 
        fi 
        sleep 5 
   done 
   ``` 
5. Грубая остановка pg
   Удаление физ-компоненты pg-кластера, восстановление её из бэкапа:
   ```shell
   cd $PGDATA/ 
   find ./ -type f -delete 
   rm -rf ./ 
   cp -Hr /mnt/sharedstorage/backup/ ./ 
   ls -lthr 
   # find out later 
   mv -v ./backup/PG_VERSION ./ 
   mv -v ./backup/global/pg_control ./global/ 
   cp -v /mnt/sharedstorage/archivelogs/* $PGDATA/pg_wal/ 
   pg_ctlcluster 14 main start 
   ``` 
   Тут сразу же допустил себе несколько ошибок.
   Первое: надо было копировать из бэкапа так, именно, со звёздочкой `cp -Hr /mnt/sharedstorage/backup/* ./`):
   И вообще лучше это копирование параллелить, как то и делать рсинком.
   Но сначала, из за того что неправильно ресторил файлы из бэкапа, на попытку запуска получал: 
   ```shell
   postgres@postgresql1:~/14/main$ pg_ctlcluster 14 main start
   Warning: the cluster will not be running as a systemd service. Consider using systemctl:
     sudo systemctl start postgresql@14-main
   Error: /usr/lib/postgresql/14/bin/pg_ctl /usr/lib/postgresql/14/bin/pg_ctl start -D /var/lib/postgresql/14/main -l /var/log/postgresql/postgresql-14-main.log -s -o  -c config_file="/etc/postgresql/14/main/postgresql.conf"  exited with status 1:
   pg_ctl: directory "/var/lib/postgresql/14/main" is not a database cluster directory
   ```
   Первый совет от гугла:
   ```shell
   postgres@postgresql1:~/14/main$ find ./ -type f -name 'PG_VERSION' 
   ./backup/base/1/PG_VERSION 
   ./backup/base/13761/PG_VERSION 
   ./backup/base/13760/PG_VERSION 
   ./backup/PG_VERSION 
   postgres@postgresql1:~/14/main$ mv -v ./backup/PG_VERSION ./ 
   renamed './backup/PG_VERSION' -> './PG_VERSION' 
   postgres@postgresql1:~/14/main$ cat ./PG_VERSION 
   14 
   ``` 
   Вторая проблема и действия по ней:
   ```shell
   postgres@postgresql1:~/14/main$ pg_ctlcluster 14 main start 
   Warning: the cluster will not be running as a systemd service. Consider using systemctl: 
     sudo systemctl start postgresql@14-main 
   Error: /usr/lib/postgresql/14/bin/pg_ctl /usr/lib/postgresql/14/bin/pg_ctl start -D /var/lib/postgresql/14/main -l /var/log/postgresql/postgresql-14-main.log -s -o  -c config_file="/etc/postgresql/14/main/postgresql.conf"  exited with status 1: 
   2022-08-20 19:12:15.675 GMT [5876] LOG:  skipping missing configuration file "/var/lib/postgresql/14/main/postgresql.auto.conf" 
   postgres: could not find the database system 
   Expected to find it in the directory "/var/lib/postgresql/14/main", 
   but could not open file "/var/lib/postgresql/14/main/global/pg_control": No such file or directory 
   pg_ctl: could not start server 
   Examine the log output. 
   postgres@postgresql1:~/14/main$ find ./ -type f -name 'pg_control' 
   ./backup/global/pg_control 
   postgres@postgresql1:~/14/main$ ls -lthr ./global/ 
   total 0 
   postgres@postgresql1:~/14/main$ mv -v ./backup/global/pg_control ./global/ 
   renamed './backup/global/pg_control' -> './global/pg_control' 
   ``` 
   Третье: при грубой остановке - зря удалил папку $PGDATA/pg_wal, после грубой остановки кластера - снёс последние вал-логи.
   ```shell 
   '/mnt/sharedstorage/archivelogs/000000010000000000000006' -> '/var/lib/postgresql/14/main/pg_wal/000000010000000000000006' 
   '/mnt/sharedstorage/archivelogs/000000010000000000000006.00000028.backup' -> '/var/lib/postgresql/14/main/pg_wal/000000010000000000000006.00000028.backup' 
   '/mnt/sharedstorage/archivelogs/000000010000000000000007' -> '/var/lib/postgresql/14/main/pg_wal/000000010000000000000007' 
   '/mnt/sharedstorage/archivelogs/000000010000000000000008' -> '/var/lib/postgresql/14/main/pg_wal/000000010000000000000008' 
   '/mnt/sharedstorage/archivelogs/000000010000000000000009' -> '/var/lib/postgresql/14/main/pg_wal/000000010000000000000009' 
   '/mnt/sharedstorage/archivelogs/00000001000000000000000A' -> '/var/lib/postgresql/14/main/pg_wal/00000001000000000000000A' 
   '/mnt/sharedstorage/archivelogs/00000001000000000000000B' -> '/var/lib/postgresql/14/main/pg_wal/00000001000000000000000B' 
   '/mnt/sharedstorage/archivelogs/00000001000000000000000C' -> '/var/lib/postgresql/14/main/pg_wal/00000001000000000000000C' 
   '/mnt/sharedstorage/archivelogs/00000001000000000000000D' -> '/var/lib/postgresql/14/main/pg_wal/00000001000000000000000D' 
   '/mnt/sharedstorage/archivelogs/00000001000000000000000E' -> '/var/lib/postgresql/14/main/pg_wal/00000001000000000000000E' 
   '/mnt/sharedstorage/archivelogs/00000001000000000000000F' -> '/var/lib/postgresql/14/main/pg_wal/00000001000000000000000F' 
   '/mnt/sharedstorage/archivelogs/000000010000000000000010' -> '/var/lib/postgresql/14/main/pg_wal/000000010000000000000010' 
   '/mnt/sharedstorage/archivelogs/000000010000000000000011' -> '/var/lib/postgresql/14/main/pg_wal/000000010000000000000011' 
   '/mnt/sharedstorage/archivelogs/000000010000000000000012' -> '/var/lib/postgresql/14/main/pg_wal/000000010000000000000012' 
   '/mnt/sharedstorage/archivelogs/000000010000000000000013' -> '/var/lib/postgresql/14/main/pg_wal/000000010000000000000013' 
   '/mnt/sharedstorage/archivelogs/000000010000000000000014' -> '/var/lib/postgresql/14/main/pg_wal/000000010000000000000014' 
   postgres@postgresql1:~/14/main$ pg_ctlcluster 14 main start 
   Warning: the cluster will not be running as a systemd service. Consider using systemctl: 
     sudo systemctl start postgresql@14-main 
   Error: /usr/lib/postgresql/14/bin/pg_ctl /usr/lib/postgresql/14/bin/pg_ctl start -D /var/lib/postgresql/14/main -l /var/log/postgresql/postgresql-14-main.log -s -o  -c config_file="/etc/postgresql/14/main/postgresql.conf"  exited with status 1: 
   2022-08-20 19:20:39.254 GMT [5918] LOG:  skipping missing configuration file "/var/lib/postgresql/14/main/postgresql.auto.conf" 
   2022-08-20 19:20:39.275 UTC [5918] LOG:  starting PostgreSQL 14.5 (Ubuntu 14.5-1.pgdg22.04+1) on x86_64-pc-linux-gnu, compiled by gcc (Ubuntu 11.2.0-19ubuntu1) 11.2.0, 64-bit 
   2022-08-20 19:20:39.275 UTC [5918] LOG:  listening on IPv6 address "::1", port 5432 
   2022-08-20 19:20:39.275 UTC [5918] LOG:  listening on IPv4 address "127.0.0.1", port 5432 
   2022-08-20 19:20:39.278 UTC [5918] LOG:  listening on Unix socket "/var/run/postgresql/.s.PGSQL.5432" 
   2022-08-20 19:20:39.284 UTC [5919] LOG:  database system was interrupted; last known up at 2022-08-20 18:24:30 UTC 
   2022-08-20 19:20:40.659 UTC [5919] LOG:  database system was not properly shut down; automatic recovery in progress 
   2022-08-20 19:20:40.674 UTC [5919] LOG:  redo starts at 0/6000028 
   2022-08-20 19:20:40.680 UTC [5919] LOG:  file "pg_xact/0000" doesn't exist, reading as zeroes 
   2022-08-20 19:20:40.680 UTC [5919] CONTEXT:  WAL redo at 0/70169A0 for Transaction/COMMIT: 2022-08-20 18:28:14.866372+00; inval msgs: catcache 76 catcache 75 catcache 76 catcache 75 catcache 51 catcache 50 catcache 7 catcache 6 catcache 7 catcache 6 catcache 7 catcache 6 catcache 7 catcache 6 catcache 7 catcache 6 catcache 7 catcache 6 catcache 7 catcache 6 snapshot 2608 relcache 16387 
   2022-08-20 19:20:40.682 UTC [5919] LOG:  redo done at 0/14002D08 system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.00 s 
   2022-08-20 19:20:41.009 UTC [5919] FATAL:  could not access status of transaction 1 
   2022-08-20 19:20:41.009 UTC [5919] DETAIL:  Could not open file "pg_multixact/offsets/0000": No such file or directory. 
   2022-08-20 19:20:41.012 UTC [5918] LOG:  startup process (PID 5919) exited with exit code 1 
   2022-08-20 19:20:41.012 UTC [5918] LOG:  aborting startup due to startup process failure 
   2022-08-20 19:20:41.013 UTC [5918] LOG:  database system is shut down 
   pg_ctl: could not start server 
   Examine the log output. 
   ``` 
   Т.е.: намекается что нужно делать `Point-In-Time-Recovery`
   Для этого, в пг, есть разнообразные `recover_target*`параметры, с пом-ю которых можно задать момент времени, до которого рековерить образ пг-кластера.
   Ну. Тут дан так называемый lsn-номер: `0/6000028`, аналог scn-каунтера в oracle-бд.
   Поэтому - `recovery_target_lsn='0/70169A0'`:
   И - всё получилось
   И - оценка на кол-во потерянных изменений:
6. Решил проверить ещё такой кейс: нелоггируемые структуры хранения данных.
   С ними должны быть проблема такая что, если они создаются после получения бэкапа, то, при ресторинге из бэкапа и догоне ресторенного с вал-логов - должна получится не рабочая структура данных.
   Т.е.: повторил все действия выше, только, после получения бэкапа пг-кластера, таблицу `testtab` объявлял так:
   ```shell 
   psql -c "select pg_switch_wal();" 
   psql -c "drop table testtab;" 2>/dev/null 
   psql -c "create unlogged table testtab(col1 integer);" 
   cat /dev/null > $HOME/journal.txt 
   v_count="1" 
   while [ 1 ]; do 
        v_val=$(date +%s) 
        psql -v ON_ERROR_STOP=1 -c "insert into testtab(col1) values($v_val);" 1>/dev/null 2>&1 
        [ "$?" -ne "0" ] && echo "psql failed" 
        echo "$v_val" | tee -a "$HOME/journal.txt" 
        v_count=$((v_count+1)) 
        if [ "$v_count" -gt "20" ]; then 
           psql -c "select pg_switch_wal();" 
           v_count="1" 
        fi 
        sleep 5 
   done 
   ``` 
   Расстрелял процессы пг. Удалил, в дата-директории, всё, кроме папки `pg_wal`.
   Выложил файлы из бэкапа, сделал попытку запустить бд, получил ошибку про необходимость создать `recovery.signal` файл.
   Ну, ок. Создал.
   Снова запустил пг-кластер - запустилось, сделало рековер:
   ``` 
   2022-08-21 12:46:12.714 UTC [2822] HINT:  If you are restoring from a backup, touch "/var/lib/postgresql/14/main/recovery.signal" a 
   nd add required recovery options. 
           If you are not restoring from a backup, try removing the file "/var/lib/postgresql/14/main/backup_label". 
           Be careful: removing "/var/lib/postgresql/14/main/backup_label" will result in a corrupt cluster if restoring from a backup 
   . 
   2022-08-21 12:46:12.716 UTC [2821] LOG:  startup process (PID 2822) exited with exit code 1 
   2022-08-21 12:46:12.716 UTC [2821] LOG:  aborting startup due to startup process failure 
   2022-08-21 12:46:12.717 UTC [2821] LOG:  database system is shut down 
   pg_ctl: could not start server 
   Examine the log output. 
   2022-08-21 12:47:08.563 UTC [2835] LOG:  starting PostgreSQL 14.5 (Ubuntu 14.5-1.pgdg22.04+1) on x86_64-pc-linux-gnu, compiled by gcc (Ubuntu 11.2.0-19ubuntu1) 11.2.0, 64-bit 
   2022-08-21 12:47:08.563 UTC [2835] LOG:  listening on IPv6 address "::1", port 5432 
   2022-08-21 12:47:08.563 UTC [2835] LOG:  listening on IPv4 address "127.0.0.1", port 5432 
   2022-08-21 12:47:08.566 UTC [2835] LOG:  listening on Unix socket "/var/run/postgresql/.s.PGSQL.5432" 
   2022-08-21 12:47:08.571 UTC [2836] LOG:  database system was interrupted; last known up at 2022-08-21 12:14:59 UTC 
   cp: cannot stat '/mnt/sharedstorage/archivelogs/00000002.history': No such file or directory 
   2022-08-21 12:47:08.581 UTC [2836] LOG:  starting archive recovery 
   2022-08-21 12:47:08.595 UTC [2836] LOG:  restored log file "00000001000000000000002B" from archive 
   2022-08-21 12:47:08.728 UTC [2836] LOG:  redo starts at 0/2B000028 
   2022-08-21 12:47:08.730 UTC [2836] LOG:  consistent recovery state reached at 0/2B000138 
   2022-08-21 12:47:08.730 UTC [2835] LOG:  database system is ready to accept read-only connections 
   2022-08-21 12:47:08.744 UTC [2836] LOG:  restored log file "00000001000000000000002C" from archive 
   2022-08-21 12:47:08.892 UTC [2836] LOG:  restored log file "00000001000000000000002D" from archive 
   2022-08-21 12:47:09.041 UTC [2836] LOG:  restored log file "00000001000000000000002E" from archive 
   2022-08-21 12:47:09.192 UTC [2836] LOG:  restored log file "00000001000000000000002F" from archive 
   2022-08-21 12:47:09.323 UTC [2836] LOG:  restored log file "000000010000000000000030" from archive 
   cp: cannot stat '/mnt/sharedstorage/archivelogs/000000010000000000000031': No such file or directory 
   2022-08-21 12:47:09.452 UTC [2836] LOG:  invalid record length at 0/31002C30: wanted 24, got 0 
   2022-08-21 12:47:09.452 UTC [2836] LOG:  redo done at 0/31002C08 system usage: CPU: user: 0.00 s, system: 0.02 s, elapsed: 0.72 s 
   2022-08-21 12:47:09.452 UTC [2836] LOG:  last completed transaction was at log time 2022-08-21 12:43:40.822125+00 
   cp: cannot stat '/mnt/sharedstorage/archivelogs/000000010000000000000031': No such file or directory 
   cp: cannot stat '/mnt/sharedstorage/archivelogs/00000002.history': No such file or directory 
   2022-08-21 12:47:09.467 UTC [2836] LOG:  selected new timeline ID: 2 
   2022-08-21 12:47:09.628 UTC [2836] LOG:  archive recovery complete 
   cp: cannot stat '/mnt/sharedstorage/archivelogs/00000001.history': No such file or directory 
   2022-08-21 12:47:09.727 UTC [2835] LOG:  database system is ready to accept connections 
   2022:08:21-12:47:09 Trying to archive pg_wal/00000002.history to /mnt/sharedstorage/archivelogs/00000002.history 
   2022:08:21-12:47:09 archived successfully 
   2022:08:21-12:47:09 Trying to archive pg_wal/000000010000000000000031.partial to /mnt/sharedstorage/archivelogs/000000010000000000000031.partial 
   2022:08:21-12:47:09 archived successfully 
   2022-08-21 12:49:13.880 UTC [2901] postgres@postgres ERROR:  relation "testtab1" does not exist at character 57 
   ``` 
   Спросил таблицу. Не сругнулось но - и данных нет. Впрочем - резонно, нелоггируемая же.




# Standby-тема
