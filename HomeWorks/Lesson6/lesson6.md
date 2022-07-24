 
1. Присоединил к вм дополнительный диск, на 8Гб: ![6_1](/HomeWorks/Lesson6/6_1.png)
   Выполнил:
   ```shell
   (echo n; echo p; echo ""; echo ""; echo ""; echo w) | fdisk /dev/vdb
   fdisk -l /dev/vdb
   ```
   Выполнил:
   ```shell
   root@postgresql1:~# mkfs.xfs /dev/vdb1
   meta-data=/dev/vdb1              isize=512    agcount=4, agsize=524224 blks
            =                       sectsz=4096  attr=2, projid32bit=1
            =                       crc=1        finobt=1, sparse=1, rmapbt=0
            =                       reflink=1
   data     =                       bsize=4096   blocks=2096896, imaxpct=25
            =                       sunit=0      swidth=0 blks
   naming   =version 2              bsize=4096   ascii-ci=0, ftype=1
   log      =internal log           bsize=4096   blocks=2560, version=2
            =                       sectsz=4096  sunit=1 blks, lazy-count=1
   realtime =none                   extsz=4096   blocks=0, rtextents=0
   root@postgresql1:~# mkdir /mnt/pgdata
   root@postgresql1:~# mount -t xfs -o noatime,nodiratime /dev/vdb1 /mnt/pgdata
   root@postgresql1:~# cat /proc/mounts | grep "/mnt/pgdata"
   /dev/vdb1 /mnt/pgdata xfs rw,noatime,nodiratime,attr2,inode64,logbufs=8,logbsize=32k,noquota 0 0
   root@postgresql1:~# echo "/dev/vdb1 /mnt/pgdata xfs noatime,nodiratime 0 0" >> /etc/fstab
   root@postgresql1:~# shutdown -r now
   ```
   ![6_2_1](/HomeWorks/Lesson6/6_2_1.png)
2. Контроль состояния кластера. Текущая дата-директория: `/var/lib/postgresql/14/main`; Создание тестовой таблицы:
   ![6_3](/HomeWorks/Lesson6/6_3.png) 
3. В жизни: продукционную бд - конечно же не 1) оставливать будет сложно из за сопровотивления бизнеса и 2) бизнес будет принуждать к возможно меньшему даунтайму. 
   Поэтому и из любопытства перемещение датафайлов выполнил в две операции.
   Первоночальное копирование образов фйлов:
   ```shell
   sudo chown -R postgres:postgres /mnt/pgdata
   sudo chmod -R 700 /mnt/pgdata  # I found it later
   export PGCONF="/etc/postgresql/14/main/postgresql.conf"
   export RSYNC="/usr/bin/rsync"
   export SOURCE_DIR="/var/lib/postgresql/14/main"
   export TARGET_DIR="/mnt/pgdata"
   
   #### Directory deals
   cd
   cat /dev/null > ./temp.txt
   find "$SOURCE_DIR" -type d | tee -a ./temp.txt

   cat /dev/null > ./cmd.txt
   while read line; do 
         #echo "$line"
         v_str="$line"
         v_str=${v_str/#${SOURCE_DIR}/"$TARGET_DIR"}
         #echo "${line} -> ${v_str}"
         echo "mkdir ${v_str}" | tee -a "./cmd.txt"
   done < <(cat ./temp.txt)
   chmod u+x ./cmd.txt; ./cmd.txt

   #### if necessery
   find "$TARGET_DIR" -type f -delete; find "$TARGET_DIR" -type d -delete

   function rcopy(){
   local v_file="$1"
   local v_cmd=""
   local v_path=""
 
   #[ ! -d "$SOURCE_DIR" ] && exit 3
   #[ ! -d "$TARGET_DIR" ] && exit 4
 
   if [ -f "$v_file" ]; then
      v_path=$(dirname "$v_file" )
      v_path=${v_path/#${SOURCE_DIR}/"$TARGET_DIR"}
      v_cmd="${RSYNC} ${ROPTIONS} \"$v_file\" \"${v_path}\""
      #echo "$v_cmd"
      eval "$v_cmd"
   else
      exit 4
   fi
   }
   export -f rcopy

   #### initial copy, making files at remote-site
   DOP="3"
   export ROPTIONS="-pogtD --progress --inplace --partial -4 -v --checksum --ignore-existing"
   time find "$SOURCE_DIR" -type f | xargs -n 1 -P "$DOP" -d "\n" -I {} -t bash -c rcopy\ \"\{\}\"
 
   find "$SOURCE_DIR" -type f | wc -l
   find "$TARGET_DIR" -type f | wc -l

   #### control
   cat /dev/null > ./temp.txt
   for i in $( find "$SOURCE_DIR" -type f ); do
       v_file=$( basename "$i" )
       v_path=$(dirname "$i" )
       v_path=${v_path/#${SOURCE_DIR}/"$TARGET_DIR"}
       v_file="${v_path}/${v_file}"
       #echo "$i $v_file"
       v_md5_1=$( md5sum "$i" | cut -f 1 -d " " )
       v_md5_2="-"
       [ -f "$v_file" ] && v_md5_2=$( md5sum "$v_file" | cut -f 1 -d " " )
       echo "$i $v_file $v_md5_1 $v_md5_2" >> ./temp.txt
   done
   
   cat ./temp.txt | wc -l
   cat ./temp.txt | awk '{if ( $3 != $4 ){ printf "%s %s\n", $1, $2; }}' | wc -l
   ```
   Т.е.: не останавливая кластер - откопировал всё, в онлайне.
   После остановки кластера - докопировал, только изменения и только от изменившихся файлов, из исходной директори, в целевую:
   ```shell
   DOP="3"
   export ROPTIONS="-pogtD --progress --inplace --partial -4 -v --checksum"
   time find "$SOURCE_DIR" -type f | xargs -n 1 -P "$DOP" -d "\n" -I {} -t bash -c rcopy\ \"\{\}\"
   ```
   ![6_4](/HomeWorks/Lesson6/6_4.png)
   В данном, случае - конечно разницы практически нет никакой.
   В условиях прода, когда речь будет идти о большом кол-ве и больших файлах - разница конечно будет и такого рода подход: инкрментальное докопирование - позволит значительно уменьшить время даунтайма.
