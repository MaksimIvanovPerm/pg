[Официальная док-ция](https://www.postgresql.org/docs/14/ddl-partitioning.html)

Получить и вести секционирование таблицы, в пг, можно двумя способами.
Первый и - старый (до 10-й версии пг) механизм: триггерный.
И новый, с версии 10: так называемый - нативный, или - декларативный.

Сначала про общее для обоих вариантов секционирования.
В обоих вариантах партиционирование выполняется с использованием понятия: парент-таблица и её таблицы-партиции.
Пример (триггерное секционирование):
```sql
CREATE TABLE logs (id serial, created_at timestamp without time zone);
CREATE TABLE logs_old (CHECK ( created_at < '2020-01-01' ) ) INHERITS(logs);
CREATE TABLE logs_202001( CHECK ( created_at >= '2020-01-01' and created_at < '2020-02-01' )) INHERITS(logs);
...
CREATE TABLE logs_202012 ( CHECK ( created_at >= '2020-12-01' and created_at < '2021-01-01' )) INHERITS(logs);
```

Соотв-но есть понятие наследования: таблиц-партиции наследуют констрейнты, индексы от парент-таблицы и парент-таблица - как бы объявляет структуру партиционированной таблицы.
Как обычно - ключ секционирования: должен быть not null;
Как обычно - pk/uk-констрейнты, на партиционированную таблицу (и, соотв-но, pk/uk-индексы): обязаны включать в себя ключ секционирования таблицы (пункт `5.11.2.3. Limitations` [доки](https://www.postgresql.org/docs/14/ddl-partitioning.html#DDL-PARTITIONING-OVERVIEW)).
Как обычно - ключ секционирования, если это диапазонное, или списковое секционирование, в каждой партиции (с некоторыми оговорками), желательно обвешивать check-констрейнтами.
Нужно для того чтобы:
1. Гарантированно перекрыть возможность попадания/оставления строки не "в свою" партицию: check-констрейнт просто не пропустит, то что, по дизайну, не должно быть в данной партиции.
   Так называемый `constraint_exclusion`
2. При состоянии active-validate (правда, не уверен - есть/не есть такое в пг): база, этим check-констрейнтом, информируется, о том что именно есть, в данной партиции, в ключе секуионирования.
   И, например при аттачах партиции к парент-таблице: не выполняет валидацию фактических значений ключей секционирования строк, в партиции.
   Что, для больших партиций - весьма актуально.
   Партишен-прунинг, для триггер-базед варианта секционирования, может сработать только на этих check-ах, если они есть и если есть диапазонный предикат, в where-предложении sql-команды, на ключ секционирования.
   Соотв-но тут ещё - крайне желателен индекс, на ключ-секционирования.

Оговорка, с пространным отступлением в декларативное секционирование, такая: в декларативном секционировании появилась так называемая дефолтная партиция.
Пример, именно декларативного секционирования ([отсюда](https://severalnines.com/blog/how-take-advantage-new-partitioning-features-postgresql-11/)):
```sql
CREATE TABLE customers(cust_id bigint NOT NULL,cust_name varchar(32) NOT NULL,cust_address text,
cust_country text)PARTITION BY LIST(cust_country);
CREATE TABLE customer_ind PARTITION OF customers FOR VALUES IN ('ind');
CREATE TABLE customer_jap PARTITION OF customers FOR VALUES IN ('jap');
CREATE TABLE customers_def PARTITION OF customers DEFAULT;
```

Дефолтная партиция - нужна для сохранения строк, которые не мапятся, по своему значению ключа секционирования, ни в какие другие партиции.
Правда, если дефолтная таблица - есть, и в ней есть какие то строки, например, в контексте примера выше:
```sql
UPDATE customers1 SET cust_country ='usa' WHERE cust_id=2039;
```
То, если создавать специальную партицию под `cust_country='usa'` - надо будет, сначала, куда то сохранить и удалить строки с `cust_country='usa'` из дефолтной партиции.
Иначе - не даст создать партицию.
Ну и, поскольку, если дефолтная партиция - есть и, поскольку, не известно заранее - какие именно значения ключа секционирования в её строках будут (если будут) то check-констрейнт на эту партицию, на столбец(ы) являющиеся ключами секционирования - повесить затруднительно.
Кстати это обозначает что, при добавлении новых партиций, дефаулт-секция, если она есть - будет сканится полностью.
На предмет проверки - а вдруг там есть записи, со значением(ами) ключей секционирования такими, какими они д.б. в новой партиции.
Поэтому, если check-констрейнт, на дефаулт-секцию, на ключ секционирования повесить затруднительно, то, хотя бы, индекс должен быть.

Ещё один момент, который, тоже, будет трудно поддаваться обвешиванию check-ами: партиции, в декларативном секционировании, которые могут быть объявлены, с опциями `minvalue` и/или `maxvalue`
Ну и видимо - такая же будет история, если надо будет добавить партицию под значение ключа, под которое уже есть строки в партициях с maxvalue/minvalue;

Можно, в обоих вариантах секционирования, навешивать какие то свои индексы, констрейнты, на таблицы-партиции.
При этом, опять, отступление в декларативное секционирование, в [доке](https://www.postgresql.org/docs/14/ddl-partitioning.html#DDL-PARTITIONING-OVERVIEW) есть такое интересное замечание, в пункте `5.11.2.2. Partition Maintenance`, про такие - дополнительные индексы.
Дело в том что в пг - можно создавать индексы с опцией `CONCURRENTLY` ([дока](https://www.postgresql.org/docs/14/sql-createindex.html#SQL-CREATEINDEX-CONCURRENTLY)) - это аналог online-опции, в oracle-субд.
Т.е. - без эксклюзивного лока, на индексируемую таблицу, вместе с дмл-операциями.
В пг, правда, CONCURRENTLY-опция стоит сильно дороже, чем в оракле, потому что, про себя, она потребует двойного сканирования ииндексируемой таблицы.
Типа, сначала создаётся индекс, при первом сканировании.
Потом дожидается завершения текущих, на момент первого сканирования, транзакций и делает второе сканирование - для уточнения индексных элементов в индексе.

Так вот оказывается что CONCURRENTLY-опцию: нельзя применять, для создания вторичных индексов (global-индексов, т.е.: на всю партиционированную таблицу. На конкретную таблицу-партицию - можно) на партиционированную таблицу.
Но есть объездной вариант, пример, из доки:
```sql
CREATE TABLE measurement (
    city_id         int not null,
    logdate         date not null,
    peaktemp        int,
    unitsales       int
) PARTITION BY RANGE (logdate);
...
CREATE INDEX measurement_usls_idx ON ONLY measurement (unitsales);
...
CREATE TABLE measurement_y2006m02 PARTITION OF measurement FOR VALUES FROM ('2006-02-01') TO ('2006-03-01');
...
CREATE INDEX measurement_usls_200602_idx ON measurement_y2006m02 (unitsales); --можно с CONCURRENTLY-опцией
ALTER INDEX measurement_usls_idx ATTACH PARTITION measurement_usls_200602_idx;
...
```
Особенность тут в том что по ONLY-опции индекс объявляется только на парент-таблицу, которая типа - пустая.
ONLY - понял так что это общеиспользуемое ключевое слово, которое встречается в разных скл-командах пг скл-диалекта и обозначает, по видимому, именно тот, сам объект, который упомянут далее.
И такой индекс, на парент-таблицу, сразу после создания помечается инвалидным.
Затем на какую то таблицу-партицю, на тот же индексируемый столбец, вешается индекс и аттачится, как партиция индекса, к индексу на парент-таблицу (в пг, технически, индексы - тоже таблицы).
Сам аттач, понятно - это быстро, это никакая не обработка каких то табличных строк.
И вот после аттача - глобальный индекс - помечается валидным.

Немного про старый/новый вариант секционирования.
Смысл триггерного варианта, вкратце, в том что движение строк, в и между партициями, при, соотв-но, инсертах/апдейтах, выполняется for-each-row дмл-триггером.
Т.е.: некто - определяет практически всё:
Набор таблиц: парент-таблица и таблиц-партиции, индексы, констрейнты.
И определяет триггер.
[Шикарный и подробный пример](https://juanitofatas.com/series/postgres/partitioning) об этом варианте получения партиционированной таблицы.

В дальнейшем - вот этот весь набор объектов: так и живёт, такой, какой он был определён.
Т.е. новые партиции автоматом - не создаются, если вставляется, или, по итогу какого то апдейта - получается строка с таким значением ключа секционирования, под которое ни одна из уже существующих партиций - не попадает.
Тогда, такая строка - сохраняется в парент-таблицу.
Дефолт-партиции, maxvalue/minvalue определения диапазона ключа секционирования, для партиции, в триггерном мех-ме - нет.
Кстати, в декларативном варианте секционирования - новые партиции автоматически: тоже не создаются.
Вакуумировать, анализировать таблицы-партиции надо отдельно, явно указывая их имя.

В декларативном секционировании: триггерный мех-м - спрятан под капот.
И, ключевое: изменён синтаксис добавления таблиц-партиций - теперь в самой ддл-команде определения партиции указывается - к какому именно диапазону значений ключа секционирования данная партиция относится.
Например:
```sql
CREATE TABLE measurement (
    city_id         int not null,
    logdate         date not null,
    peaktemp        int,
    unitsales       int
) PARTITION BY RANGE (logdate);

CREATE TABLE measurement_y2006m02 PARTITION OF measurement FOR VALUES FROM ('2006-02-01') TO ('2006-03-01');
...
CREATE TABLE measurement_y2007m12 PARTITION OF measurement FOR VALUES FROM ('2007-12-01') TO ('2008-01-01') TABLESPACE fasttablespace;
CREATE TABLE measurement_y2006m02 PARTITION OF measurement FOR VALUES FROM ('2006-02-01') TO ('2006-03-01') PARTITION BY RANGE (peaktemp);
```

Этим сразу же сообщается субд и sql-оптимизатору информация о том - где какие строки должны(или не должны) хранится и храняться.
И партишен-прунинг не обязательно обеспечивать на constraint_exclusion check-констрейнтах, хотя они и желательны.
Тем не менее, видимо для баквард-компатибилити, сделан параметр: `enable_partition_pruning` По дефолту: `on`
Есть аттач/детач партиций, аналог partition-exchange в oracle-субд.
Вакуумировать, анализировать таблицы-партиции надо, так же, отдельно, явно указывая их имя.

Новые партиции - автоматически не создаются, ни в каком виде секционирования.
Т.е. аналога интервального секционирования, как в oracle-субд, нет.
Но, как обычно, для этого есть пг-расширения, например [pg_partman](https://github.com/pgpartman/pg_partman)

Формулировка ДЗ: `Секционировать большую таблицу из демо базы flights`

Не понял - где брать эту демо базу.
Спросил у гугла, в первой же позиции данных гугл-поска нашлась какая то демо-база, про авиаперевозки, на [сайте пгпро](https://postgrespro.com/education/demodb).

Установка этой демо-бд (!!! оно пересоздаёт базу DEMO !!!):
```shell
sudo su postgre
wget -O 1.zip https://edu.postgrespro.com/demo-small-en.zip
unzip 1.zip
psql -f demo-small-en-20170815.sql
psql -d demo << __EOF__
\conninfo
analyze verbose;
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
  and t.relname in ('aircrafts_data','airports_data','boarding_passes','bookings','flights','seats','ticket_flights','tickets')
order by t.reltuples desc
;
__EOF__
```

```
 nspname  |        db_object         |     est_rows     |  t_size  |  ti_size
----------+--------------------------+------------------+----------+-----------
 bookings | postgres.ticket_flights  |          1045730 | 71442432 | 113917952
 bookings | postgres.boarding_passes |           579686 | 34963456 |  84598784
 bookings | postgres.tickets         |           366733 | 50380800 |  61972480
 bookings | postgres.bookings        |           262788 | 13746176 |  19668992
 bookings | postgres.flights         |            33121 |  3244032 |   5062656
 bookings | postgres.seats           |             1339 |    98304 |    147456
 bookings | postgres.airports_data   |              104 |    57344 |     73728
 bookings | postgres.aircrafts_data  |                9 |    16384 |     32768
(8 rows)
```

Самая большая таблица, правда она не именно `flights` называется, но, может быть это пгпро переделали так:
```sql
[local]:5432 #postgres@demo > \d ticket_flights
                     Table "bookings.ticket_flights"
     Column      |         Type          | Collation | Nullable | Default
-----------------+-----------------------+-----------+----------+---------
 ticket_no       | character(13)         |           | not null |
 flight_id       | integer               |           | not null |
 fare_conditions | character varying(10) |           | not null |
 amount          | numeric(10,2)         |           | not null |
Indexes:
    "ticket_flights_pkey" PRIMARY KEY, btree (ticket_no, flight_id)
Check constraints:
    "ticket_flights_amount_check" CHECK (amount >= 0::numeric)
    "ticket_flights_fare_conditions_check" CHECK (fare_conditions::text = ANY (ARRAY['Economy'::character varying::text, 'Comfort'::character varying::text, 'Business'::character varying::text]))
Foreign-key constraints:
    "ticket_flights_flight_id_fkey" FOREIGN KEY (flight_id) REFERENCES flights(flight_id)
    "ticket_flights_ticket_no_fkey" FOREIGN KEY (ticket_no) REFERENCES tickets(ticket_no)
Referenced by:
    TABLE "boarding_passes" CONSTRAINT "boarding_passes_ticket_no_fkey" FOREIGN KEY (ticket_no, flight_id) REFERENCES ticket_flights(ticket_no, flight_id)

[local]:5432 #postgres@demo >
```

Поразглядвал [sql-запросы](https://postgrespro.com/docs/postgrespro/10/apjs05.html), к этой табличной схеме.
Ну. `ticket_flights` - либо джойнится по полю `ticket_no`, либо фильтруется, именно по этому полю, других вариантов нет.

Есть вот такой sql-запрос:
```sql
psql -d demo << __EOF__ | tee /tmp/temp.txt
explain (verbose true, format text, analyze true)
SELECT   b.book_ref,
         t.ticket_no,
         t.passenger_id,
         t.passenger_name,
         tf.fare_conditions,
         tf.amount,
         f.scheduled_departure_local,
         f.scheduled_arrival_local,
         f.departure_city || ' (' || f.departure_airport || ')' AS departure,
         f.arrival_city || ' (' || f.arrival_airport || ')' AS arrival,
         f.status,
         bp.seat_no
FROM     bookings b
         JOIN tickets t ON b.book_ref = t.book_ref
         JOIN ticket_flights tf ON tf.ticket_no = t.ticket_no
         JOIN flights_v f ON tf.flight_id = f.flight_id
         LEFT JOIN boarding_passes bp ON tf.flight_id = bp.flight_id
                                     AND tf.ticket_no = bp.ticket_no
WHERE    b.book_ref = '_QWE12'
ORDER BY t.ticket_no, f.scheduled_departure;
\q
__EOF__
```
Давайте этот запрос, здесь и далее, называть `Q1`;

Запрос - ничего не возвращает, 0 строк, это важно, для дальнейшего рассмотрения.

Выше, в описании стр-ры таблицы, видно что есть `"ticket_flights_pkey" PRIMARY KEY, btree (ticket_no, flight_id)`;
И есть `"tickets_pkey" PRIMARY KEY, btree (ticket_no)` на таблицу `tickets`;
Оно эти джойны - отлично подведёт под NL-вариант соединения, и `ticket_flights` по определению запроса - будет ведомым потоком.
Для индексного доступа в таблицу - не важно, таблица секционирована/не секционирована.

[План выполнения](/HomeWorks/Lesson20/plan.txt) этого запроса: и да - всё таки и есть: NL-джойны с индексным доступом.

С фильтрацией запрос - ну, например:
```sql
SELECT   to_char(f.scheduled_departure, 'DD.MM.YYYY') AS when,
         f.departure_city || ' (' || f.departure_airport || ')' AS departure,
         f.arrival_city || ' (' || f.arrival_airport || ')' AS arrival,
         tf.fare_conditions AS class,
         tf.amount
FROM     ticket_flights tf
         JOIN flights_v f ON tf.flight_id = f.flight_id
WHERE    tf.ticket_no = '0005432661915'
ORDER BY f.scheduled_departure;
```

Давайте этот запрос, здесь и далее, называть `Q2`;
Запрос - возвращает 6 строк.

В `Q2`, если уникальных значений, именно в поле `ticket_no` - немного, относительно общего кол-ва строк в таблице `ticket_flights` секционирование - очень даже может помочь.
Что там с уникальностью:
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
  and ps.schemaname='bookings'
  and ps.tablename='ticket_flights'
  and ps.attname in ('ticket_no', 'flight_id');

most_common_elem_freqs |
-[ RECORD 2 ]----------+----------------
attname                | ticket_no
null_frac              | 0
n_distinct             | -0.30283076
most_common_vals       |
most_common_freqs      |
most_common_elems      |
most_common_elem_freqs |

[local]:5432 #postgres@demo > select count(*) as col1, count(distinct ticket_no) as col2 from bookings.ticket_flights;
-[ RECORD 1 ]-
col1 | 1045726
col2 | 366733

[local]:5432 #postgres@demo >
```
Т.е., в среднем, на одно значение, в столбце `ticket_no` встречается в 3-4 строках, при том что строк: ~1млн.
Такое индексом `ticket_flights_pkey` закроется, в данном случе, отлично, партиции тут скорее навредят.

Т.е., если даже таблицу, как то побить на партиции, с большой вероятностью это ничего не изменит в данных запросах.
Однако, сказано побить, значит - побъём.
Если и бить таблицу `ticket_flights` то на партиции по полю `ticket_no`
Может быть по полям `ticket_no, flight_id`

Для начала - просто потренируюсь получать из не секционированной таблицы секционированную.
Плюс - строк довольно много, и `ticket_no` - строковое, неудобно выписывать диапазоны, пока лениво с этим связываться.

Сам подход к преобразованию не секционированной таблицы в секционированную (или изменение разбиения уже секционированной таблицы), как подсказывает гугл, типовой и, по существу, такой ([например](https://rodoq.medium.com/partition-an-existing-table-on-postgresql-480b84582e8d)):
1. Исходная таблица переименовывается.
   Интересно, кстати: а что в пг с развалидацией зависимых объектов, хранимых процедур, вьюх, зависящих от таблицы.
   И, если такое понятие есть, то насколько бесболезненно это, потом, завалидируется, в случае высокой популярности зависимых объектов бд.
2. Создаётся целевая таблица, понятно - такая же по структуре и по pk-индексу и с оригинальным именем, какое оно было у исходной таблицы.
   Создаются её партиции, какие надо.
3. Исходная таблица аттачится к новой таблице как партиция. 
   Тут, правда, не очень понятно - как оно такое получится, в общем случае.
   Бикоз оф, ну если с range-секционированием - ещё такое прокатит, в общем случае, то как быть с листовым, или хаш-секционированием.
   А ещё могут хотеть сделать (ре)партиционирование именно для того чтобы большую исходную таблицу - побить на значительно меньшие куски.
   Т.е., в таком случае, априорно нельзя аттачить исходную таблицу, как одну партицию, в целевую таблицу.
   Подозреваю что, в общем случае - придётся делать не аттач, а `insert into <новая таблица> select * from <старая таблица>;`
   А это, может быть весьма долго, при больших объёмах данных.

Для автоматизации этого всего существуют пг-экстеншены, например, [pg_rewrite](https://github.com/cybertec-postgresql/pg_rewrite)

Если правильно подозреваю, про перенос данных, что в общем случае его надо делать - скл-командой, или репликацией, или триггером, тогда, более адекватным, в случае больших объёмов данных, в смысле снижения даунтайма, будет такой вариант:
1. Создаётся целевая таблица, понятно - такая же по структуре и по pk-индексу и с каким то именем.
   Имя, которое занято исходной таблицей - не трогается.
2. Делается запуск репликации (натурально - репликации, или какого то поделия, на for-each-row дмл-триггере), из исходной таблицы, в целевую.
   С логической репликациях, на публикации/подписке: тоже можно, но довольно извратно, [пишут об этом, в подробностях, как именно](https://blog.hagander.net/repartitioning-with-logical-replication-in-postgresql-13-246/).
3. Когда репликация выйдет на штатную работу и лаг репликации будет минимальным: начинается даунтайм, в виде перекрытия доступности, для новых транзакций, доступа к исходной таблице.
   Когда уже открытые тр-ци доработают своё, репликация останавливается.
   Исходная таблица - переименовывается в какое то свободное имя.
   Целевая таблица - переименовывается в имя которое было у исходной таблицы.
   Открытие доступа к целевой таблице.

Ну. Попробовал так:
1. Создал целевую таблицу:
   ```sql
   CREATE TABLE ticket_flights_hashed (
       ticket_no character(13) NOT NULL,
       flight_id integer NOT NULL,
       fare_conditions character varying(10) NOT NULL,
       amount numeric(10,2) NOT NULL,
       CONSTRAINT ticket_flights_amount_check CHECK ((amount >= (0)::numeric)),
       CONSTRAINT ticket_flights_fare_conditions_check CHECK (((fare_conditions)::text = ANY (ARRAY[('Economy'::character varying)::text, ('Comfort'::character varying)::text, ('Business'::character varying)::text])))
   )
   partition by hash(ticket_no, flight_id) 
   ;
   alter table ticket_flights_hashed add constraint ticket_flights_hashed_pk primary key (ticket_no, flight_id);
   ```
   Конечно лобовая попытка подключить старую таблицу как партицию, в данном случае - не получилась:
   ```sql
   [local]:5432 #postgres@demo > alter table ticket_flights_hashed attach partition ticket_flights for values with (modulus 10, remainder 9);
   ERROR:  partition constraint of relation "ticket_flights" is violated by some row
   ```
   Поэтому, в случае hash-секционирования: только ч/з переливку данных.
   Кстати, если захочется увеличить кол-во партиций, при хеш-секционировании - тоже [через переливку данных](https://www.postgresql.fastware.com/postgresql-insider-prt-ove).
2. Объявил партиции:
   ```sql
   create table ticket_flights_hashed_p0 partition of ticket_flights_hashed for values with (modulus 5,remainder 0);
   create table ticket_flights_hashed_p1 partition of ticket_flights_hashed for values with (modulus 5,remainder 1);
   create table ticket_flights_hashed_p2 partition of ticket_flights_hashed for values with (modulus 5,remainder 2);
   create table ticket_flights_hashed_p3 partition of ticket_flights_hashed for values with (modulus 5,remainder 3);
   create table ticket_flights_hashed_p4 partition of ticket_flights_hashed for values with (modulus 5,remainder 4);
   [local]:5432 #postgres@demo > \d+ ticket_flights_hashed_p4
                                              Table "bookings.ticket_flights_hashed_p4"
        Column      |         Type          | Collation | Nullable | Default | Storage  | Compression | Stats target | Description
   -----------------+-----------------------+-----------+----------+---------+----------+-------------+--------------+-------------
    ticket_no       | character(13)         |           | not null |         | extended |             |              |
    flight_id       | integer               |           | not null |         | plain    |             |              |
    fare_conditions | character varying(10) |           | not null |         | extended |             |              |
    amount          | numeric(10,2)         |           | not null |         | main     |             |              |
   Partition of: ticket_flights_hashed FOR VALUES WITH (modulus 5, remainder 4)
   Partition constraint: satisfies_hash_partition('33006'::oid, 5, 4, ticket_no, flight_id)
   Indexes:
       "ticket_flights_hashed_p4_pkey" PRIMARY KEY, btree (ticket_no, flight_id)
   Check constraints:
       "ticket_flights_amount_check" CHECK (amount >= 0::numeric)
       "ticket_flights_fare_conditions_check" CHECK (fare_conditions::text = ANY (ARRAY['Economy'::character varying::text, 'Comfort'::character varying::text, 'Business'::character varying::text]))
   Access method: heap
   ```
3. Дальше надо бы, конечно, писать хотя бы for-each-row дмл-триггер.
   Чтобы он, при выполнении дмл-команд на исходную таблицу, в фоне, занимался дублированием этих дмл-ей на новую таблицу.
   Т.е. повторял, в новую таблицу, инсерты.
   Повтор обновлений, в новую таблицу, выполнял с проверкой - есть/не есть, в новой таблице, обновляемая строка.
   Повтор удалений в новую таблицу - тоже с проверкой: она там, удаляемая строка, есть/не есть.
   
   Кстати попадос будет, если для строй и/или новой таблиц - используется автоинкрементные столбцы, под ключи строк.
   
   И запускать свою дмл-команду, на исходную таблицу, которой выполнить какой нибудь формальный апдейт каждой строки.
   Затем перекрыть, как нибудь, доступность к исходной таблице, для пользовательских скл-сессий.
   Дать доработать старым транзакциям.
   Увы: merge-команды в пг нет, поэтому: просто ещё раз выполнить формальный апдейт. После этого триггер отключить.
   Мне это всё проделывать, ну, как то слишком, для формата ДЗ.
   Поэтому ограничился простым инсертом всех данных из исходной таблицы, в целевую - хеш-секционированную.
   ```sql
   [local]:5432 #postgres@demo > insert into ticket_flights_hashed select * from ticket_flights;
   INSERT 0 1045726
   Time: 10755.497 ms (00:10.755)
   ```
4. Размеры таблиц, исходной/целевой, таблиц-партиций:
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
     and t.relname in ('ticket_flights_hashed','ticket_flights','ticket_flights_hashed_p0','ticket_flights_hashed_p1','ticket_flights_hashed_p2','ticket_flights_hashed_p3','ticket_flights_hashed_p4')
   order by t.reltuples desc;
    nspname  |             db_object             |     est_rows     |  t_size  |  ti_size
   ----------+-----------------------------------+------------------+----------+-----------
    bookings | postgres.ticket_flights           |          1045730 | 71442432 | 113917952
    bookings | postgres.ticket_flights_hashed_p1 |           209618 | 14344192 |  25616384
    bookings | postgres.ticket_flights_hashed_p0 |           209163 | 14319616 |  25444352
    bookings | postgres.ticket_flights_hashed_p4 |           209100 | 14311424 |  25534464
    bookings | postgres.ticket_flights_hashed_p2 |           209042 | 14311424 |  25452544
    bookings | postgres.ticket_flights_hashed_p3 |           208803 | 14295040 |  25444352
   (6 rows)
   ```
   Ещё интересный запрос, с учётом связей партиционированной таблицы и её партиций:
   ```sql
   select  n.nspname
       ,v1.relname as table_name
       ,p1.relname as partition_name
       ,pg_table_size(v1.inhrelid) as part_size
       ,pg_total_relation_size(v1.inhrelid)-pg_table_size(v1.inhrelid) as part_idx_size
   from (
       select  p.relname, p.relnamespace, i.inhrelid
       from pg_inherits i, pg_class p
       where p.relkind='p'
         and p.relname='ticket_flights_hashed'
         and i.inhparent=p.oid
       ) v1, pg_class p1, pg_catalog.pg_namespace n
   where v1.relnamespace=n.oid
     and v1.inhrelid=p1.oid
   ;
    nspname  |      table_name       |      partition_name      | part_size | part_idx_size
   ----------+-----------------------+--------------------------+-----------+---------------
    bookings | ticket_flights_hashed | ticket_flights_hashed_p0 |  14319616 |      11124736
    bookings | ticket_flights_hashed | ticket_flights_hashed_p1 |  14344192 |      11272192
    bookings | ticket_flights_hashed | ticket_flights_hashed_p2 |  14311424 |      11141120
    bookings | ticket_flights_hashed | ticket_flights_hashed_p3 |  14295040 |      11149312
    bookings | ticket_flights_hashed | ticket_flights_hashed_p4 |  14311424 |      11223040
   (5 rows)
   ```
5. Кстати выполнил `analyze verbose`, в бд `demo` 
   И посмотрел на план выполнения тех двух запросов, которые упоминал выше - как они изменяются, если в текст запросов, вместо `ticket_flights` подставить `ticket_flights_hashed`
   
   План выполнения `Q1`: [plan2](/HomeWorks/Lesson20/plan2.txt)
   Тут, по костам - никакой разницы, относительно [варианта](/HomeWorks/Lesson20/plan.txt) с использованием несекционированной, heap-таблицы;
   
   Для запроса `Q2`, который - с условием `tf.ticket_no = '0005432661915'` как и ожидалось: индексный доступ показывает себя лучше.
   [План выполнения](/HomeWorks/Lesson20/plan3.txt) с обращением к `ticket_flights` в ипостаси heap-таблицы;
   [План выполнения](/HomeWorks/Lesson20/plan3_hash.txt) с обращением к `ticket_flights` в ипостаси hash-секционированной таблицы;


C range-секционированием, всё таки, интересно.
Попробовал так:
1. Имеющийся, по факту, в данных столбцов таблицы `ticket_flights` дапазон значений:
   ```sql
   [local]:5432 #postgres@demo > select min(to_number(t.ticket_no, '9999999999999')) as tmin, max(to_number(t.ticket_no, '9999999999999')) as tmax from ticket_flights t limit 10;
       tmin    |    tmax
   ------------+------------
    5432000987 | 5435999873
   
   [local]:5432 #postgres@demo > select min(flight_id) as fmin, max(flight_id) as fmax from ticket_flights t limit 10;                 fmin | fmax
   ------+-------
       1 | 33121
   (1 row)
   
   [local]:5432 #postgres@demo > \d ticket_flights
                        Table "bookings.ticket_flights"
        Column      |         Type          | Collation | Nullable | Default
   -----------------+-----------------------+-----------+----------+---------
    ticket_no       | character(13)         |           | not null |
    flight_id       | integer               |           | not null |
    fare_conditions | character varying(10) |           | not null |
    amount          | numeric(10,2)         |           | not null |
   ```
   Оба поля `ticket_no,flight_id` - not null;
2. Ну. Что. Создал таблицу:
   ```sql
   --Wrapper as a way to avoid: ERROR:  functions in partition key expression must be marked IMMUTABLE
   [local]:5432 #postgres@demo > CREATE OR REPLACE FUNCTION func1(p1 character)
   RETURNS numeric
   AS
   $BODY$
   select to_number($1, '9999999999999');
   $BODY$
   LANGUAGE sql
   IMMUTABLE;
   CREATE FUNCTION
   [local]:5432 #postgres@demo >    CREATE TABLE ticket_flights_range (
   ticket_no character(13) NOT NULL,
   flight_id integer NOT NULL,
   fare_conditions character varying(10) NOT NULL,
   amount numeric(10,2) NOT NULL,
   CONSTRAINT ticket_flights_amount_check CHECK ((amount >= (0)::numeric)),
   CONSTRAINT ticket_flights_fare_conditions_check CHECK (((fare_conditions)::text = ANY (ARRAY[('Economy'::character varying)::text, ('Comfort'::character varying)::text, ('Business'::character varying)::text])))
   )
   partition by range(func1(ticket_no), flight_id);
   CREATE TABLE
   CREATE TABLE
   [local]:5432 #postgres@demo > alter table ticket_flights_range add constraint ticket_flights_hashed_pk primary key (ticket_no, flight_id);
   ERROR:  unsupported PRIMARY KEY constraint with partition key definition
   DETAIL:  PRIMARY KEY constraints cannot be used when partition keys include expressions.
   [local]:5432 #postgres@demo > create unique index ticket_flights_hashed_uk on ticket_flights_range(ticket_no, flight_id);
   ERROR:  unsupported UNIQUE constraint with partition key definition
   DETAIL:  UNIQUE constraints cannot be used when partition keys include expressions.
   [local]:5432 #postgres@demo > create index ticket_flights_hashed_idx on ticket_flights_range(ticket_no, flight_id);
   CREATE INDEX
   ```
   Засада конечно, с pk|uk.
   Без выражений, на просто списки столбцов - создаётся, как показал пример выше, с хеш-секционированием.
   С другой стороны - резонно, кто его знает что за экспрешен могут понаписать, в общем случае.
   Хотя могли и потребовать детерменированности функций и возврата скаляра.
   Ну. Ладно. 
   Если уж костылить и извращаться, то можно, при наличии индекса на `ticket_no, flight_id` вркутить на `ticket_flights_range` for-each-row дмл-триггер.
   Которым, при вставке/апдейте строк в `ticket_flights_range` - контролировать вновь образуемые значения в `ticket_no, flight_id`: не дубли ли это.
2. Дальше выполнил:
   ```sql
   alter table ticket_flights_range attach partition ticket_flights for values from (5432000987, 1) to (5435999873, 33121);
   ```
   И оно - прекрасно выполнилось:
   ![1.png](/HomeWorks/Lesson20/1.png)
   Правда сплитить партицию: тоже [через перезаливку данных](https://stackoverflow.com/questions/63529097/how-to-divide-single-partition-into-two-different-partitions-in-postgresql-and-t) самой, расщепляемой партиции.
   split-partition пг не поддерживает.
3. Детач партиции - тоже выполнился успешно:
   ![2.png](/HomeWorks/Lesson20/2.png)

Дальше, решил не извращаться, с избеганиями использования строкового ключа секционирования в определениях партиций.
И, всё таки, побить таблицу используя строковые значения в определении условий разбиения.
Тогда, оно, хотя бы сможет сделать партишен-прунинг.
На перфоманс, в данном случае, это никак не повлияет, из за хорошо подходящих для запросов индексов.
Но, хотя бы можно будет увидеть что - да: партишен-прунинг делается.

Набил набор shell-команд, которыми готовятся sql-статементы определяющие партиции: [generator.sh](/HomeWorks/Lesson20/generator.sh)

В итоге получилась такая совокупность команд:
```sql
CREATE TABLE ticket_flights_range (
    ticket_no character(13) NOT NULL,
    flight_id integer NOT NULL,
    fare_conditions character varying(10) NOT NULL,
    amount numeric(10,2) NOT NULL,
    CONSTRAINT ticket_flights_amount_check CHECK ((amount >= (0)::numeric)),
    CONSTRAINT ticket_flights_fare_conditions_check CHECK (((fare_conditions)::text = ANY (ARRAY[('Economy'::character varying)::text, ('Comfort'::character varying)::text, ('Business'::character varying)::text])))
   )
   partition by range(ticket_no, flight_id);

create table ticket_flights_range_default partition of ticket_flights_range default;
create table ticket_flights_range_p1 partition of ticket_flights_range for values from ('0005432000987', 1) to ('0005432569011', 31341);
create table ticket_flights_range_p2 partition of ticket_flights_range for values from ('0005432569012', 1) to ('0005432949091', 32518);
create table ticket_flights_range_p3 partition of ticket_flights_range for values from ('0005432949092', 2) to ('0005433345622', 32936);
create table ticket_flights_range_p4 partition of ticket_flights_range for values from ('0005433345623', 3) to ('0005433716457', 32518);
create table ticket_flights_range_p5 partition of ticket_flights_range for values from ('0005433716458', 43) to ('0005434082374', 32702);
create table ticket_flights_range_p6 partition of ticket_flights_range for values from ('0005434082375', 9) to ('0005434435159', 32876);
create table ticket_flights_range_p7 partition of ticket_flights_range for values from ('0005434435160', 28) to ('0005434878084', 32998);
create table ticket_flights_range_p8 partition of ticket_flights_range for values from ('0005434878085', 245) to ('0005435214745', 33121);
create table ticket_flights_range_p9 partition of ticket_flights_range for values from ('0005435214746', 1038) to ('0005435626534', 33121);

insert into ticket_flights_range select * from ticket_flights;
alter table ticket_flights_range add constraint ticket_flights_hashed_pk primary key (ticket_no, flight_id);
-- to ask namely and only parent-table -------------
-- select count(*) from only ticket_flights_range; 
----------------------------------------------------
```

Из любопытства добавил default-секцию.
Плюс, как чувствовал что накосячу с вычислением диапазонов и всё аккуратно по партициям разложить, с первого подхода не получится.
Так и случилось.
Без дефаулт-секции получал ошибки вида:
```sql
[local]:5432 #postgres@demo > insert into ticket_flights_range select * from ticket_flights;                                       ERROR:  no partition of relation "ticket_flights_range" found for row
DETAIL:  Partition key of the failing row contains (ticket_no, ticket_no) = (0005434435160, 0005434435160).
```

С дефаулт-секцией: всё что не смогло смаппироваться в какую то регулярную секцию - улетело в дефаулт-секцию.
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
  and t.relname in ('ticket_flights','ticket_flights_range_default','ticket_flights_range_p1','ticket_flights_range_p2','ticket_flights_range_p3','ticket_flights_range_p4','ticket_flights_range_p5','ticket_flights_range_p6','ticket_flights_range_p7','ticket_flights_range_p8','ticket_flights_range_p9')
order by t.reltuples desc;
 nspname  |               db_object               |     est_rows     |  t_size  |  ti_size
----------+---------------------------------------+------------------+----------+-----------
 bookings | postgres.ticket_flights               |          1045730 | 71442432 | 113917952
 bookings | postgres.ticket_flights_range_p4      |           104998 |  7200768 |   7200768
 bookings | postgres.ticket_flights_range_p1      |           104997 |  7200768 |   7200768
 bookings | postgres.ticket_flights_range_p5      |           104997 |  7200768 |   7200768
 bookings | postgres.ticket_flights_range_p8      |           104997 |  7200768 |   7200768
 bookings | postgres.ticket_flights_range_p7      |           104996 |  7200768 |   7200768
 bookings | postgres.ticket_flights_range_p9      |           104995 |  7200768 |   7200768
 bookings | postgres.ticket_flights_range_p3      |           104995 |  7200768 |   7200768
 bookings | postgres.ticket_flights_range_p6      |           104994 |  7200768 |   7200768
 bookings | postgres.ticket_flights_range_p2      |           104994 |  7200768 |   7200768
 bookings | postgres.ticket_flights_range_default |           100763 |  6914048 |   6914048
(11 rows)
```

Планы выполнений демо-запросов, при использовании нормально range-секционированной ипостаси таблицы `ticket_flights`.
Тексты запросов - добавил в файлы с планами, чтобы не скроллить вверх.

`Q1` [опять же](/HomeWorks/Lesson20/plan3_q1_range.txt) - без разницы, относительно планов выполнения выше, по существу плана.
Т.е. перебирает все партиции, но не заходит ни в одну: `never executed`
Ну. Видимо такие данные перебираются, что приходится бегать по всем партициям.

По запросу `Q2` интереснее.
[План выполнения](/HomeWorks/Lesson20/plan3_q2_range.txt), если в запрос подставить range-секционированную таблицу показывает три вещи.
1. Партишен-прунинг - есть, при этом check-констрейнты я, умышленно, не навешивал, на партиции.
   Т.е. база ориентируется только по определениям партиций и `not null` на ключ секционирования, этого - уже достаточно, для прунинга секций.
   Параметр `enable_partition_pruning` по дефолту `on`. Включено то есть.
2. Уник-индекс, который обеспечивает pk-констрейнт, на `ticket_flights_range` - автоматически создался секционированным.
3. Поскольку используется хороший индексных доступ к данным из `ticket_flights_range` то что оно - секционированное, практически не меняет кост запроса, относительно варианта с heap-ипостасью таблицы `ticket_flights`
   Даже ухудшает немного.
   
Из любопытства, чтобы увидеть стоимости выполнения `Q2` при фуллскане heap-ипостаси `ticket_flights` и насколько этот кост уменьшает секционирование сделал такое:
1. Удалил pk-констрейнт с `ticket_flights_range`, [план выполнения](/HomeWorks/Lesson20/plan3_q2_range_wo_pk.txt) получился с костом `4366.93` и фуллсканом `ticket_flights_range_p2, ticket_flights_range_default`
2. Удалил pk-констрейнт c `ticket_flights`, [план выполнения](/HomeWorks/Lesson20/plan3_q2_range_fullscan.txt) получился с костом `21830.57` и фуллсканом `ticket_flights`
   Там ещё, время выполнения запроса есть, в файлах.
   Ну. Т.е., кратно больший кост.
   Т.е. если бы хорошего индекса и хорошего, для индекса, запроса к данным - не было, партиционированием может получится снизить кост выполнения запроса.
   Кроме того - партиционирование: хороший подход для организации ротирования (удаления), бэкапирования табличных данных.

Ещё, стало интересно - если оно такое: partition-aware, то оно и тогда - должно мочь, более-менее, в partition-wise join-ы.
Ну, по крайней мере - на лету, во время выполнения джойна двух секционированных таблиц и, если джойн делается по ключу секционирования - понимать: какие, для этого джойна, нужны/не нужны партиции, из входов джойна.

Решил пронаблюдать эксперементально, это дело, на примере `Q2` запроса.
В исходном `Q2` запросе, то с чем джойнится `ticket_flights`, т.е.: `flights_v` - это вью, с таким определением:
```sql
CREATE VIEW flights_v AS
 SELECT f.flight_id,
    f.flight_no,
    f.scheduled_departure,
    timezone(dep.timezone, f.scheduled_departure) AS scheduled_departure_local,
    f.scheduled_arrival,
    timezone(arr.timezone, f.scheduled_arrival) AS scheduled_arrival_local,
    (f.scheduled_arrival - f.scheduled_departure) AS scheduled_duration,
    f.departure_airport,
    dep.airport_name AS departure_airport_name,
    dep.city AS departure_city,
    f.arrival_airport,
    arr.airport_name AS arrival_airport_name,
    arr.city AS arrival_city,
    f.status,
    f.aircraft_code,
    f.actual_departure,
    timezone(dep.timezone, f.actual_departure) AS actual_departure_local,
    f.actual_arrival,
    timezone(arr.timezone, f.actual_arrival) AS actual_arrival_local,
    (f.actual_arrival - f.actual_departure) AS actual_duration
   FROM flights f,
    airports dep,
    airports arr
  WHERE ((f.departure_airport = dep.airport_code) AND (f.arrival_airport = arr.airport_code));
```
Ну. Подготовил секционированную версию таблицы `flights_range`, глядя на то как была определена исходная `flights`;
Тут, опять же важно что `flight_id` столбец имеет `NOT NULL`;
Cекционировал `flights_range` по диапазонам значений `flight_id`, заранее посмотрел максимальное/минимальное значения этого столбца, в исходной `flights`;
Загрузил в неё данные из `flights`
```sql
--drop table flights_range
CREATE TABLE flights_range (
    flight_id integer NOT NULL,
    flight_no character(6) NOT NULL,
    scheduled_departure timestamp with time zone NOT NULL,
    scheduled_arrival timestamp with time zone NOT NULL,
    departure_airport character(3) NOT NULL,
    arrival_airport character(3) NOT NULL,
    status character varying(20) NOT NULL,
    aircraft_code character(3) NOT NULL,
    actual_departure timestamp with time zone,
    actual_arrival timestamp with time zone,
    CONSTRAINT flights_check CHECK ((scheduled_arrival > scheduled_departure)),
    CONSTRAINT flights_check1 CHECK (((actual_arrival IS NULL) OR ((actual_departure IS NOT NULL) AND (actual_arrival IS NOT NULL) AND (actual_arrival > actual_departure)))),
    CONSTRAINT flights_status_check CHECK (((status)::text = ANY (ARRAY[('On Time'::character varying)::text, ('Delayed'::character varying)::text, ('Departed'::character varying)::text, ('Arrived'::character varying)::text, ('Scheduled'::character varying)::text, ('Cancelled'::character varying)::text])))
)partition by range(flight_id)
;
create table flights_range_default partition of flights_range default;
create table flights_range_p1 partition of flights_range for values from (1) to (2999);
create table flights_range_p2 partition of flights_range for values from (3000) to (5999);
create table flights_range_p3 partition of flights_range for values from (6000) to (8999);
create table flights_range_p4 partition of flights_range for values from (9000) to (11999);
create table flights_range_p5 partition of flights_range for values from (12000) to (14999);
create table flights_range_p6 partition of flights_range for values from (15000) to (17999);
create table flights_range_p7 partition of flights_range for values from (18000) to (20999);
create table flights_range_p8 partition of flights_range for values from (21000) to (23999);
create table flights_range_p9 partition of flights_range for values from (24000) to (26999);
create table flights_range_p10 partition of flights_range for values from (27000) to (29999);
create table flights_range_p11 partition of flights_range for values from (30000) to (32999);
create table flights_range_p12 partition of flights_range for values from (33000) to (maxvalue);
insert into flights_range select * from flights;
alter table flights_range add constraint flights_range_pk primary key (flight_id);
```
Создал вью `flights_v_range_parted` - подставил в текст запроса `flights_range`.
В текст запроса `Q2` вписал использование `flights_v_range_parted` и `flights_range`.
Т.е. вот так:
```sql
SELECT   to_char(f.scheduled_departure, 'DD.MM.YYYY') AS when,
         f.departure_city || ' (' || f.departure_airport || ')' AS departure,
         f.arrival_city || ' (' || f.arrival_airport || ')' AS arrival,
         tf.fare_conditions AS class,
         tf.amount
FROM     ticket_flights_range tf
         JOIN flights_v_range_parted f ON tf.flight_id = f.flight_id
WHERE    tf.ticket_no = '0005432661915'
ORDER BY f.scheduled_departure;
```

В таком запросе, особенно если `tf.ticket_no` - заиндексирован и имеет `not null`: `flights_v_range_parted` должен быть ведомым датасорсом.
`tf.ticket_no` - имеет `not null`, а вот индекс на него я удалил, для прошлого эксперимента.
Ну, опять же - это, т.е.: `tf.ticket_no` ключ секционирования и условие `tf.ticket_no = '0005432661915'` - должно, вместе с `not null` дать партишен-прунинг на `ticket_flights_range`

Выполнил `anayze verbose`, в demo-бд.
Ну. Если PWJ - работает, то сейчас, в плане выполнения, должны увидеть, в рантайме, перебор партиции `flights_range`, при отработке условия джойна `ON tf.flight_id = f.flight_id`
Но, при этом, оно, не заходя в партиции - будет понимать есть/не есть, в данной партиции от `flights_range`, искомые данные.
Ну, так и есть - [план выполнения](/HomeWorks/Lesson20/plan3_q2_PWS.txt).


В целом: ну, весьма не плохо.

Несколько стрёмно что, прямо в доке написано - не нужно делать много партиций, более десятков тысяч.
Потому что для работы с партицией пг грузит в память метаданные по партиции.
Но, может поправят в следующих версиях + для небольших проектов - вполне.
А может и для больших, если дадут вдумчиво отстроить ротирование данных и выводить из базы, в дамп-бэкапы партиции с архивным данными.
Есть разбиение на подсекции, т.е.: партиция таблицы - может быть сама партиционирована.
Ну, по факту партишен-вайз джойн-ов есть.

В оракле, конечно, работа с партициями заметно более продвинутая: есть сплитинг, мерджинг партиций, есть интервальное секционирование - автоматическое создание новых партиций.
Есть более спортивные методы преоборазования не секционированной таблицы в секционированную (и обратно).
Богаче набор методов секционирования + нет никакого ограничения на кол-во партиций.
Однако есть нюанс: `partition option` - доступна только в EE-редакции и не из коробки, а как extra-cost опция.



