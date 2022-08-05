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
   1:2022-08-05 11:18:54.144  write=26.658 s, sync=0.024 s, total=26.783 s; sync files=18, longest=0.010 s, average=0.002 s; distance=4845
   0 kB, estimate=48450 kB
   2:2022-08-05 11:19:24.220  write=26.913 s, sync=0.016 s, total=27.076 s; sync files=5, longest=0.011 s, average=0.004 s; distance=10867
   9 kB, estimate=108679 kB
   3:2022-08-05 11:19:54.177  write=26.841 s, sync=0.032 s, total=26.955 s; sync files=5, longest=0.017 s, average=0.007 s; distance=74405
    kB, estimate=105252 kB
   4:2022-08-05 11:20:24.167  write=26.885 s, sync=0.017 s, total=26.987 s; sync files=5, longest=0.011 s, average=0.004 s; distance=89573
    kB, estimate=103684 kB
   5:2022-08-05 11:20:54.191  write=26.853 s, sync=0.029 s, total=27.022 s; sync files=5, longest=0.010 s, average=0.006 s; distance=93190
    kB, estimate=102635 kB
   6:2022-08-05 11:21:24.173  write=26.816 s, sync=0.016 s, total=26.979 s; sync files=5, longest=0.010 s, average=0.004 s; distance=89355
    kB, estimate=101307 kB
   7:2022-08-05 11:21:54.167  write=26.871 s, sync=0.025 s, total=26.993 s; sync files=5, longest=0.009 s, average=0.005 s; distance=90903
    kB, estimate=100266 kB
   8:2022-08-05 11:22:24.164  write=26.877 s, sync=0.022 s, total=26.996 s; sync files=5, longest=0.015 s, average=0.005 s; distance=88228
    kB, estimate=99062 kB
   9:2022-08-05 11:22:54.171  write=26.845 s, sync=0.027 s, total=27.005 s; sync files=5, longest=0.010 s, average=0.006 s; distance=90386
    kB, estimate=98195 kB
   10:2022-08-05 11:23:24.096  write=26.816 s, sync=0.018 s, total=26.924 s; sync files=5, longest=0.011 s, average=0.004 s; distance=9834
   3 kB, estimate=98343 kB
   11:2022-08-05 11:23:54.106  write=26.898 s, sync=0.019 s, total=27.007 s; sync files=5, longest=0.010 s, average=0.004 s; distance=8967
   8 kB, estimate=97476 kB
   12:2022-08-05 11:24:24.095  write=26.872 s, sync=0.018 s, total=26.986 s; sync files=5, longest=0.011 s, average=0.004 s; distance=9427
   2 kB, estimate=97156 kB
   13:2022-08-05 11:24:54.154  write=26.929 s, sync=0.033 s, total=27.058 s; sync files=5, longest=0.018 s, average=0.007 s; distance=7857
   0 kB, estimate=95297 kB
   14:2022-08-05 11:25:24.107  write=26.831 s, sync=0.023 s, total=26.950 s; sync files=5, longest=0.015 s, average=0.005 s; distance=9118
   1 kB, estimate=94885 kB
   15:2022-08-05 11:25:54.109  write=26.873 s, sync=0.028 s, total=27.001 s; sync files=6, longest=0.014 s, average=0.005 s; distance=8796
   0 kB, estimate=94193 kB
   16:2022-08-05 11:26:24.095  write=26.865 s, sync=0.024 s, total=26.984 s; sync files=5, longest=0.012 s, average=0.005 s; distance=8681
   3 kB, estimate=93455 kB
   17:2022-08-05 11:26:54.182  write=26.911 s, sync=0.031 s, total=27.084 s; sync files=5, longest=0.019 s, average=0.006 s; distance=6610
   4 kB, estimate=90720 kB
   18:2022-08-05 11:27:24.164  write=26.866 s, sync=0.020 s, total=26.980 s; sync files=5, longest=0.012 s, average=0.004 s; distance=1045
   84 kB, estimate=104584 kB
   19:2022-08-05 11:27:54.111  write=26.824 s, sync=0.031 s, total=26.948 s; sync files=5, longest=0.014 s, average=0.006 s; distance=8265
   3 kB, estimate=102391 kB
   postgres@postgresql1:/home/student$
   ```
