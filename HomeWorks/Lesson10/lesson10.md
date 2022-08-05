 Занятные статьи: 
 1. [Basics of Tuning Checkpoints](https://www.enterprisedb.com/blog/basics-tuning-checkpoints) .
 2. [топик на стэковерфлоу](https://dba.stackexchange.com/questions/61822/what-happens-in-postgresql-checkpoint)
 3. [Checkpoint-статья на pgpedia](https://pgpedia.info/c/checkpoint.html) - тут упоминается файл `$PGDATA/global/pg_control` и функции для получения информации из него: `pg_control_checkpoint()`;
    Но, блин, это всё - про последний чекпойнт. А если надо (а оно - надо) знать когда именно были выполнены две последние контрольные точки.
    Есть, конечно, такая информация в логе самого пг-кластера.
    Так он, вообще говоря - ротироваться должен и будет, в условиях прода. 
    Во вторых ну, надо будет либо стандартизировать формат записией в этом логе, это как минимум. Ну: чтобы какой то скрипт(ы), которые из этого лога информацию берут - работали везде, на всех инсталяциях пг-баз, в орг-ции.
    А если надо будет ещё и из sql-скриптов брать информацию из этого лога - ну, тогда задавать ему csv-формат и select, на основе copy-команды psql-я.
4.  [pg_ls_waldir](https://pgpedia.info/p/pg_ls_waldir.html) - вообще занятный [список, там же](https://pgpedia.info/version-charts/file-system-functions.html).

1. ```
   Настройте выполнение контрольной точки раз в 30 секунд.
   ```
   ![10_1](/HomeWorks/Lesson10/10_1.png)
   ![10_2](/HomeWorks/Lesson10/10_2.png)
   Т.е.: чекпойнты логгируются в лог кластера, потому что уже было: `log_min_messages='debug1'`, с какого то из прошлых занятий.
   Дополнительно выставил `log_checkpoint='on'`
2. ```
   10 минут c помощью утилиты pgbench подавайте нагрузку.
   Измерьте, какой объем журнальных файлов был сгенерирован за это время. 
   Оцените, какой объем приходится в среднем на одну контрольную точку.
   Проверьте данные статистики: все ли контрольные точки выполнялись точно по расписанию. 
   Почему так произошло?
   ```
   Тестовая схема, в bmdb-базе: осталась с прошлого занятия:
   ```sql
   [local]:5432 #postgres@postgres > \c bmdb
   You are now connected to database "bmdb" as user "postgres".
   [local]:5432 #postgres@bmdb > SELECT 'pgbench_accounts' as item, count(*) as rows from pgbench_accounts
   bmdb-# union all
   bmdb-# SELECT 'pgbench_branches', count(*) as rows from pgbench_branches
   bmdb-# union all
   bmdb-# SELECT 'pgbench_branches', count(*) as rows from pgbench_history
   bmdb-# union all
   bmdb-# SELECT 'pgbench_tellers', count(*) as rows from pgbench_tellers;
          item       |  rows
   ------------------+---------
    pgbench_accounts | 2000000
    pgbench_branches |      20
    pgbench_branches |  775451
    pgbench_tellers  |     200
   (4 rows)
   
   [local]:5432 #postgres@bmdb >
   ```
   Выполнил, опять же из прошлого занятия:
   ```shell
   export DBNAME="bmdb"
   export DBUSER="postgres"
   export PSQL="/usr/bin/psql"
   export PGBENCH="/usr/bin/pgbench"
   export VERBOSE="1"
   export LOGFILE="/tmp/logfile.txt"
   export PGBENCH_DIR="$HOME/pgbench_dir"; [ ! -d "$PGBENCH_DIR" ] && mkdir -p "$PGBENCH_DIR"
   export METADATADB="postgres"
   export METADATADBUSER="postgres"
   export TESTDURATION="600"
   export INTERVAL="60"
   find $PGBENCH_DIR -type f -delete
   psql -c "select * from pg_ls_waldir() ORDER BY name;" 
   date
   $PGBENCH --client=8 --time=${TESTDURATION} --username=${DBUSER} --log --log-prefix=${PGBENCH_DIR}/temp --aggregate-interval=${INTERVAL} "$DBNAME"
   date
   psql -c "select count(*) from pg_ls_waldir()e;"
   ```
   ![10_3](/HomeWorks/Lesson10/10_3.png)
   ![10_4](/HomeWorks/Lesson10/10_4.png)
   ![10_5](/HomeWorks/Lesson10/10_5.png)
   Ну. 
   Получается что `tpc=749` и генерация wal-логов: `~6.4Мб/сек`
   В логе пг-кластера такие записи:
   ![10_6](/HomeWorks/Lesson10/10_6.png)
   Интересные данные в строке `LOG:  checkpoint complete`, про продуктивность записи дарти-блоков в файлы.
   ```
   write=26.855 s, sync=0.006 s, total=26.916 s; sync files=5, longest=0.003 s, average=0.002 s; distance=94242 kB, estimate=101576 kB
   ```
   write-значение, это похоже что время которое задаётся по `checkpoint_completion_target`
   synс-значение: это, видимо, время выполнения сискола `fcync()`
   `longest,average` - это понятно что, файлов несоклько штук, куда пишутся дарти-блоки, во время чекпойнта, вот по ним - статистика.
   `distance,estimate` - не понял, что такое.
   На протяжении всего времени теста это write-значение не перекрывало 30секунд - интервал между чекпйонтами.
   Ну. Т.е.: процедуры выполнения чекпонтов - не перекрывались, во времени.
   ```shell
   postgres@postgresql1:/home/student$ grep "LOG:  checkpoint complete:"  $PGLOG | sed -r "s/UTC\W+\[[0-9\-]+\]//" | sed -r "s/ LOG:  checkpoint complete: wrote\W+[0-9]+\W+buffers \([0-9\.]+%\);\W+[0-9]+ WAL file\(s\) added, [0-9]+ removed, [0-9]+ recycled;//" | awk '{printf "%d:%s\n", NR, $0;}' | column -t
   1:2022-08-05   11:18:54.144  write=26.658s,  sync=0.024s,  total=26.783s;  sync  files=18,  longest=0.010s,  average=0.002s;  distance=48450   kB,  estimate=48450   kB
   2:2022-08-05   11:19:24.220  write=26.913s,  sync=0.016s,  total=27.076s;  sync  files=5,   longest=0.011s,  average=0.004s;  distance=108679  kB,  estimate=108679  kB
   3:2022-08-05   11:19:54.177  write=26.841s,  sync=0.032s,  total=26.955s;  sync  files=5,   longest=0.017s,  average=0.007s;  distance=74405   kB,  estimate=105252  kB
   4:2022-08-05   11:20:24.167  write=26.885s,  sync=0.017s,  total=26.987s;  sync  files=5,   longest=0.011s,  average=0.004s;  distance=89573   kB,  estimate=103684  kB
   5:2022-08-05   11:20:54.191  write=26.853s,  sync=0.029s,  total=27.022s;  sync  files=5,   longest=0.010s,  average=0.006s;  distance=93190   kB,  estimate=102635  kB
   6:2022-08-05   11:21:24.173  write=26.816s,  sync=0.016s,  total=26.979s;  sync  files=5,   longest=0.010s,  average=0.004s;  distance=89355   kB,  estimate=101307  kB
   7:2022-08-05   11:21:54.167  write=26.871s,  sync=0.025s,  total=26.993s;  sync  files=5,   longest=0.009s,  average=0.005s;  distance=90903   kB,  estimate=100266  kB
   8:2022-08-05   11:22:24.164  write=26.877s,  sync=0.022s,  total=26.996s;  sync  files=5,   longest=0.015s,  average=0.005s;  distance=88228   kB,  estimate=99062   kB
   9:2022-08-05   11:22:54.171  write=26.845s,  sync=0.027s,  total=27.005s;  sync  files=5,   longest=0.010s,  average=0.006s;  distance=90386   kB,  estimate=98195   kB
   10:2022-08-05  11:23:24.096  write=26.816s,  sync=0.018s,  total=26.924s;  sync  files=5,   longest=0.011s,  average=0.004s;  distance=98343   kB,  estimate=98343   kB
   11:2022-08-05  11:23:54.106  write=26.898s,  sync=0.019s,  total=27.007s;  sync  files=5,   longest=0.010s,  average=0.004s;  distance=89678   kB,  estimate=97476   kB
   12:2022-08-05  11:24:24.095  write=26.872s,  sync=0.018s,  total=26.986s;  sync  files=5,   longest=0.011s,  average=0.004s;  distance=94272   kB,  estimate=97156   kB
   13:2022-08-05  11:24:54.154  write=26.929s,  sync=0.033s,  total=27.058s;  sync  files=5,   longest=0.018s,  average=0.007s;  distance=78570   kB,  estimate=95297   kB
   14:2022-08-05  11:25:24.107  write=26.831s,  sync=0.023s,  total=26.950s;  sync  files=5,   longest=0.015s,  average=0.005s;  distance=91181   kB,  estimate=94885   kB
   15:2022-08-05  11:25:54.109  write=26.873s,  sync=0.028s,  total=27.001s;  sync  files=6,   longest=0.014s,  average=0.005s;  distance=87960   kB,  estimate=94193   kB
   16:2022-08-05  11:26:24.095  write=26.865s,  sync=0.024s,  total=26.984s;  sync  files=5,   longest=0.012s,  average=0.005s;  distance=86813   kB,  estimate=93455   kB
   17:2022-08-05  11:26:54.182  write=26.911s,  sync=0.031s,  total=27.084s;  sync  files=5,   longest=0.019s,  average=0.006s;  distance=66104   kB,  estimate=90720   kB
   18:2022-08-05  11:27:24.164  write=26.866s,  sync=0.020s,  total=26.980s;  sync  files=5,   longest=0.012s,  average=0.004s;  distance=104584  kB,  estimate=104584  kB
   19:2022-08-05  11:27:54.111  write=26.824s,  sync=0.031s,  total=26.948s;  sync  files=5,   longest=0.014s,  average=0.006s;  distance=82653   kB,  estimate=102391  kB
   20:2022-08-05  11:28:24.031  write=26.855s,  sync=0.006s,  total=26.916s;  sync  files=5,   longest=0.003s,  average=0.002s;  distance=94242   kB,  estimate=101576  kB
   postgres@postgresql1:/home/student$
   ```
   Все выполнения чекпойнтов делались в 54-ю и 24-ю секунды, т.е.: с шагом в 30сек, как и задано по конфигурации.
3. ```
   Сравните tps в синхронном/асинхронном режиме утилитой pgbench. Объясните полученный результат.
   ```
   Ну. Понял так что речь идёт о `synchronous_commit='off'`
   Включил асинхронный режим выполнения коммитов:
   ```sql
   [local]:5432 #postgres@postgres > alter system set synchronous_commit='off';
   ALTER SYSTEM
   [local]:5432 #postgres@postgres > select pg_reload_conf();
    pg_reload_conf
   ----------------
    t
   (1 row)
   
   [local]:5432 #postgres@postgres > show synchronous_commit;
    synchronous_commit
   --------------------
    off
   (1 row)
   
   [local]:5432 #postgres@postgres > \! date
   Fri 05 Aug 2022 12:22:21 PM UTC
   ```
   Запустил выполнение теста:
   ![10_7](/HomeWorks/Lesson10/10_7.png)
   ![10_8](/HomeWorks/Lesson10/10_8.png)
   ![10_9](/HomeWorks/Lesson10/10_9.png)
   Т.е.: `tps = 2575` и генерация wal-логов: `~15.5Мб.сек`
   В записях про чекпойнты, в логе кластера, принципиальных изменений нет, кроме, конечно, кол-ва обработанных дарти-буферов и релевантных, к этой количественно возросшей активности, затрат.
   ![10_17](/HomeWorks/Lesson10/10_17.png)
   Из деградации - подросли, кратно, `longest` значения, времени синкания дарти-блоков в датафайлы.
   ```shell
   grep "LOG:  checkpoint complete:"  $PGLOG | sed -r "s/UTC\W+\[[0-9\-]+\]//" | sed -r "s/ LOG:  checkpoint complete: wrote\W+[0-9]+\W+buffers \([0-9\.]+%\);\W+[0-9]+ WAL file\(s\) added, [0-9]+ removed, [0-9]+ recycled;//" | awk '{printf "%d:%s\n", NR, $0;}' | column -t
   21:2022-08-05  12:25:27.124  write=26.094s,  sync=0.013s,  total=26.192s;  sync  files=14,  longest=0.006s,  average=0.001s;  distance=222089  kB,  estimate=222089  kB
   22:2022-08-05  12:25:57.420  write=27.126s,  sync=0.080s,  total=27.294s;  sync  files=5,   longest=0.061s,  average=0.016s;  distance=236484  kB,  estimate=236484  kB
   23:2022-08-05  12:26:27.163  write=26.610s,  sync=0.011s,  total=26.743s;  sync  files=6,   longest=0.005s,  average=0.002s;  distance=227452  kB,  estimate=235581  kB
   24:2022-08-05  12:26:57.143  write=26.896s,  sync=0.012s,  total=26.978s;  sync  files=6,   longest=0.005s,  average=0.002s;  distance=205505  kB,  estimate=232573  kB
   25:2022-08-05  12:27:27.254  write=26.920s,  sync=0.011s,  total=27.108s;  sync  files=6,   longest=0.006s,  average=0.002s;  distance=233496  kB,  estimate=233496  kB
   26:2022-08-05  12:27:57.218  write=26.768s,  sync=0.022s,  total=26.962s;  sync  files=5,   longest=0.010s,  average=0.005s;  distance=223820  kB,  estimate=232529  kB
   27:2022-08-05  12:28:27.118  write=26.789s,  sync=0.010s,  total=26.898s;  sync  files=6,   longest=0.006s,  average=0.002s;  distance=241305  kB,  estimate=241305  kB
   28:2022-08-05  12:28:57.142  write=26.892s,  sync=0.017s,  total=27.022s;  sync  files=6,   longest=0.005s,  average=0.003s;  distance=228278  kB,  estimate=240002  kB
   29:2022-08-05  12:29:27.124  write=26.863s,  sync=0.010s,  total=26.980s;  sync  files=6,   longest=0.006s,  average=0.002s;  distance=237778  kB,  estimate=239780  kB
   30:2022-08-05  12:29:57.114  write=26.877s,  sync=0.011s,  total=26.988s;  sync  files=5,   longest=0.006s,  average=0.003s;  distance=234775  kB,  estimate=239279  kB
   31:2022-08-05  12:30:27.312  write=26.917s,  sync=0.020s,  total=27.196s;  sync  files=5,   longest=0.014s,  average=0.004s;  distance=236627  kB,  estimate=239014  kB
   32:2022-08-05  12:30:57.187  write=26.750s,  sync=0.031s,  total=26.875s;  sync  files=6,   longest=0.022s,  average=0.006s;  distance=219193  kB,  estimate=237032  kB
   33:2022-08-05  12:31:27.124  write=26.812s,  sync=0.035s,  total=26.936s;  sync  files=5,   longest=0.033s,  average=0.007s;  distance=229826  kB,  estimate=236311  kB
   34:2022-08-05  12:31:57.153  write=26.900s,  sync=0.034s,  total=27.029s;  sync  files=6,   longest=0.027s,  average=0.006s;  distance=205569  kB,  estimate=233237  kB
   35:2022-08-05  12:32:27.253  write=26.906s,  sync=0.022s,  total=27.098s;  sync  files=6,   longest=0.014s,  average=0.004s;  distance=226600  kB,  estimate=232573  kB
   36:2022-08-05  12:32:57.159  write=26.768s,  sync=0.033s,  total=26.903s;  sync  files=6,   longest=0.020s,  average=0.006s;  distance=215498  kB,  estimate=230866  kB
   37:2022-08-05  12:33:27.214  write=26.848s,  sync=0.028s,  total=27.052s;  sync  files=6,   longest=0.023s,  average=0.005s;  distance=230056  kB,  estimate=230785  kB
   38:2022-08-05  12:33:57.162  write=26.813s,  sync=0.037s,  total=26.946s;  sync  files=7,   longest=0.026s,  average=0.006s;  distance=234849  kB,  estimate=234849  kB
   39:2022-08-05  12:34:27.186  write=26.869s,  sync=0.023s,  total=27.022s;  sync  files=5,   longest=0.018s,  average=0.005s;  distance=206174  kB,  estimate=231981  kB
   40:2022-08-05  12:34:57.115  write=26.867s,  sync=0.009s,  total=26.927s;  sync  files=6,   longest=0.004s,  average=0.002s;  distance=227589  kB,  estimate=231542  kB
   ```
   Т.е. в работе самого чекпойнта - ничего не поменялось, кроме объёма работы/ед.времени;
   Повышение продуктивности по tps-ам и кол-ва дарти-блоков связано с значительным уменьшением времени обслуживания базой коммит-ов, при `synchronous_commit='off'`
   Журнальные данные, по закоммичиваемой тр-ции, пишутся, из вал-буфера в текущий вал-лог без выполнения сискола `fcync()`
   Т.е. это запись в файловый кеш ОС-и, а не в вал-лог на диске.
4. ```
   Создайте новый кластер с включенной контрольной суммой страниц. 
   Создайте таблицу. 
   Вставьте несколько значений. 
   Выключите кластер. 
   Измените пару байт в таблице. 
   Включите кластер и сделайте выборку из таблицы. 
   Что и почему произошло? 
   как проигнорировать ошибку и продолжить работу?
   ```
   Пересоздал кластер.
   ```shell
   pg_createcluster --start --start-conf=auto 14 main -- --no-sync --data-checksums
   ```
   ![10_10](/HomeWorks/Lesson10/10_10.png)
   Выполнил:
   ```shell
   select name, setting from pg_settings where name in ('data_checksums','ignore_checksum_failure') order by name;
   create table testtab(col1 int);
   begin;
   insert into testtab(col1) values(1);
   insert into testtab(col1) values(2);
   insert into testtab(col1) values(3);
   commit;
   select * from testtab;
   select * from pg_relation_filepath('testtab');
   ```
   ![10_13](/HomeWorks/Lesson10/10_13.png)
   В отдельном screen-экране, в vim-е, поменял пару символов в файле.
   md5sum-хеш файла поменялся, после правки:
   ![10_14](/HomeWorks/Lesson10/10_14.png)
   Запуск пг-кластера, попытка опроса таблицы:
   ![10_15](/HomeWorks/Lesson10/10_15.png)
   Ошибка в логе кластера:
   ```shell
   2022-08-05 13:38:26.817 UTC [2237] LOG:  database system is ready to accept connections
   2022-08-05 13:38:57.167 UTC [2258] postgres@postgres WARNING:  page verification failed, calculated checksum 41385 but expected 43263
   2022-08-05 13:38:57.168 UTC [2258] postgres@postgres ERROR:  invalid page in block 0 of relation base/13760/16384
   2022-08-05 13:38:57.168 UTC [2258] postgres@postgres STATEMENT:  FETCH FORWARD 100 FROM _psql_cursor
   2022-08-05 13:38:57.168 UTC [2258] postgres@postgres ERROR:  current transaction is aborted, commands ignored until end of transaction block
   2022-08-05 13:38:57.168 UTC [2258] postgres@postgres STATEMENT:  CLOSE _psql_cursor
   ```
   Выполнил:
   ```sql
   alter system set ignore_checksum_failure='on';
   select pg_reload_conf();
   ```
   ![10_16](/HomeWorks/Lesson10/10_16.png)
   
