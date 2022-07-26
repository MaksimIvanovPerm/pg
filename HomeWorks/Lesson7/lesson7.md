[Дока](https://www.postgresql.org/docs/current/ddl-schemas.html) по концепциям темы схем, ролей, пользователей.
По пунктам ДЗ:
1. Пункт 1 ДЗ: cоздайте новый кластер PostgresSQL 13 (на выбор - GCE, CloudSQL)
![7_1](/HomeWorks/Lesson7/7_1.png)
2. Пункты 2-11 ДЗ: 
   ![7_2](/HomeWorks/Lesson7/7_2.png) 
   
   [дока](https://www.postgresql.org/docs/14/sql-grant.html) по grant-команде в пг.
   В [доке про схемы](https://www.postgresql.org/docs/14/ddl-schemas.html), так же, сказано что:
   ```
   In addition to public and user-created schemas, each database contains a pg_catalog schema, which contains the system tables and all the built-in data types, functions, and operators. 
   pg_catalog is always effectively part of the search path. 
   If it is not named explicitly in the path then it is implicitly searched before searching the path's schemas. 
   This ensures that built-in names will always be findable. 
   However, you can explicitly place pg_catalog at the end of your search path if you prefer to have user-defined names override built-in names.
   ```
   Судя по всему: `pg_catalog` - не одна такая, служебная схема, которая, автоматически есть и ведётся в каждой базе данных, внутри пг-кластера.
   Есть ещё `information_schema`, про которую [говорится](https://www.postgresql.org/docs/14/infoschema-schema.html):
   ```
   The information schema itself is a schema named information_schema. 
   This schema automatically exists in all databases. 
   The owner of this schema is the initial database user in the cluster, 
   and that user naturally has all the privileges on this schema, 
   including the ability to drop it (but the space savings achieved by that are minuscule).
   
   By default, the information schema is not in the schema search path, 
   so you need to access all objects in it through qualified names. 
   Since the names of some of the objects in the information schema are generic names that might occur in user applications, 
   you should be careful if you want to put the information schema in the path
   ```
   [Справка](https://www.postgresql.org/docs/14/information-schema.html) по объектам схемы `information_schema`
3. Пункты 12-14 ДЗ.
   Некоторое время тупил над сбоем подключения, под бд-аккаунтом `testread`
   Потом вспомнил что говорилось про `pg_hab.conf`, [дока](https://www.postgresql.org/docs/14/auth-pg-hba-conf.html)
   Поправил запись в файле, про подкючение обычных бд-аккаунтов в субд, в auth-method указал md5
   В поле `USER`, в этой записи, в `pg_hba.conf` забил только `testread`
   Т.е., всем остальным, не суперпользовательским аккаунтам бд, доступ перекрыл.
   ```shell
   [local]:5432 #postgres@testdb > create user testread password '123';
   CREATE ROLE
   [local]:5432 #postgres@testdb > grant readonly to testread;
   GRANT ROLE
   [local]:5432 #postgres@testdb > \q
   postgres@postgresql1:~$ cat ~/.bashrc
   #echo "Welcome again!"
   PGCONF=$( psql -t -c "show config_file;" | tr -d [:cntrl:] )
   export PGCONF="$PGCONF"
   
   
   HBAFILE=$( psql -t -c "show hba_file;" | tr -d [:cntrl:] )
   export HBAFILE="$HBAFILE"
   postgres@postgresql1:~$ HBAFILE=$( psql -t -c "show hba_file;" | tr -d [:cntrl:] ); export HBAFILE="$HBAFILE"
   postgres@postgresql1:~$ grep "testread" $HBAFILE
   local   testdb          testread                                md5
   postgres@postgresql1:~$ export PGPASSWORD="123"
   postgres@postgresql1:~$ psql -d testdb -U testread
   psql (14.4 (Ubuntu 14.4-1.pgdg20.04+1))
   Type "help" for help.
   
   [local]:5432 >testread@testdb > \conninfo
   You are connected to database "testdb" as user "testread" via socket in "/var/run/postgresql" at port "5432".
   [local]:5432 >testread@testdb >
   ```
   Из любопытства посмотрел что да - остальные простые бд-аккаунты: обламываются с подключением:
   ![7_3](/HomeWorks/Lesson7/7_3.png)
   Дописал, через запятую, имя бд-аккаунта в эту самую строку, в `pg_hba.conf` - подключение под `testread1`: заработало.
4. Пункты 15-19 ДЗ.
   Ну, сбоит запрос `select * from t1;`:
   ![7_5](/HomeWorks/Lesson7/7_5.png)
   Связано это с тем что, по умолчанию `search_path` имеет значение `"$user", public`
   Поэтому, когда создавалась таблица `t1` и явно не было указано - в какой схеме её создавать и в `search_path` схема `testnm` не была указана, в префиксной позиции, таблица создалась в схеме `public`
   Грантов на объекты, в схеме `public`, у бд-аккаунта нет никаких, соответственно читать таблицу `public.t1` бд-аккаунт `testnm` не может;