4. После остановки субд - старую директорию: переименовал. В файле `/etc/postgresql/14/main/postgresql.conf` поправил параметр `data_directory`: задал целевую директорию
   Процесс остановки и запуска: ![6_5](/HomeWorks/Lesson6/6_5.png)
   Ошибка запуска, в системном журнале ОС-и, комментировалась так:
   ```
   Jul 22 13:29:20 postgresql1 postgresql@14-main[54748]: Removed stale pid file.
   Jul 22 13:29:20 postgresql1 postgresql@14-main[54748]: Error: /usr/lib/postgresql/14/bin/pg_ctl /usr/lib/postgresql/14/bin/pg_ctl star>
   Jul 22 13:29:20 postgresql1 postgresql@14-main[54748]: 2022-07-22 13:29:20.564 UTC [54767] FATAL:  data directory "/mnt/pgdata" has in>
   Jul 22 13:29:20 postgresql1 postgresql@14-main[54748]: 2022-07-22 13:29:20.564 UTC [54767] DETAIL:  Permissions should be u=rwx (0700)>
   Jul 22 13:29:20 postgresql1 postgresql@14-main[54748]: pg_ctl: could not start server
   Jul 22 13:29:20 postgresql1 postgresql@14-main[54748]: Examine the log output.
   ...
   ```
   Выполнил `chmod -R 700 /mnt/pgdata` и субд запустилась успешно.
   Запрос к контрольной таблице:
   ![6_6](/HomeWorks/Lesson6/6_6.png)

P.S.: позже понял что целевую директорию лучше было сделать такой: `mkdir -p /mnt/pgdata/14/main`
Т.е.: не ложить всё сразу в точку монтироваия.
Размер датаблока, увы, задаётся автоматически при инсталяции ПО и изменён быть не может.
Можно менять только при сборке пг из сорсов.
В оркале, в одном инстансе (кластер, в терминах пг) - можно создавать ts-ы, с разным размером датаблока и конфигурировать буферные кеши (то что в пг называется `shared_buffer`) под кеширование данных в разного размера датаблоках.
Т.е. можно подтачивать, тонко, субд под разную нагрузку.

