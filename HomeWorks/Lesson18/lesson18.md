 
Решил отойти от буквы задания.
Был и есть такой весьма суровый, даже для промышленных инсталяций, DSS-like бенчмарк-тест: [TPC-H](https://www.tpc.org/tpch/);

Особенность у него в том что табличная модель, из коробки, выдаётся без индексов, каких либо.
Некоторые бенчарк-тулзы, типа hammerora, от себя добавляют индексы. 
Вот, решил, взять этот тест и его табличную модель, выполнить тест без индексов, посмотреть на результаты и данные о планах выполнения скл-команд и сообразить - какие индексы будет лучше сделать, какие и где джойны использовать, сколько work_mem выставить под HJ, если где то будет использоваться HJ со спиллингом в темп-файлы.
Сделать индексы, запустить, посмотреть что получится и понять - насколько выправил/ухудшил продуктивность обработки базой теста.

ER-диаграмма, табличной модели:
![ER](/HomeWorks/Lesson18/TPC-H_Datamodel.png)

Табличная модель, и запросы к ней, создаются специальными утилитами, которые можно свободно скачать с [сайта tpch-теста](https://www.tpc.org/tpc_documents_current_versions/current_specifications5.asp)
Там, однако, требуют регаться.
Мне что то стало противно и лениво, вспомнил что видел форки этих утилит, на гитхабе, скачал [оттуда](https://github.com/gregrahn/tpch-kit.git)
Процесс получения табличной модели:
```shell
sudo su root
apt-get update
apt-get upgrade
apt-get install git make gcc -y

sudo su postgres
cd
mkdir tpchkit
cd tpchkit
git clone https://github.com/gregrahn/tpch-kit.git
ls -lthr
cd tpch-kit/dbgen
make MACHINE=LINUX DATABASE=POSTGRESQL

mkdir $HOME/output_files
export DSS_CONFIG="/var/lib/postgresql/tpchkit/tpch-kit/dbgen"
export DSS_QUERY="$DSS_CONFIG/queries"
export DSS_PATH="$HOME/output_files"
export PATH="$PATH:$DSS_CONFIG"
dbgen -s 1 -v -f
qgen -v -c -s 2 -d | sed 's/limit -1//' | sed 's/day (3)/day/' > "$DSS_PATH/tpch_queries.sql"
```

В директории `DSS_PATH` нагеренятся файлы с расширением `.tbl` - это csv-like файлы с данным, для таблиц в бд.
Так же сгенерируется sql-скрипт `$DSS_PATH/tpch_queries.sql` ([tpch_queries.sql](/HomeWorks/Lesson18/tpch_queries.sql)): в нём 22 sql-запроса к табличной модели.

Загрузка данных, создал отдельную бд под табличную модель - `tpch`:
```shell
cat << __EOF__ > /etc/postgresql/14/main/additional.conf
full_page_writes=off
synchronous_commit='off'
fsync='off'
__EOF__
sed -i -e "s/.*include_if_exists.*/include_if_exists=\'additional.conf\'/" $PGCONF; grep "include_if_exists" $PGCONF 
restart_cluster
psql -c "select name, setting from pg_settings where name in ('wal_level','full_page_writes','synchronous_commit','fsync') order by name;" 

psql -c "create database tpch;"
psql -d tpch -f "$DSS_CONFIG/dss.ddl"
cd "$DSS_PATH"
for i in `ls *.tbl`; do
  table=${i/.tbl/}
  echo "Loading $table..."
  #sed 's/|$//' $i > /tmp/$i
  psql -d tpch -q -c "TRUNCATE $table"
  psql -d tpch -c "\\copy $table FROM '$DSS_PATH/$i' CSV DELIMITER '|'"
done

if [ -f "/etc/postgresql/14/main/additional.conf" ]; then
   rm -f "/etc/postgresql/14/main/additional.conf"
   restart_cluster
   psql -c "select name, setting from pg_settings where name in ('wal_level','full_page_writes','synchronous_commit','fsync') order by name;" 
fi
psql -d tpch -c "analyze verbose;"
```

Размеры таблиц:
```sql
select  n.nspname
       ,pa.rolname||'.'||t.relname as db_object
       ,to_char(CAST(t.reltuples AS numeric), '999999999999999') as est_rows
       ,pg_table_size(t.oid) as t_size
       ,pg_total_relation_size(t.oid) as ti_size
from pg_catalog.pg_class t, pg_catalog.pg_namespace n, pg_catalog.pg_authid pa
where 1=1
  and t.relkind='r'
  and t.relnamespace=n.oid
  and t.relowner=pa.oid
  and t.relname in ('supplier','region','part','partsupp','orders','nation','lineitem','customer')
order by t.reltuples desc
;

 nspname |     db_object     |  est_rows        |  t_size   |  ti_size
---------+-------------------+------------------+-----------+-----------
 public  | postgres.lineitem |          6000940 | 921903104 | 921903104
 public  | postgres.orders   |          1500000 | 213852160 | 213852160
 public  | postgres.partsupp |           800000 | 143024128 | 143024128
 public  | postgres.part     |           200000 |  33603584 |  33603584
 public  | postgres.customer |           150000 |  29401088 |  29401088
 public  | postgres.supplier |            10000 |   1851392 |   1851392
 public  | postgres.nation   |               25 |      8192 |      8192
 public  | postgres.region   |                5 |      8192 |      8192
```

Дальше - установка расширения `pg_profile`, [шпаргалка](https://github.com/MaksimIvanovPerm/pg/blob/main/HomeWorks/Lesson11/lesson11.md) есть в ДЗ к 11-му занятию.
При установке этого расширения - в т.ч., как пререквайрементс, ставиться расширение `pg_stat_statements` и ставится ОС-пакет `postgresql-contrib`;
Так же очень полезным и интересным оказывается расширение `pgcenter`
Берётся [тут](https://github.com/lesovsky/pgcenter#install-notes), в виде ОС-пакета
`pgcenter` требует ОС-пакета `postgresql-contrib`, он - уже будет установлен, если поставлен `pg_profile`, поэтому и в этом случае всё просто:
```shell
cd
mkdir pgcenter
cd pgcenter
wget -O 1.deb https://github.com/lesovsky/pgcenter/releases/download/v0.9.2/pgcenter_0.9.2_linux_amd64.deb
sudo dpkg -i 1.deb
```

пг-кластер: полностью дефолтный.
Выбрал и сохранил, из скрипта, `tpch_queries.sql` запросы в отдельные скрипты, с именами `Q{1..22}.sql`
Запустил, на выполнение, таким образом:
```shell
psql -c 'SELECT take_sample()'
for i in {1..22}; do
    [ -f "$DSS_PATH/Q${i}.log" ] && cat /dev/null > "$DSS_PATH/Q${i}.log"
    nohup psql -d tpch -q -f "$DSS_PATH/Q${i}.sql" -o "$DSS_PATH/Q${i}.log" &
done
wait
psql -c 'SELECT take_sample()'
```
Так оно проработало >18-ть часов и выполнения запросов `Q17,Q20,Q21` я так и не дождался, канселировал, эти запросы, с помощью `pgcenter` (т.е.: по `pg_cancel_backend`)

Отчёт, по этой попытке выполнения теста: [report_2_3.html](https://htmlpreview.github.io/?https://github.com/MaksimIvanovPerm/pg/blob/main/HomeWorks/Lesson18/report_2_3.html)
