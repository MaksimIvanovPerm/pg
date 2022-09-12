 
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
Зачем сделал именно так, почему не просто запустил, на выполнение `tpch_queries.sql`
Запускал.
Обнаружил что psql, при не нулевом значении своего параметра `FETCH_COUNT` (а он по умолчанию 100), оформляет каждый запрос как курсор, напрмиер:
```sql
DECLARE _psql_cursor NO SCROLL CURSOR FOR select cntrycode, count(*) as numcust, sum(c_acctbal) as totacctbal from ( select substring(c_phone from 1 for 2) as cntrycode, c_acctbal from customer where substring(c_phone from 1 for 2) in ('13', '31', '23', '29', '30', '18', '17') and c_acctbal > ( select avg(c_acctbal) from customer where c_acctbal > 0.00 and substring(c_phone from 1 for 2) in ('13', '31', '23', '29', '30', '18', '17') ) and not exists ( select * from orders where o_custkey = c_custkey ) ) as custsale group by cntrycode order by cntrycode
```

И потом получает, от сервера субд, пачками резалт-сет запроса, в виде:
```sql
FETCH FORWARD 100 FROM _psql_cursor
```
Т.е. вот этот FETCH-запрос - оказывается топовым, по времени выполнения.
Не очень удобно, я хотел чтобы мне pg_prfiler-отчёт сам показал - какой sql-запрос, сколько времени выполнялся.
В таком подходе оно работало 18+ часов, полагаю, в частности и из-за вот этого фетча, в т.ч.

Поэтому выставил, в `~/.psqlrc` настройку `\set FETCH_COUNT 0` и попытался сэкономить общее время на выполнение tpc-h-теста, распараллелив выполнение его sql-команд.
pg_profile-расширение - всё равно потом покажет: какой sql-запрос как выполнялся, в смысле временных/ресурсных затрат.
Т.е. запустил, на выполнение, скрпиты `Q{1..22}.sql` таким образом:
```shell
psql -c 'SELECT take_sample()'
for i in {1..22}; do
    [ -f "$DSS_PATH/Q${i}.log" ] && cat /dev/null > "$DSS_PATH/Q${i}.log"
    nohup psql -d tpch -q -f "$DSS_PATH/Q${i}.sql" -o "$DSS_PATH/Q${i}.log" &
done
wait
psql -c 'SELECT take_sample()'
```
В таком подходе оно проработало 2+ часа и выполнения запросов `Q17,Q20,Q21` я так и не дождался, канселировал, эти запросы, с помощью `pgcenter` (т.е.: по `pg_cancel_backend`)

