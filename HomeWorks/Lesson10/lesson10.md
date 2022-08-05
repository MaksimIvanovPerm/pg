 Занятные статьи: 
 1. [Basics of Tuning Checkpoints](https://www.enterprisedb.com/blog/basics-tuning-checkpoints) .
 2. [топик на стэковерфлоу](https://dba.stackexchange.com/questions/61822/what-happens-in-postgresql-checkpoint)
 3. [Checkpoint-статья на pgpedia](https://pgpedia.info/c/checkpoint.html) - тут упоминается файл `$PGDATA/global/pg_control` и функции для получения информации из него: `pg_control_checkpoint()`;
    Но, блин, это всё - про последний чекпойнт. А если надо (а оно - надо) знать когда именно были выполнены две последние контрольные точки.
    Есть, конечно, такая информация в логе самого пг-кластера.
    Так он, вообще говоря - ротироваться должен и будет, в условиях прода. 
    Во вторых ну, надо будет либо стандартизировать формат записией в этом логе, это как минимум. Ну: чтобы какой то скрипт(ы), которые из этого лога информацию берут - работали везде, на всех инсталяциях пг-баз, в орг-ции.
    А если надо будет ещё и из sql-скриптов брать информацию из этого лога - ну, тогда задавать ему csv-формат и select, на основе copy-команды psql-я.
    Какая то боль сплошная, этот пг - как эти костыли, из палок и синей изоленты, можно считать продакшен-реди решением. 
    `No pain, no gain`
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
   postgres@postgresql1:/home/student$ grep "LOG:  checkpoint complete:"  $PGLOG | sed -r "s/UTC\W+\[[0-9\-]+\]//" | sed -r "s/ LOG:  chec
   kpoint complete: wrote\W+[0-9]+\W+buffers \([0-9\.]+%\);\W+[0-9]+ WAL file\(s\) added, [0-9]+ removed, [0-9]+ recycled;//" | awk '{prin
   tf "%d:%s\n", NR, $0;}' | more
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
   Лог кластера: 