Позанимался бенчмаркингом.
[Скрипт](/HomeWorks/Lesson6/benchmarking_arch.txt) для нагрузочного тестирования.
Сессия тестирования состоит из нескольких сетов тестов: 7 сетов.
Каждый сет - имеет лейбл, ярлык, или тэг, в общем - метку, по которой один сет можно отличить от другого.
В рамках одного сета выполняется несколько команд: `pgbench --client="$k" -r -l -t 1000 --no-vacuum "$DBNAME"`, где `k` пробегает значения: `for((k=1; k<20; k+=2))`
Описание сессий тестов.
1. Тэг `onedisk`: дефолтный кластер пг, только физ. компонента - вынесена в отдельный раздел фс, фс создана на отдельном диске.
   Команда создания кластера пг, здесь и далее: `pg_createcluster --datadir=/mnt/pgdata/14/main --logfile=/var/log/postgresql/postgresql-14-main.log --start --start-conf=auto 14 main`
2. Тэг `onedisk_wal-segsize_128`: условия предыдущего теста и, отличие - задан, по `--wal-segsize` больший размер файлов wal-логов, с 16М до 128M.
3. Тэг `twodisk_wal-segsize_128`: условия предыдущего теста и, отличие - создан, под индексы, отдельный  раздел фс, на отдельном дисковом уст-ве. 
   Т.е.: табличные данные - на одном дисковом уст-ве. Индексы к таблицам - на другом дисковом уст-ве.
4. Тэг `twodisk_wal-segsize_128_ssd`: условия предыдущего теста и, отличие - создана отдельная фс, на отдельном ssd-диске, под wal-логи: 
   ![6_7](/HomeWorks/Lesson6/6_7.png)
5. Тэг `twodisk_wal-segsize_128_ssd_wb64m`: условия предыдущего теста и, отличие - выставлен `wal_buffer=64MB`
6. Тэг `twodisk_wal-segsize_128_ssd_wb64m_cd100000`: условия предыдущего теста и, отличие - выставлен `commit_delay=100000` 
   Этот тест - прервал, данные по нему не стал сохранять и обрабатывать: показал очень низкий троутпут про тр-циям, порядка 100 tps;
   Вернул параметр `commit_delay` в дефолтное значение (закомментил, в `postgresql.conf` и перезапустил кластер).
7. Тэг `twodisk_wal-segsize_128_ssd_wb64m`: условия сессии #5 и, отличие - выставил `synchronous_commit = off`;
   Понятно что это, уже, откровенный размен отказоустойчивости на продуктивность, но, просто ради любопытства - посмотреть какой прирост tps это покажет.
8. Тэг `twodisk_wal-segsize_128_ssd_wb64m_scoff_fsoff`: условия предыдущего теста и, отличие - выставлен `fsync=off`, чего стесняться то. 
   Заодним посмотреть: если tps - значительно повыситься, относительно tps-а в условиях в предыдущей сессии, то значит фактором ограничивающим продуктовность бд, под данной нагрузкой, является не только и не столько продуктивность обработки редо-данных от транзакций, а продуктивность IO в перманентные структуры хранения данных.
   