Отчёт, по этой попытке выполнения теста: [report_2_3.html](https://htmlpreview.github.io/?https://github.com/MaksimIvanovPerm/pg/blob/main/HomeWorks/Lesson18/report_2_3.html)

Топ-ы, по убыванию времени выполнения: 
```
Запрос Q20 - в pg_profiler-отчёт не вошёл.
158c5f764abfeff - это Q21.sql
68d11bd34ddd94d9 - это Q17.sql
f8a09ac6153112a5 - это Q2.sql
```
Тексты запросов в скрипте [tpch_queries.sql](/HomeWorks/Lesson18/tpch_queries.sql)

Ну. Понятно что - плохо всё.
Прежде всего, до какого либо рассмотрения проблемных запросов, абслютно не включая голову, обвешал табличную модель, согласно определениям ER-диаграммы, первичными/внешними ключами и заиндексировал все внешние ключи.
С индексами получился такой скрипт:
```sql
alter table lineitem add constraint lineitem_pkey primary key (l_orderkey, l_linenumber);
alter table nation add constraint nation_pkey primary key (n_nationkey); 
alter table part add constraint part_kpey primary key (p_partkey);
alter table supplier add constraint supplier_pkey primary key (s_suppkey);
alter table customer add constraint customer_pkey primary key (c_custkey);
alter table orders add constraint orders_pkey primary key (o_orderkey);
alter table partsupp add constraint partsupp_pkey primary key (ps_partkey, ps_suppkey);
alter table region add constraint region_pkey primary key (r_regionkey);

alter table supplier add constraint supplier_nation_fkey foreign key (s_nationkey) references nation(n_nationkey);
create index supplier_nation_fkey_idx on supplier(s_nationkey);

alter table partsupp add constraint partsupp_part_fkey foreign key (ps_partkey) references part(p_partkey);
create index partsupp_part_fkey_idx on partsupp(ps_partkey);

alter table partsupp add constraint partsupp_supplier_fkey foreign key (ps_suppkey) references supplier(s_suppkey);
create index partsupp_supplier_fkey_idx on partsupp(ps_suppkey);

alter table customer add constraint customer_nation_fkey foreign key (c_nationkey) references nation(n_nationkey);
create index customer_nation_fkey_idx on customer(c_nationkey);

alter table orders add constraint orders_customer_fkey foreign key (o_custkey) references customer(c_custkey);
create index orders_customer_fkey_idx on orders(o_custkey);

alter table lineitem add constraint lineitem_orders_fkey foreign key (l_orderkey) references orders(o_orderkey);
create index lineitem_orders_fkey_idx on lineitem(l_orderkey);

alter table lineitem add constraint lineitem_partsupp_fkey foreign key (l_partkey,l_suppkey) references partsupp(ps_partkey,ps_suppkey);
create index lineitem_partsupp_fkey_idx on lineitem(l_partkey,l_suppkey);

alter table nation add constraint nation_region_fkey foreign key (n_regionkey) references region(r_regionkey);
create index nation_region_fkey_idx on nation(n_regionkey);
analyze verbose;
```

Дальше собирал эксплайн-данные о том как оптимизируются, в текущих условиях, проблемные 4-ре запроса.
Для этого вписал, в начало соотв-го Q*.sql-скрипта [explain-команду](https://www.postgresql.org/docs/14/sql-explain.html), без analyze-опции (чтобы не выполняло, а то - не понятно может быстро, можен не быстро) и:
```shell
psql -d tpch -f $DSS_PATH/Q17.sql -o $DSS_PATH/Q17.explain
```
| explain-данные |
| -------------- |
|[Q20.explain](/HomeWorks/Lesson18/Q20.explain)|
|[Q21.explain](/HomeWorks/Lesson18/Q21.explain)|
|[Q17.explain](/HomeWorks/Lesson18/Q17.explain)|
|[Q2.explain](/HomeWorks/Lesson18/Q2.explain)|

И начал разглядывать эти данные.
Довольно быстро стало понятно что надо будет смотреть на стат-свойства полей таблиц, для того чтобы решать - есть/не есть смысл вешать на это поле индкес.
Т.е.: насколько оно, какое то поле - уникальное.
Тут пользовался таким запросом:
```sql
select  ps.attname
       ,ps.null_frac
       ,ps.n_distinct
       ,ps.most_common_vals
       ,ps.most_common_freqs
       ,ps.most_common_elems
       ,ps.most_common_elem_freqs
from pg_catalog.pg_stats ps
where 1=1
  and ps.schemaname='public'
  and ps.tablename='lineitem'
  and ps.attname in ('l_quantity', 'l_partkey', 'l_suppkey', 'l_shipdate')
;
```

1. Замечания по [Q20.explain](/HomeWorks/Lesson18/Q20.explain) (тексты запросов добавил в файлы)
Тут явно напрашивается индекс на `partsupp.ps_partkey part.p_name` поля
Закрывается fk-индексами `partsupp_part_fkey_idx, partsupp_supplier_fkey_idx`
А ещё, для подзапроса с `lineitem`, чувствую что будет полезно сделать что то типа index-query-covering
У `lineitem` - все поля not null, для индексного доступа это - замечательно.
В чистом виде IQC тут не получится, но, по индексации внешних ключей индекс на `l_partkey, l_suppkey` - уже есть.
Ещё можно попробовать заиндексировать `l_shipdate,l_quantity` композитным индексом и именно в такой пос-ти столбцов.
Т.е.: `create index lineitem_l_shipdate_l_quantity_idx on lineitem(l_shipdate,l_quantity);`
2. Замечания по [Q21.explain](/HomeWorks/Lesson18/Q21.explain)
Тут однозначно надо индексировать поля по которым работают коррелированные подзапросы.
Т.е. поля `lineitem.l_orderkey, lineitem.l_suppkey`
Индекс на поле `L_ORDERKEY` - закрывается fk-индексом `lineitem_orders_fkey_idx`
Индекс на `nation.name` - не нужен, таблица всего 25 строк.
Индекс под `orders.o_orderstatus = 'F'`, увы, не поможет - очень не уникальное поле.
3. Замечания по [Q17.explain](/HomeWorks/Lesson18/Q17.explain)
Однозначно индексировать `lineitem.l_partkey` - правда это уже закрывается fkиндексом `lineitem_partsupp_fkey`
C уникальностью столбцов `part.(p_container|p_brand)` - увы, всё печально.
4. Замечания по [Q2.explain](/HomeWorks/Lesson18/Q2.explain)
Может поможет такой индекс, хотя с уникальностью значений этого столбца - не очень.
`CREATE INDEX IDX_PART_P_SIZE ON PART(P_SIZE);`

В итоге, почти все потребности - закрылись индексами на fk-столбцы.
От себя создавал только `CREATE INDEX IDX_PART_P_SIZE ON PART(P_SIZE)`

Рассмотрение работы хеш-джойнов, включение/выключение их где то, или увеличение `work_mem`, если где то - уместно, но не вмещается в память, спиллится в темп-ы, решил оставить на потом.
Сначала, решил, посмотреть - какой эффект получается от такой схемы индексации данных: судя по тому как активно оптимизатор пытался использовать NL-джойны, даже без индексов - может и не надо будет HJ рассматривать.

И да, эффект - замечательный:
![test_with_idx](/HomeWorks/Lesson18/run_after_indexing.png)
Тут допустил небольшую орг-оплошность: перетёр старые логи с выборками sql-запросов.
Надо было стары логи сохранить. Затем обсчитать старые/новые логи md5sum-утилой и показать что - выборки одинаковые.
Ну. Сохранился, в screen-буфере, вывод команд, с размерами старых логов, можно сравнить с размерами новых логов - видно что: размеры всех логов (выборок) совпадают.
![old_log](/HomeWorks/Lesson18/old_logs.png)
![new_log](/HomeWorks/Lesson18/after_indexing.png)

Новые планы выполнения проблемных sql-команд:
| explain-данные |
| -------------- |
|[Q20.explain_idx](/HomeWorks/Lesson18/Q20.explain_idx)|
|[Q21.explain_idx](/HomeWorks/Lesson18/Q21.explain_idx)|
|[Q17.explain_idx](/HomeWorks/Lesson18/Q17.explain_idx)|
|[Q2.explain_idx](/HomeWorks/Lesson18/Q2.explain_idx)|

pg_profile-отчёт: [report_7_8.html](https://htmlpreview.github.io/?https://github.com/MaksimIvanovPerm/pg/blob/main/HomeWorks/Lesson18/report_7_8.html)

В секции `Top SQL by temp usage` этого отчёта усмотрел такой скл-запрос: `4941100895dac3dd`, это запрос `Q11` (можно найти в [tpch_queries.sql](/HomeWorks/Lesson18/tpch_queries.sql) по этому лейблу - `Q11`)
Действительно, в плане выполнения этого запроса ([Q11.explain](/HomeWorks/Lesson18/Q11.explain)) есть такой этап (тут уже надо именно с analyze-опцией выполнять explain-команду над запросом):
```
->  HashAggregate  (cost=6404.24..7196.74 rows=10667 width=36) (actual time=174.264..195.432 rows=7601 loops=1)
      Output: partsupp.ps_partkey, sum((partsupp.ps_supplycost * (partsupp.ps_availqty)::numeric))
      Group Key: partsupp.ps_partkey
      Filter: (sum((partsupp.ps_supplycost * (partsupp.ps_availqty)::numeric)) > $2)
      Planned Partitions: 4  Batches: 5  Memory Usage: 4273kB  Disk Usage: 1032kB
```
Это про group-by предложение.
Ну. Дефолтное значение `work_mem` - 4МБайта.
Судя по тому сколько заспиллилось на диск - должно хватить что то в районе 8-16Мб.
Сделал сессионную настройку:
![1.png](/HomeWorks/Lesson18/1.png)

И да, помогло ([Q11.setted_explain](/HomeWorks/Lesson18/Q11.setted_explain)): 
```
HashAggregate  (cost=4514.24..4994.24 rows=10667 width=36) (actual time=100.634..116.971 rows=7601 loops=1)
  Output: partsupp.ps_partkey, sum((partsupp.ps_supplycost * (partsupp.ps_availqty)::numeric))
  Group Key: partsupp.ps_partkey
  Filter: (sum((partsupp.ps_supplycost * (partsupp.ps_availqty)::numeric)) > $2)
  Batches: 1  Memory Usage: 17937kB
```

ДЗ
1. `Реализовать прямое соединение двух или более таблиц`
   ![hw1.png](/HomeWorks/Lesson18/hw1.png)
2. `Реализовать левостороннее (или правостороннее) соединение двух или более таблиц`
   ![hw2.png](/HomeWorks/Lesson18/hw2.png)
3. `Реализовать кросс соединение двух или более таблиц`
   ![hw3.png](/HomeWorks/Lesson18/hw3.png)
4. `Реализовать полное соединение двух или более таблиц`
   ![hw4.png](/HomeWorks/Lesson18/hw4.png)
5. `Реализовать запрос, в котором будут использованы разные типы соединений`
   ![hw5.png](/HomeWorks/Lesson18/hw5.png)
6. `К работе приложить структуру таблиц, для которых выполнялись соединения`
   ```sql
   [local]:5432 #postgres@tpch > \d supplier
                           Table "public.supplier"
      Column    |          Type          | Collation | Nullable | Default
   -------------+------------------------+-----------+----------+---------
    s_suppkey   | integer                |           | not null |
    s_name      | character(25)          |           | not null |
    s_address   | character varying(40)  |           | not null |
    s_nationkey | integer                |           | not null |
    s_phone     | character(15)          |           | not null |
    s_acctbal   | numeric(15,2)          |           | not null |
    s_comment   | character varying(101) |           | not null |
   Indexes:
       "supplier_pkey" PRIMARY KEY, btree (s_suppkey)
       "supplier_nation_fkey_idx" btree (s_nationkey)
   Foreign-key constraints:
       "supplier_nation_fkey" FOREIGN KEY (s_nationkey) REFERENCES nation(n_nationkey)
   Referenced by:
       TABLE "partsupp" CONSTRAINT "partsupp_supplier_fkey" FOREIGN KEY (ps_suppkey) REFERENCES supplier(s_suppkey)
   
   [local]:5432 #postgres@tpch > \d partsupp
                            Table "public.partsupp"
       Column     |          Type          | Collation | Nullable | Default
   ---------------+------------------------+-----------+----------+---------
    ps_partkey    | integer                |           | not null |
    ps_suppkey    | integer                |           | not null |
    ps_availqty   | integer                |           | not null |
    ps_supplycost | numeric(15,2)          |           | not null |
    ps_comment    | character varying(199) |           | not null |
   Indexes:
       "partsupp_pkey" PRIMARY KEY, btree (ps_partkey, ps_suppkey)
       "partsupp_part_fkey_idx" btree (ps_partkey)
       "partsupp_supplier_fkey_idx" btree (ps_suppkey)
   Foreign-key constraints:
       "partsupp_part_fkey" FOREIGN KEY (ps_partkey) REFERENCES part(p_partkey)
       "partsupp_supplier_fkey" FOREIGN KEY (ps_suppkey) REFERENCES supplier(s_suppkey)
   Referenced by:
       TABLE "lineitem" CONSTRAINT "lineitem_partsupp_fkey" FOREIGN KEY (l_partkey, l_suppkey) REFERENCES partsupp(ps_partkey, ps_suppkey)
   
   [local]:5432 #postgres@tpch > \d nation
                            Table "public.nation"
      Column    |          Type          | Collation | Nullable | Default
   -------------+------------------------+-----------+----------+---------
    n_nationkey | integer                |           | not null |
    n_name      | character(25)          |           | not null |
    n_regionkey | integer                |           | not null |
    n_comment   | character varying(152) |           |          |
   Indexes:
       "nation_pkey" PRIMARY KEY, btree (n_nationkey)
       "nation_region_fkey_idx" btree (n_regionkey)
   Foreign-key constraints:
       "nation_region_fkey" FOREIGN KEY (n_regionkey) REFERENCES region(r_regionkey)
   Referenced by:
       TABLE "customer" CONSTRAINT "customer_nation_fkey" FOREIGN KEY (c_nationkey) REFERENCES nation(n_nationkey)
       TABLE "supplier" CONSTRAINT "supplier_nation_fkey" FOREIGN KEY (s_nationkey) REFERENCES nation(n_nationkey)
   
   ```
7. `Придумайте 3 своих метрики на основе показанных представлений`
    На мой взгляд это слишком обще поставленный вопрос. 
    Если это oltp-нагрузка, тогда: tps - кол-во транзакций/сек.
    Если это olap-нагрузка, тогда: qps - кол-во запросов/сек.
    Потому что конечных пользователей субд, бизнес, всегда интересует доступность и продуктивность работы сервиса субд.
    В этом смысле - ну ещё среднее время работы субд до планового/не планового прерывания, и среднее время недоступности.
    От чего конкретно зависят эти 3, или 4 метрики - в случае каждой конкретной инсталяции будет зависеть от какой то своей специфики.
