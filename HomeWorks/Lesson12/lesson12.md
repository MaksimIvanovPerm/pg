# Бэкапирование-тема
Кучка тематических ссылок
1. [http://www.interdb.jp/pg/pgsql10.html](http://www.interdb.jp/pg/pgsql10.html)
2. [ttps://dbsguru.com/restore-backup-using-pg_basebackup-postgresql/](https://dbsguru.com/restore-backup-using-pg_basebackup-postgresql/)
3. [ttps://www.percona.com/blog/2019/07/10/wal-retention-and-clean-up-pg_archivecleanup/](https://www.percona.com/blog/2019/07/10/wal-retention-and-clean-up-pg_archivecleanup/)
4. [ttps://www.highgo.ca/2021/10/01/postgresql-14-continuous-archiving-and-point-in-time-recovery/](https://www.highgo.ca/2021/10/01/postgresql-14-continuous-archiving-and-point-in-time-recovery/)

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
   ![archmode](/HomeWorks/Lesson12/archive_mode_setted.png)
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
   ![making_backup](/HomeWorks/Lesson12/making_backup.png)
   ![rotation_of_obsolete_archivelogs](/HomeWorks/Lesson12/rotation_of_obsolete_archivelogs.png)
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
5. Грубая остановка pg, по `kill -9` расстрелял процессы.
   Проверил lsof-ом что ничего открытого нет, из папки `$PGDATA`; 
   Тестовый скрипт - понятно сломался:
   ![pq_failed](/HomeWorks/Lesson12/pq_failed.png)
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
   И - всё получилось:
   ![successfull_resore_recover](/HomeWorks/Lesson12/successfull_resore_recover.png)
   ![log_successfull_resore_recover](/HomeWorks/Lesson12/log_successfull_resore_recover.png)
   И - оценка на кол-во потерянных изменений:
   ![lost_time](https://github.com/MaksimIvanovPerm/pg/blob/main/HomeWorks/Lesson12/lost_time.png)
   На скрине, выше по тексту, видно что последним таймстампом, перед тем как тестовый скрипт сказал `psql failed`, было значение `1661021604`;
   Наиболее современное значение таймстампа, которое, после восстановления, считывается из testtab-таблицы - `1661021508`
   Ну, приблизительно, изменения за 96, последних перед сбоем, секунд, восстановление не повторило, над образом выложенным из бэкапа.
6. Решил проверить ещё такой кейс: нелоггируемые структуры хранения данных.
   С ними должны быть проблема такая что, если они создаются после получения бэкапа, то, при ресторинге из бэкапа и догоне ресторенного с вал-логов - должна получится не рабочая структура данных.
   Т.е.: повторил все действия выше, только, после получения бэкапа пг-кластера, таблицу `testtab` объявлял так (unlogged-опция):
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
   ![query_unlogged_table](/HomeWorks/Lesson12/query_unlogged_table.png)



# Standby-тема
Тематические ссылки:
1. [официоз](https://www.postgresql.org/docs/14/warm-standby.html#STANDBY-SERVER-OPERATION)
2. [https://habr.com/ru/post/216067/](https://habr.com/ru/post/216067/)
3. [https://www.percona.com/blog/2021/04/22/demonstrating-pg_rewind-using-linux-contain](https://www.percona.com/blog/2021/04/22/demonstrating-pg_rewind-using-linux-contain)
4. [https://www.youtube.com/watch?v=qc7HTiJm_tQ](https://www.youtube.com/watch?v=qc7HTiJm_tQ)
5. [https://medium.com/analytics-vidhya/postgresql-streaming-replication-4b4679b352f3](https://medium.com/analytics-vidhya/postgresql-streaming-replication-4b4679b352f3)
6. [про .pgpass](https://stackoverflow.com/questions/16786011/postgresql-pgpass-not-working)

Сама подготовка standby-бд: почти тривиальна.
На стороне сервера, где нужно получить standby-базу, делается инсталяция пг, собирается кластер.
Потом, на этом сервере, переходим в `$PGDATA`, удаляем всё и, с помощью утилиты `pg_basebackup` получаем, в эту директорию образ физ-компоненты мастер-кластера.
```shell
cd "$PGDATA/"; find ./ -delete
pg_basebackup --dbname="host=${v_masterip} port=5432 user=repuser password=qazxsw321" -D "$PGDATA/" -c fast -F p -P -v
```
Выполнять можно от бд-аккаунта `postgres`, но рекомендовано заводить отдельный пг-аккаунт, с ролями `REPLICATION, LOGIN`
```shell
psql << __EOF__
create user repuser with login replication password 'qazxsw321';
\q
__EOF__
```

Больше нюансов в подготовке к этому действию.
А именно.
1. Для работы standby-бд, нужно обеспечивать доступность, для него последовательности wal-логов.
   Тут есть два подхода: настраивать архивлог-могу работы мастера и складирование архивлогов на шаредный сторидж, который будет доступен реплике и объяснять реплике (параметром `restore_command`) - откуда ей брать архлоги, если это её станет нужно.
   Либо, при архлог-моде, настраивать и использовать т.н. [репликейшен-слот](https://hevodata.com/learn/postgresql-replication-slots/).
   Репликейшен-слот позволяет мастеру понимать - какие вал-логи нужны, ассоциированной со слотом, реплике и мастер-удерживает эти вал логи у себя.
   Ещё, ч/з слот, в мастер провайдится информация о транзакицях, на стороне реплики и т.о. мастер получает возможность учитывать эти данные и не создавать своей работой конфликты, при накате вал-логов на реплику, т.е. - аналог того что делает параметр `hot_standby_feedback`.
   Обратная сторона медали тут в том что такой учёт мастером этого фидбака, про транзакции, со стороны реплики, будет задерживать выполнение операций, на стороне мастера, которые вызовут конфиликт.
2. Надо править `pg_hba.conf` - прописывать в нём возможность подключения реплики к мастеру и обратно, под аккаунтом пг-кластера, под которым будут выполняться walsender|walreceiver;
   Соответственно: надо править параметр `listen_addresses` чтобы такие подключения выполнялись.
3. На стороне вылепливаемого standby-кластера, после получения там копии физ-компоненты мастер-кластера, по pg_basebackup-утилиты, надо сделать `touch $PGDATA/standby.signal`
4. В конфигурации обоих пг-кластеров, мастера и реплики, д.б. проставлено `wal_level=replica`
   
Я решил не связываться со слотами и использовать расшариваемый сторидж, который - всё равно нужен, для хранения на нём бэкапов.
Сторидж на нфс, для работы с нфс-шарой - надо чтобы uid|gid postgresql-аккаунта ОС-и: были одинаковыми, на серверах субд.
Ну, собственно, и всё.
После запуска реплики контролировать факт её работы с теперь актуальности можно, например, таким образом:
```shell
psql -c "select pid, application_name, client_addr, state, sync_state, pg_current_wal_lsn() as current_lsn, sent_lsn, write_lsn from pg_stat_replication;"   
psql -c "select conninfo from pg_stat_wal_receiver;"
```

Значительно больше интересовала возможность быстро получить в работу новую физическую реплику, после того как для старой реплики былы выполнена операция промоута.
Потому что, out-of-box, операции свичовера, если выражаться в терминах oracle-субд, в пг - нет, на уровне скл-команд.
А сама операция промоута - просто удаляет `$PGDATA/standby.signal` файл, останавливает накат и открывает реплику как мастер-кластер.
Открывает в новом таймлайне.

Т.е., начиная с этого момента времени мастеров - два, старый и новый, причём старый - живёт в старом таймлайне и, вообще говоря, может ещё и какие то транзакции обслуживать.
Т.е. эволюционировать как то по своему, относительно нового мастера.
Поэтому у старого мастера - надо сносить физ-компоненту, всю, и начинать, по `pg_basebackup` вытягивать, на его сторону, в его `$PGDATA`: актуальный образ физ-компоненты нового, актуального мастера.
`Слюшай, это хорошо? Это ... пративна!` (с) "Райкин, монолог [Дефицит](https://www.youtube.com/watch?v=mFNAUv17QFc)"

Но есть решение: утилита [pg_rewind](https://www.postgresql.org/docs/14/app-pgrewind.html)
Для работы этой утилите нужно чтобы, либо, пг-кластера (мастер/реплика) работали в чексумм-моде, или (и лучше) было выставлено `wal_log_hints=on`, тоже, на обои сторонах.
По `wal_log_hints=on`: в редо-поток мастер начинает писать весь образ модифицированного, какой то транзакцией, дата-пейджа.
Т.о., после промоута, на стороне бывшего мастера, можно будет понять, глядя на старый и на новый мастера одновременно (pg_rewind - требует подключения в новый мастер, или доступа в его `$PGDATA`):
1. Начиная с какого именно момента времени появился новый таймлайн.
2. Какие именно дата-пейджи менялись, с этого момента времени
3. Взять именно и только эти дата-пейджи из нового мастера и вписать их в физ-компоненту старого мастера.

Таким образом можно, спортивно, откатить старый мастер в то состояние, от того момента времени, с которого новый мастер - начал работать как мастер.
Ну и. Если с этого момента времени - есть все вал-логи, от откаченный мастер - может быть запущен как реплика и может начать применять на себя эти самые вал-логи.

У меня получилось выполнять эту процедуру в виде такой пос-ти действий:

1. Пусть есть настроенная физ-я репликация: мастер и хот-реплика:
   ![1](/HomeWorks/Lesson12/1.png)   
   ![2](/HomeWorks/Lesson12/2.png)   
   На стороне действующего мастера выполняем (опционально):
   ```shell
   psql -c "checkpoint;" 
   psql -c "select pg_switch_wal();" 
   ```
2. На текущей standby-стороне сделать `pg_promote();` Оно удалит `$PGDATA/standby.signal` и откроет кластер как праймари.
   Конфигурация реплика-кластера - не меняется, на этом шаге.
   `psql -c "select pg_promote();"`
   На этот момент времени: существуют два праймари-кластера, старый и новый (который запромоутили).
   Лог нового мастера:
   ```shell
   2022-08-27 08:58:12.908 UTC [1820] LOG:  received promote request 
   2022-08-27 08:58:12.909 UTC [1859] FATAL:  terminating walreceiver process due to administrator command 
   cp: cannot stat '/mnt/sharedstorage/archivelogs/0000000A.history': No such file or directory 
   cp: cannot stat '/mnt/sharedstorage/archivelogs/00000009000000000000006F': No such file or directory 
   2022-08-27 08:58:12.913 UTC [1820] LOG:  invalid record length at 0/6F000060: wanted 24, got 0 
   2022-08-27 08:58:12.913 UTC [1820] LOG:  redo done at 0/6F000028 system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 156.96 s 
   cp: cannot stat '/mnt/sharedstorage/archivelogs/00000009000000000000006F': No such file or directory 
   cp: cannot stat '/mnt/sharedstorage/archivelogs/0000000A.history': No such file or directory 
   2022-08-27 08:58:12.922 UTC [1820] LOG:  selected new timeline ID: 10 
   2022-08-27 08:58:13.079 UTC [1820] LOG:  archive recovery complete 
   cp: cannot stat '/mnt/sharedstorage/archivelogs/00000009.history': No such file or directory 
   2022-08-27 08:58:13.110 UTC [1819] LOG:  database system is ready to accept connections 
   ``` 
   ![3](/HomeWorks/Lesson12/3.png)
3. На бывшей primary-стороне выполнить
   ```shell 
   v_localip=$( ifconfig eth0 | egrep -o "inet [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | awk '{printf "%s", $2;}' ) 
   case "$v_localip" in 
        "10.129.0.5" ) v_masterip="10.129.0.30" ;; 
        "10.129.0.30" ) v_masterip="10.129.0.5" ;; 
        *) v_masterip="error" ;; 
   esac 
   echo "Local IP: ${v_localip}; Master IP: ${v_masterip}" 
    
   pg_ctlcluster 14 main stop 
   /usr/lib/postgresql/14/bin/pg_rewind --target-pgdata="$PGDATA/"  --source-server='host=10.129.0.30 port=5432 user=postgres password=qazxsw321' -P 
    
   touch $PGDATA/standby.signal 
   if [ "$v_masterip" != "error" ]; then 
      cat << __EOF__ > /etc/postgresql/14/main/rep.conf 
   primary_conninfo='host=${v_masterip} port=5432 user=repuser password=qazxsw321' 
   archive_mode=on 
   archive_command='/bin/true' 
   restore_command = 'cp /mnt/sharedstorage/archivelogs/%f "%p"' 
   hot_standby=on 
   hot_standby_feedback=on 
   max_standby_archive_delay=60s 
   max_standby_streaming_delay=60s 
   archive_cleanup_command = 'pg_archivecleanup /mnt/sharedstorage/archivelogs %r' 
   recovery_target_timeline='latest' 
   wal_keep_size=100MB 
   __EOF__ 
   sed -i -e "s/.*include_if_exists.*/include_if_exists=\'rep.conf\'/" $PGCONF; grep "include_if_exists" $PGCONF 
   restart_cluster 
   psql -c "select name, setting from pg_settings where name in ('wal_keep_size','listen_addresses','primary_conninfo','recovery_target_timeline','archive_cleanup_command','hot_standby','wal_log_hints','wal_sender_timeout ','wal_level','archive_mode','archive_command','restore_command','full_page_writes') order by name;" 
   else 
      echo "Error: can not determ master-side ip; Nothing is changed here" 
   fi 
   ``` 
   ![4](/HomeWorks/Lesson12/4.png)
   ![5](/HomeWorks/Lesson12/5.png)
4. На действующем-новом мастере выполнить:
   ```shell 
   cat << __EOF__ > /etc/postgresql/14/main/rep.conf 
   archive_mode=on 
   archive_command='/var/lib/postgresql/archive.sh "/mnt/sharedstorage/archivelogs" "%f" "%p"' 
   restore_command='cp /mnt/sharedstorage/archivelogs/%f "%p"' 
   hot_standby=off 
   wal_keep_size=100MB 
   __EOF__ 
   sed -i -e "s/.*include_if_exists.*/include_if_exists=\'rep.conf\'/" $PGCONF; grep "include_if_exists" $PGCONF 
   restart_cluster 
   psql -c "select name, setting from pg_settings where name in ('wal_keep_size','listen_addresses','primary_conninfo','recovery_target_timeline','archive_cleanup_command','hot_standby','wal_log_hints','wal_sender_timeout ','wal_level','archive_mode','archive_command','restore_command','full_page_writes') order by name;" 
   date 
   psql -c "select pid, application_name, client_addr, state, sync_state, pg_current_wal_lsn() as current_lsn, sent_lsn, write_lsn from pg_stat_replication;"    
   ``` 
   ![6](/HomeWorks/Lesson12/6.png)
5. Проверка:
   ![7](/HomeWorks/Lesson12/7.png)
   ![8](/HomeWorks/Lesson12/8.png)