Замечения возникшие в ходе бенчей:
1. Заметка к бенчмаркингу: не надо удалять прям все wal-логи. Ибо и, понятно почему, можно словить, при попытке перезапуска субд:
   ```
   2022-07-23 06:47:01.063 UTC [845] LOG:  starting PostgreSQL 14.4 (Ubuntu 14.4-1.pgdg20.04+1) on x86_64-pc-linux-gnu, compiled by gcc (Ubuntu 9.4.0-1ubuntu1~20.04.1) 9.4.0, 64-bit
   2022-07-23 06:47:01.064 UTC [845] LOG:  listening on IPv6 address "::1", port 5432
   2022-07-23 06:47:01.064 UTC [845] LOG:  listening on IPv4 address "127.0.0.1", port 5432
   2022-07-23 06:47:01.066 UTC [845] LOG:  listening on Unix socket "/var/run/postgresql/.s.PGSQL.5432"
   2022-07-23 06:47:01.070 UTC [846] LOG:  database system was shut down at 2022-07-22 19:14:13 UTC
   2022-07-23 06:47:01.070 UTC [846] LOG:  invalid primary checkpoint record
   2022-07-23 06:47:01.070 UTC [846] PANIC:  could not locate a valid checkpoint record
   2022-07-23 06:47:01.070 UTC [845] LOG:  startup process (PID 846) was terminated by signal 6: Aborted
   2022-07-23 06:47:01.070 UTC [845] LOG:  aborting startup due to startup process failure
   2022-07-23 06:47:01.071 UTC [845] LOG:  database system is shut down
   ```
   Имеет смысл выставить `archive_mode = off`, [пишут](https://dba.stackexchange.com/questions/252461/does-postgres-automatically-rotate-wal-files-out-pg-xlog-if-archive-mode-is-of) что:
   ```
   If archive_mode = off, PostgreSQL will delete old WAL files as soon as they are older than the latest checkpoint. 
   These checkpoints occur by default at least every 5 minutes, so there should never be many old WAL files around.

   If you set archive_mode = on, a WAL file are only deleted once archive_command has returned success for that file. An empty archive_command should always do that immediately.
   It is a tradition to set archive_command = '/bin/true' to indicate that you temporarily disabled archiving.
   ```
   Посмотреть значение конф-х параметров:
   ```shell
   [local]:5432 #postgres@postgres > select name, setting from pg_settings where name like '%archive%';
              name            |  setting
   ---------------------------+------------
    archive_cleanup_command   |
    archive_command           | (disabled)
    archive_mode              | off
    archive_timeout           | 0
    max_standby_archive_delay | 30000
   (5 rows)
   
   [local]:5432 #postgres@postgres *> commit;
   COMMIT
   [local]:5432 #postgres@postgres > show archive_mode;
    archive_mode
   --------------
    off
   (1 row)
   
   [local]:5432 #postgres@postgres *> commit;
   COMMIT
   [local]:5432 #postgres@postgres >
   ```
2. Стало интересно: как можно задать размер wal-лога. Файлики по 16Мб - это фу. Занятная [статья](https://habr.com/ru/company/okmeter/blog/421061/). 
   [Выясняется](https://www.postgresql.org/docs/14/wal-internals.html) что размер файлов wal-логов задаётся при создании кластера, по опции `--wal-segsize` и позднее не м.б. изменён.
   [Описание](https://www.postgresql.org/docs/14/wal-configuration.html) механизма работы журнализации транзакций
3. На уровне скл-сессии задать отложенный-пакетный режим обработки commit-ов, т.е., то что в пг, на уровне кластера, задаётся по `synchronous_commit = off` - нальзя.
4. Обработка данных от нагрузочного тестирования:
   ```sql
   create table metric_log(tag text, testnum int, clientnum int, tps float);
   commit;
   --for text-format: default delimiter is tab;
   copy metric_log from '/var/lib/postgresql/metric_log.txt' with (format text); 
   commit;
   
   create table cmd_hases(hash text, cmd text);
   commit;
   copy cmd_hases from '/var/lib/postgresql/cmd_hashes.txt' with (format text, delimiter ';');
   commit;
   
   create table cmd_latency(tag text, testnum int, latency float, hash text);
   commit;
   copy cmd_latency from '/var/lib/postgresql/cmd_latency.txt' with (format text, delimiter ' ');
   commit;
   
   copy (
   select 'onedisk' as tag, v.* 
   from (select clientnum, min(tps) as mintps, avg(tps) as avgtps, max(tps) as maxtps 
         from metric_log where tag='onedisk' 
         group by clientnum 
         order by clientnum asc) v
   union all
   select 'onedisk_wal-segsize_128' as tag, v.* 
   from (select clientnum, min(tps) as mintps, avg(tps) as avgtps, max(tps) as maxtps 
         from metric_log where tag='onedisk_wal-segsize_128' 
         group by clientnum 
         order by clientnum asc) v
   union all
   select 'twodisk_wal-segsize_128' as tag, v.* 
   from (select clientnum, min(tps) as mintps, avg(tps) as avgtps, max(tps) as maxtps 
         from metric_log 
         where tag='twodisk_wal-segsize_128' 
         group by clientnum order by clientnum asc) v
   union all
   select 'twodisk_wal-segsize_128_ssd' as tag, v.* 
   from (select clientnum, min(tps) as mintps, avg(tps) as avgtps, max(tps) as maxtps 
         from metric_log 
         where tag='twodisk_wal-segsize_128_ssd' 
         group by clientnum order by clientnum asc) v
   union all
   select 'twodisk_wal-segsize_128_ssd_wb64m' as tag, v.* 
   from (select clientnum, min(tps) as mintps, avg(tps) as avgtps, max(tps) as maxtps 
         from metric_log 
         where tag='twodisk_wal-segsize_128_ssd_wb64m' 
         group by clientnum order by clientnum asc) v
   union all
   select 'twodisk_wal-segsize_128_ssd_wb64m_scoff' as tag, v.* 
   from (select clientnum, min(tps) as mintps, avg(tps) as avgtps, max(tps) as maxtps 
         from metric_log 
         where tag='twodisk_wal-segsize_128_ssd_wb64m_scoff' 
         group by clientnum order by clientnum asc) v
   union all
   select 'twodisk_wal-segsize_128_ssd_wb64m_scoff_fsoff' as tag, v.* 
   from (select clientnum, min(tps) as mintps, avg(tps) as avgtps, max(tps) as maxtps 
         from metric_log 
         where tag='twodisk_wal-segsize_128_ssd_wb64m_scoff_fsoff' 
      group by clientnum order by clientnum asc) v;
   ```

Выводы:
1. Графики, с динамикой tps, от кол-ва клиентов, по сессиям:
   ![6_8](/HomeWorks/Lesson6/6_8.png)
   
   Разложение таблиц, индексов, wal-логов по разным дискам (по сути - разложение IO, по разным шпинделям), изменение размера wal-логов, wal-буфера: эффекта, практически, никакого не дало.
   Эффект дало качественное изменение выполнения IO на диск в wal-логи: когда был выключен sync-IO в wal-логи, по `synchronous_commit = off`;
   Ну.
   Мораль такая что, при транзакционной нагрузке - надо low-latency дисковый сторидж, под wal-логи.
   Also. 
   Выставление `fsync=off`, т.е. отключение выполнения базой сискола `fsync()`, после физических фрайтов бд (любых) (именно для режима выполнения IO-записей в wal-файлы есть отдельный пар-р `wal_sync_method` и он игнорится, если выставлено `fsync=off`) - практически никак не повыстило троутпут по tps-ам, относительно динамики троутпут-а в сессии тестов с `synchronous_commit = off`
   
   Значит, в этом нагрузочном тестировании основной фактор определяющий продуктивность субд - это качество работы её с дисковым сториджем где расположены wal-логи, именно - латенси на физ-запись в этот дисковый сторидж.
   В работу с дисками где лежат перманентные данные (таблицы/индесы) бд - вообще не упирается.
2. Интересен второй график.
   Данные по динамике троутпута по tps-у в двух, крайних, в смысле продуктивности, сессиях тестирования:
   ![6_9](/HomeWorks/Lesson6/6_9.png)
   
   Тот факт что, в обоих вариантах настроек субд, и при данном значении кол-ва клиентов, значения tps-а, гуляет вокруг своего среднего почти в два раза, толсто намекает что есть ещё, как минимум один, минорный фактор влияющий на пропускную способность субд по трназакциям.
   Примечательно что с увеличением степени параллелизма работы с субд: разброс вокруг среднего - значительно уменьшается.
   Ну.
   Вариантов тут два, не взаимоисключающих.
   Например, с повышением нагрузки (т.е.: кол-ва одновременно работающих клиентов) начинает более эффективно работать дисковая подсистема.
   Например настройки IO-шедулера начинают быть более эффективными.
   И/или навигация по блокам в фс, или ещё что. 
   И/или с повышением нагрузки начинает как то по другому работать ОС-евой менеджер виртуальной памяти.
   
   Как это уточнять: ну либо методом исключения, например вывести из работы IO-шедулер и/или фс и посмотреть что получится. 
   Но это - уже силшком, для рамок ДЗ и не уверен что пг - поддерживает работу с raw-девайсами.
   Либо трейсить работу серверных процессов субд, в тех режимах которые характеризуются большой волатильностью метрики продуктивности (tps-ом) вокруг среднего и догадываться, по временным затратам на сискол-ы и по набору вызываемых сисколов - это с чем идёт работа и как и во что упирается эта работа.
   Тоже: дао, по затратам плохо вписывающееся в рамки ДЗ.
   Ну либо есть ещё какой то вариант локализации проблем продуктивности пг-субд, про который я, пока что, не знаю.
   
[Экселька](/HomeWorks/Lesson6/Chart.xlsx) с графиками.
