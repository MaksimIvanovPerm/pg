 
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
Сервер сделал таким: [11_1](/HomeWorks/Lesson11/11_1.png)


