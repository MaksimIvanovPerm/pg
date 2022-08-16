 
Полезные статьи:
1. [статья про настройку памяти, sysctl для пг](https://habr.com/ru/post/458860/) - комментарии на порядок полезнее самой статьи.
   [официоз от пг-комьюнити](https://www.postgresql.org/docs/current/kernel-resources.html)
3. [референс]([https://www.postgresql.org/docs/current/kernel-resources.html](https://www.kernel.org/doc/html/latest/admin-guide/sysctl/index.html)) по параметрам линукс-ядра.
4. [прикольная справка по параметрам конф-ции пг](https://postgresqlco.nf/doc/ru/param/effective_cache_size/)
5. Отличная вещь для пг, прямо таки - awr-like approach [pg_profiler](https://github.com/zubkov-andrei/pg_profile)
6. [Шикарная статья](https://habr.com/ru/company/postgrespro/blog/466199/), про блокировки в памяти, всё как в оракле. В общем то - почему должно быть по другому, механизмы, среда, цели работы - те же.
   Вообще [весь набор статей](https://habr.com/ru/company/postgrespro/blog/458186/) от пгпро, на хабре - отличный экскурс в архитектуру и механику работы пг.

Заметки по установка `pg_prfiler`:
1. ```shell
   sudo apt install postgresql-contrib git
   ```
2. От ОС-аккаунта `postgres`:
   ```shell
   cd ~
   wget -O pg_profile.tar.gz https://github.com/zubkov-andrei/pg_profile/releases/download/0.3.6/pg_profile--0.3.6.tar.gz
   tar xzf pg_profile.tar.gz --directory $(pg_config --sharedir)/extension
   psql << __EOF__
   show search_path;
   CREATE EXTENSION dblink;
   CREATE EXTENSION pg_stat_statements;
   CREATE EXTENSION pg_profile;
   \dx
   alter system set shared_preload_libraries='pg_stat_statements';
   #parameter "shared_preload_libraries" cannot be changed without restarting the server
   __EOF__
   pg_ctlcluster 14 main restart
   psql -c "select name, setting from pg_catalog.pg_settings where name='shared_preload_libraries';"
   ```
   Должно сказать:
   ```sql
   [local]:5432 #postgres@postgres > \dx
                                            List of installed extensions
           Name        | Version |   Schema   |                              Description
   --------------------+---------+------------+------------------------------------------------------------------------
    dblink             | 1.2     | public     | connect to other PostgreSQL databases from within a database
    pg_profile         | 0.3.6   | public     | PostgreSQL load profile repository and report builder
    pg_stat_statements | 1.9     | public     | track planning and execution statistics of all SQL statements executed
   ```
3. Явно добавлять локальный кластер в конфигурацию pg_profiler-а не нужно: `Once installed, extension will create one enabled local server - this is for cluster, where extension is installed.`
   Посмотреть списки зарегестрированных кластеров, сэмплов (то что в oracle-субд называется: `awr snapshot`), сгенерировать простой отчёт (есть ещё дифференциальный):
   ```shell
   psql -c "select show_servers();"
   psql -c "select show_samples();"
   
   psql -Aqtc "SELECT get_report_latest();" -o report_latest.html
   v_bsample="4"
   v_esample="5"
   v_desc="Report for ${v_bsample}_${v_esample} samples"
   psql -Aqtc "SELECT get_report(${v_bsample}, ${v_esample}, '${v_desc}');" -o report_${v_bsample}_${v_esample}.html
   ```
   Генерятся, почему то, принципиально только в html-формате.
   Примеры отчётов - будут ниже.
   Фреймворка для регулярного выполнения задач в пг: нет.
   Поэтому - кронтабом, заготовка: 
   ```shell
   */15 * *   *   *     [ -f "/var/lib/postgresql/pg_profile/make_snap.sh" ] && /var/lib/postgresql/pg_profile/make_snap.sh 1>/dev/null 2>&1
   ```
   [make_snap.sh](/HomeWorks/Lesson11/make_snap.sh)
4. P.S. только в самом финале работ [углядел](https://github.com/zubkov-andrei/pg_profile/blob/master/doc/pg_profile.md) что надо делать
   ```sql
   track_activities = on
   track_counts = on
   track_io_timing = on
   track_wal_io_timing = on      # Since Postgres 14
   track_functions = all/pl
   ```
   весьма досадно, что пропустил такой важный момент(((((
   
Заметки по `sysbench`:
[https://github.com/akopytov/sysbench](https://github.com/akopytov/sysbench)
Но, в убунту, сильно проще, если устраивает версия из стандартного репозитория:
```shell
apt install sysbench
sysbench --version=on # sysbench 1.0.18
```
Доустановка lua-надстройки, дающей именно TPC-C-тест:
```shell
mkdir ~/tpcc
cd ~/tpcc
git clone https://github.com/Percona-Lab/sysbench-tpcc
cd ./sysbench-tpcc/
psql -c "ALTER USER postgres PASSWORD 'qazxsw123';"
```
Подсмотрел [тут](https://www.percona.com/blog/2018/06/15/tuning-postgresql-for-sysbench-tpcc/), как и что дальше.
Создание табличной модели под tpc-c-тест, выполнение теста, удаление табличной модели:
```shell
./tpcc.lua --pgsql-host=localhost --pgsql-user=postgres --pgsql-db=postgres --pgsql-password="qazxsw123" --time=60 --threads=2 --report-interval=10 --tables=10 --scale=2 --use_fk=0  --trx_level=RC --db-driver=pgsql prepare
# psql -U postgres -d postgres -c "select table_name, pg_relation_size(quote_ident(table_name)) from information_schema.tables where table_schema = 'public' order by 2 desc;"

./tpcc.lua --pgsql-host=localhost --pgsql-user=postgres --pgsql-db=postgres --pgsql-password="qazxsw123" --time=300 --threads=8 --report-interval=60 --tables=10 --scale=2 --use_fk=0  --trx_level=RC --db-driver=pgsql run | tee -a  /var/lib/postgresql/tpcc/sysbench-tpcc/result.txt

./tpcc.lua --pgsql-host=localhost --pgsql-user=postgres --pgsql-db=postgres --pgsql-password="qazxsw123" --threads=1 --tables=10 --db-driver=pgsql cleanup
```
Табличная модель получается, в сравнении с тем что строит `pgbench`, значительно более интересная, для нагрузочного тестирования.

Формулировка ДЗ:
```
настроить кластер PostgreSQL на максимальную производительность не обращая внимание на возможные проблемы с надежностью в случае аварийной перезагрузки виртуальной машины.
нагрузить кластер через утилиту https://github.com/Percona-Lab/sysbench-tpcc (требует установки https://github.com/akopytov/sysbench)
написать какого значения tps удалось достичь, показать какие параметры в какие значения устанавливали и почему
```
Ну. 
В техническом смысле - полная копия ДЗ к 8-й лекции.
Только что, к текущему занятию, рассмотрено уже больше механизмов в архитектуре пг, т.е. можно, и нужно "крутить" больше настроечных параметров пг.
И нагрузка создаётся `sysbench`, а не `pgbench`

О исходных.
Табличная модель, которую построил `tpcc.lua` - получилась размером 1.6Гб.

К текущему занятию прошли такие архитектурные темы как: шаред-буффер, wal-подсистема, вакуум/автовакуум, чекпойнты.
Поэтому, с одной стороны, исходя  из того что размер тестовой табличной схемы и нагрузка предполагается более-менее серьёзной: решил что пора уже отстроить сервер субд - более-менее нормально.
Т.е.: с конфигурацией больших страниц, с конфигурацией ОС-и, как минимум - vm-менеджера.
С варьированием большего кол-ва настроечных параметров и в больших диапазонах.

С другой стороны, опять же - все те же рассуждения что и в ДЗ к 8-й теме, приводят к тем же выводам: надо автомат и оптимизационный алгорим - пусть ищет, спортивно, какой вариант настройки даст большую и более качественную продуктивность.
Большую и более качественную: значит максимально возможную и наиболее стабильную динамику значений tps, поскльку tpcc-тест: это oltp;

Подготовка сервера.
Сервер сделал таким: 

![11_1](/HomeWorks/Lesson11/11_1.png)

После увеличения ресурсов сервера решил что будет интересно посмотреть - как оно работает в дефаултах и без подстройки ОС-и под пг.
А потом, после конфигурации больших страниц, ОС-и, подбора параметров - сравнить.

Репорт от tppc.lua-скрипта: [result.txt](/HomeWorks/Lesson11/result.txt)

pg_profiler-отчёт: [report_4_5.html](https://htmlpreview.github.io/?https://github.com/MaksimIvanovPerm/pg/blob/main/HomeWorks/Lesson11/report_4_5.html)

Затем:
1. Настройка и применение `sysctl.conf`:
   ```shell
   cat < __EOF__ >> /etc/sysctl.conf
   kernel.randomize_va_space=0
   fs.aio-max-nr=1048576
   fs.file-max=6815744
   vm.nr_hugepages=1280 #2.5Gb
   kernel.shmmax=2818572288
   kernel.shmmni=4096
   # getconf -a | grep "PAGE_SIZE"
   # (shmmax/PAGE_SIZE)
   kernel.shmall=688128
   vm.swappiness = 5
   __EOF__
   
   sysctl -p /etc/sysctl.conf
   ```
   Отключить инфернальное зло - THP, в убунту просто:
   ```shell
   apt install libhugetlbfs-bin
   id postgres | egrep -o "gid=[0-9]+\(postgres\)"
   hugeadm --set-shm-group=116
   echo "vm.hugetlb_shm_group=116" >> "/etc/sysctl.conf"
   hugeadm --thp-never
   ```
   Also и на всякий случай прописал в конфиг груб-загрузчика `transparent_hugepages=never`
   Рестартанул вм.
   Also, в проде, с настоящей железкой, чем уверен что, по хорошему то - надо было бы ещё поварьировать посмотреть на эффект от разных стратегий управления грязными страницами vm-менеджером, посмотреть на эффект от выставления разных io-шедулеров.
   Но, два момента. 
   Это уже выполнение действий от рута.
   А мне яндекс-вм не даёт, от postgres-а, делать sudo-команды, поправить `/etc/sudoers` - что то не помню: то ли не даёт, то ли что, точно помню что пробовал.
   Ну и переписывать код, наработанный в ДЗ к 8-й теме, под его выполнение из под рут-а: совсем лениво.
   Второе - всей чуйкой чую что YC - поредоставляет зашейпированные ресурсы, эксплуатационные качества которых будут значительно отличатся от качеств настоящей железки.
2. ОС-лимиты:
   ```shell
   cat << __EOF__ > /etc/security/limits.conf
   # Число открытых файлов
   postgres           soft    nofile          unlimited
   postgres           hard    nofile          unlimited
   # Число процессов Oracle
   postgres           soft    nproc           unlimited
   postgres           hard    nproc           unlimited
   # ОЗУ
   postgres           soft    memlock         unlimited
   postgres           hard    memlock         unlimited
   # Размер core-файлов в килобайтах
   postgres           soft    core            unlimited
   postgres           hard    core            unlimited
   # stack size
   postgres           soft    stack           unlimited
   postgres           hard    stack           unlimited
   __EOF__
   ```
3. Решил варьировать такие и в таких диапазонах, пг-параметры:
   | parameter | range | note |
   | --------- | ----- | ---- |
   | autovacuum_analyze_scale_factor | [0.01, 0.9] | float |
   |autovacuum_analyze_threshold|[50, 5000]| int|
   |autovacuum_max_workers|[1,4]| int|
   |autovacuum_naptime|[1,180]| int|
   |autovacuum_vacuum_scale_factor|[0.01, 0.9]| float|
   |autovacuum_vacuum_threshold|[50, 5000]| int|
   |maintenance_work_mem|[4096, 131072]| int (4-128Mb)|
   |shared_buffers|[16384, 163840]| int (128-1280Mb)|
   |wal_buffers|[2048, 20480]| int (16-160Mb)|
   |work_mem|[64, 40960]| int (40Мб; 400Мб)|
   |wal_compression|[1, 4]| int (<=2: off, >2: on)|
   |bgwriter_delay|[10, 10000]| int|
   |bgwriter_lru_maxpages|[100, 100000]| int|
   |checkpoint_completion_target|[0.1, 0.9]| float|
   |checkpoint_timeout|[30, 600]| int|
   |commit_delay|[0, 100000]| int|
   |commit_siblings|[0, 10]| int|
   |effective_io_concurrency|[1, 10]| int|
   
   Параметры `archive_mode = off`, `effective_cache_size=10*0.6*RAM`, `huge_pages=on` выставил и оставил такие на постоянку.
   Прикинул, по максимальным значениям параметров относящихся к потреблению памяти, в сумме получается ~1Гб. 
   Поэтому задавал `vm.nr_hugepages=1280 #2.5Gb`
   Позднее, при запусках, обратил внимание что пг - нигде не пишет, что села в большие страницы.
   Видно только по изменению значений каунтеров в выоде `cat /proc/meminfo | grep -i hugepages`
   Неудобненько. 
   Оракл - подробно пишет: сколько занял, каких страниц занял, сразу видно - хорошо оценили, наконфигурили кол-во больших страниц, или нет.
   
   Дальше: я умышенно не стал, на этом этапе, включать, в набор варьируемых параметров пг, параметры `fsync, synchronous_commit`;
   Совершенно понятно - что эффект будет, большой.
   И ровно поэтому оптимизационный алгоритм: это заметит и конечно же начнёт пихать во все рассматриваемые варианты хорошие значения этих параметров.
   Импакт от остальных параметров, если он и будет какой то - будет просто не видим, на фоне импакта от `fsync, synchronous_commit`

Пос-ть действий, для выполнения tpcc-теста, такая:
1. Генерируется и выставляется (чем и как - позже) значения для параметров.
2. кластер перезапускается, по `pg_ctlcuster`, именно - по `stop|start`, чтобы прямо всё-всё "по честному" - сбросило кеши, пересоздало кеши заданных размеров, позакрывало сессии-транзакции, автовакуум перестал работать, если вдруг работал в ходе текущего теста.
   Здесь, в рантайме, немедленно возникла проблема: а фигатам, достаточно нагруженная/большая бд, сразу же остановится.
   Порешал так:
   ```shell
   pg_ctlcluster 14 main stop
   sleep 2
   pg_ctlcluster 14 main start
   sleep 2
   pg_isready -t 1 -q -h "$PG_HOST" -p "$PG_PORT"
   rc="$?"
   while [ "$rc" -ne "0" ]; do
         output "wait for cluster shutdowning"
         sleep 5
         pg_ctlcluster 14 main start
         sleep 1
         pg_isready -t 1 -q -h "$PG_HOST" -p "$PG_PORT"
         rc="$?"
   done
   output "cluster restarted"
   ```
4. на все таблицы tpcc-табличной модели выполняется вакуум. Тут покажу код:
   ```shell
   function vacuumit(){
   local v_tabname="$1"
   
   v_tabname=$( echo -n "$v_tabname" | tr -d [:space:] )
   if [ ! -z "$v_tabname" ]; then
      v_cmd="vacuum ${v_tabname};"
      /usr/bin/psql -U postgres -d postgres -q -c "${v_cmd}"
   fi
   }
   export -f vacuumit
   ...
   output "cluster restarted"
   output "vacuuming"
   cat /tmp/tablist.txt | awk -F "|" '{ if ( $2 > 0 ) {printf "%s\n", $1;}}' | sed -r "s/^\W+//" | xargs -n 1 -P 4 -I {} -t bash -c vacuumit\ \{\} | tee -a    "$LOGFILE"
   output "vacuuming done"
   ```
   Поскольку набор таблиц - статичен, просто сохранил их имена в файл и всё.
   Работает, параллелит, довольно быстро обрабатывает:
   ![psaxf](/HomeWorks/Lesson11/pslist.png)
   ![log](/HomeWorks/Lesson11/log.png)
5. выполняется tpcc-тест, с одними и тем же настройками (команда выше). 
   В таблицы бд сохраняются: данные теста, метрика теста, пг-параметры данного теста.

Работа генетического алгоритма, это он, по заданным ему параметрам, диапазонам значений параметров и фитнесс-функции выполняет оптимизацию:
![GA](/HomeWorks/Lesson11/ga.png)


Результаты
Ну. Прежде всего сджойнил, по номеру тестов, друг с другом, массив данных по значениям настрочных параметров, в тестах и метрик тестов.
Значения параметров, при этом - развернул в строку.
В cran-r зафиттил линейную модель - приближающую значения метрик теста, от значений параметров в тесте.
Построил линейную модель, для метрики теста, от значений параметров.
Если объясняемая переменная (в данном случае - метрика текста) действительно значимо объясняется, как факторами, значениями настрочных параметров, модель - должна быть похожа на динамику реальных значений.
С этим - плохо:
![metrics](/HomeWorks/Lesson11/11_2.png)

Т.е.: полная линейная модель, куда предикторами входят значения всех настроечных параметров пг, варьируемых от теста к тесту: едва объясняет обший рост значений метрики.
Т.е. да - что то, из того что я менял, в виде значений параметров пг, от теста к тесту - как то влияет.
Но на самом деле значимый фактор(ы), я не трогал.
Интересны значения коэфф-в линейной модели, практически значимым - является только коэф-т при `autovacuum_vacuum_scale_factor
`
Об этом - ниже чуть чуть.
Провёл `attribute-importance` анализ, т.е. выявил - какой предикат и как (в количественном смысле) влияет на значение метрики.
Получается так что это, по убыванию импакта:
```
autovacuum_vacuum_scale_factor
maintenance_work_mem
checkpoint_completion_target
shared_buffers
```
![attrimp](/HomeWorks/Lesson11/11_3.png)
Причём очень похоже что, именно параметр `autovacuum_vacuum_scale_factor`, практически в единственном числе, является наиболее значимым.
В принципе это же видно и из коэффициэнтов, которые дала линейная модель.
В общем - толстый намёк на автовакуум, что, среди того что я варьировал - это наиболее значимый фактор.

Все данные, графики - вывел в [эксельку](/HomeWorks/Lesson11/testprocessing.xlsx)

Намёк дан в виде `autovacuum_vacuum_scale_factor`
Т.е. это только - порог срабатывания для автовакуума, ничего не говорится про то как именно работа/не работа автовакуума влияет.
Ну.
Предположу что более щадящими являются условия при которых автовакуум реже анализирует/обрабатывает таблицы.
А если обрабатывает, то желательно чтобы побыстрее.
Проверка, взял значения настроечных параметров характерные для средних значений метрики.
Выкрутил параметры относящиеся к автовакууму, в подходящие, на мой взгляд и гипотезу, значения:
```shell
source /var/lib/postgresql/lesson8/library
$PSQL -v ON_ERROR_STOP=1 << __EOF__ 1>/dev/null
alter system set autovacuum_max_workers=2;
alter system set autovacuum_naptime=180;
alter system set checkpoint_timeout=586;
alter system set bgwriter_delay=5696;
alter system set bgwriter_lru_maxpages=93033;
alter system set checkpoint_completion_target=0.9;
alter system set commit_siblings=4;
alter system set maintenance_work_mem=131072;
alter system set autovacuum_analyze_scale_factor=0.7;
alter system set autovacuum_vacuum_scale_factor=0.7;
alter system set commit_delay=44889;
alter system set shared_buffers=87811;
alter system set work_mem=20261;
alter system set autovacuum_vacuum_threshold=4096;
alter system set effective_io_concurrency=3;
alter system set wal_buffers=8211;
alter system set wal_compression=off;
alter system set autovacuum_analyze_threshold=4096;
__EOF__
if [ "$?" -eq "0" ]; then
   restart_cluster
   psql -c "select name, setting from pg_catalog.pg_settings where name in ('autovacuum_analyze_scale_factor','autovacuum_analyze_threshold','autovacuum_max_workers','autovacuum_naptime','autovacuum_vacuum_scale_factor','autovacuum_vacuum_threshold','maintenance_work_mem','shared_buffers','wal_buffers','work_mem','wal_compression','bgwriter_delay','bgwriter_lru_maxpages','checkpoint_completion_target','checkpoint_timeout','commit_delay','commit_siblings','effective_io_concurrency') order by name;"
   psql -t -c "select table_name, pg_relation_size(quote_ident(table_name)) from information_schema.tables where table_schema = 'public' order by 2 desc;" > /tmp/tablist.txt
   vacuuming 1>/dev/null
   psql -c 'SELECT take_sample()'
   ./tpcc.lua --pgsql-host=localhost --pgsql-user=postgres --pgsql-db=postgres --pgsql-password="qazxsw123" --time=920 --threads=8 --report-interval=60 --tables=10 --scale=2 --use_fk=0  --trx_level=RC --db-driver=pgsql run >  /var/lib/postgresql/tpcc/sysbench-tpcc/result.txt
   psql -c 'SELECT take_sample()'
   cat /var/lib/postgresql/tpcc/sysbench-tpcc/result.txt | grep "thds: 8 tps: "
else
   echo "Error while executing alter system statements"
fi
```
Скриншоты:
![pic1](/HomeWorks/Lesson11/retry_besttest_1.png)
![pic2](/HomeWorks/Lesson11/retry_besttest_2.png)
![pic3](/HomeWorks/Lesson11/retry_besttest_3.png)
pg_profiler-отчёт: [report_47_48.html](https://htmlpreview.github.io/?https://github.com/MaksimIvanovPerm/pg/blob/main/HomeWorks/Lesson11/report_47_48.html)

Т.е. довольно надолго откладывается анализ и обработка таблиц.
Автовакуум много и долго спит, у него много памяти для работы.

Позапускал такое ещё пару раз: стабильно такая картина.
Т.е., уверенно, не те 30tps-ов, которые были в дефолтных настройках.
Ну, т.е., не те 60+ tps, максимальные, которые достигались, в принципе.
Видимо, какая то добавка к продуктивности - таки есть в значениях других параметров.
Т.е. если выкрутить на максимальные значения размеры `work_mem, shared_buffers, wal_buffers`: получатся те самые стабильные 60+ tps, на последних 2/3 времени теста;
Этот тест, здесь и далее, будем называть хороший тест.

Получается так что, в условиях данного tpcc-теста, его типовой продолжительности, профиля нагрузки который он даёт, значимым, снова, оказывается процесс работы автовакуума.
То как часто он начинает обрабатывать таблицы, `autovacuum_vacuum_scale_factor` влияет именно на это.
А если обрабатывает - сколько у него есть ресурсов для этой обработки (ну т.е.: как быстро обрабатывает).
Выставил, исходя из этих размышлений, при прочих равных c предудущим тестом, такое:
```shell
$PSQL -v ON_ERROR_STOP=1 << __EOF__ 1>/dev/null
alter system set autovacuum_max_workers=2;
alter system set autovacuum_naptime=10;
alter system set checkpoint_timeout=586;
alter system set bgwriter_delay=5696;
alter system set bgwriter_lru_maxpages=93033;
alter system set checkpoint_completion_target=0.9;
alter system set commit_siblings=4;
alter system set maintenance_work_mem=4096;
alter system set autovacuum_analyze_scale_factor=0.01;
alter system set autovacuum_vacuum_scale_factor=0.01;
alter system set commit_delay=44889;
alter system set shared_buffers=87811;
alter system set work_mem=20261;
alter system set autovacuum_vacuum_threshold=50;
alter system set effective_io_concurrency=3;
alter system set wal_buffers=8211;
alter system set wal_compression=off;
alter system set autovacuum_analyze_threshold=50;
__EOF__
```
Т.е. целеаправленно, при прочих равных пг-настройках с хорошим тестом, сделал так чтобы автовакуум - сработывал, при своём запуске, практически для любой таблицы, в которой есть более 1% мёртвых туплов.
И задал, относительно хорошего теста, малый период засыпания автовакуума.
И зарезал, до минимума, кол-во памяти, доступное для деятельности автовакуума.
И получил замечательную деградацию по tps-ам:
![rw1](/HomeWorks/Lesson11/retry_worsttest_1.png)
![rw2](/HomeWorks/Lesson11/retry_worsttest_2.png)
![rw3](/HomeWorks/Lesson11/retry_worsttest_3.png)
pg_profiler-отчёт: [report_45_46.html]([https://htmlpreview.github.io/?https://github.com/MaksimIvanovPerm/pg/blob/main/HomeWorks/Lesson11/report_45_46.html](https://htmlpreview.github.io/?https://github.com/MaksimIvanovPerm/pg/blob/main/HomeWorks/Lesson11/report_diff_45_46_47_48.html))
Этот тест, здесь и далее, будем называть плохой тест.

Т.е. работа автовакуума подтвержается, как главный фактор, влияющий на метрику качества теста.



diff-отчёты.
1. Между хорошим тестом и tpcc-тестом в дефолтных настройках пг-кластера, сразу после его установки и до отстройки ОС-и: [report_diff_4_5_47_48.html](/HomeWorks/Lesson11/report_diff_4_5_47_48.html)
2. Между хорошим и плохим tpcc-тестами: [report_diff_45_46_47_48.html](https://htmlpreview.github.io/?https://github.com/MaksimIvanovPerm/pg/blob/main/HomeWorks/Lesson11/report_diff_45_46_47_48.html)

Из спортивного интереса попытался, к значениям параметров дающих лучшее значение метрики.
Выставил `fsync=off, synchronous_commit=off`, запустил тест.
И тут YC остановил мне виртуалку, она - прерываемая у меня.
Кластер - сломался. Печалька.
На экране остались первые два замера:
```shell
[ 60s ] thds: 8 tps: 197.83 qps: 5600.76 (r/w/o: 2554.13/2650.57/396.06) lat (ms,95%): 219.36 err/s 0.73 reconn/s: 0.00
[ 120s ] thds: 8 tps: 201.68 qps: 5684.65 (r/w/o: 2594.25/2687.04/403.37) lat (ms,95%): 207.82 err/s 0.88 reconn/s: 0.00
```
Ну. Т.е., как обычно, не на порядок, кратно.
