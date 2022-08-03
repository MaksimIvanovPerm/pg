1. Первое задание сформулировано так:
   ```
   Настройте сервер так, чтобы в журнал сообщений сбрасывалась информация о блокировках, удерживаемых более 200 миллисекунд. 
   Воспроизведите ситуацию, при которой в журнале появятся такие сообщения.
   ```
   [дока](https://www.postgresql.org/docs/current/runtime-config-logging.html#GUC-LOG-MIN-MESSAGES) про параметр `log_lock_waits`
   ![9_3](/HomeWorks/Lesson9/9_3.png)
   Для этого выполнил такие действия, открыл две скл-сессии,
   1. В одной скл-сессии:
      ```sql
      [local]:5432 #postgres@postgres > \c bmdb
      You are now connected to database "bmdb" as user "postgres".
      [local]:5432 #postgres@bmdb > create table testtab(id int, line text);
      CREATE TABLE
      [local]:5432 #postgres@bmdb > set application_name to sess2;
      SET
      [local]:5432 #postgres@bmdb > insert into testtab(id, line) values(1, 'line1');
      INSERT 0 1
      [local]:5432 #postgres@bmdb > insert into testtab(id, line) values(2, 'line2');
      INSERT 0 1
      [local]:5432 #postgres@bmdb > \echo :AUTOCOMMIT
      on
      [local]:5432 #postgres@bmdb > begin;
      BEGIN
      [local]:5432 #postgres@bmdb *> update testtab set line='qqq1' where id=1;
      UPDATE 1
      [local]:5432 #postgres@bmdb *>
      ```
   2. В другой скл-сессии:
      ```sql
      [local]:5432 #postgres@postgres > \c bmdb
      You are now connected to database "bmdb" as user "postgres".
      [local]:5432 #postgres@bmdb > set application_name to sess1;
      SET
      [local]:5432 #postgres@bmdb > update testtab set line='qqq1' where id=1;
      ```
2. Второе задание:
   ```
   Смоделируйте ситуацию обновления одной и той же строки тремя командами UPDATE в разных сеансах. 
   Изучите возникшие блокировки в представлении pg_locks и убедитесь, что все они понятны. 
   Пришлите список блокировок и объясните, что значит каждая.
   ```
   Дополнительно к двум скл-сессям выше, и не закрывая в них транзакции, открыл ещё один экран в скрин-е, в нём открыл ещё одну скл-сессию, выполнил:
   ```sql
   [local]:5432 #postgres@postgres > \c bmdb
   You are now connected to database "bmdb" as user "postgres".
   [local]:5432 #postgres@bmdb > set application_name to 'sess3';
   SET
   [local]:5432 #postgres@bmdb > begin;
   BEGIN
   [local]:5432 #postgres@bmdb *> update testtab set line='sss3' where id=1;
   ```
   Скл-сессия: закономерно повисла.
   Открыл ещё один screen-экран, скл-сессию, набрал и выполнил такой запрос:
   ```sql
      select  db.datname
             ,l.relation::regclass
             ,l.pid
             ,case when l.page is not null then concat(l.page,'/',l.tuple) 
              else null
              end as rowid
             ,l.locktype
             ,l.transactionid 
             ,l.mode
             ,l.granted
             ,pg_blocking_pids(l.pid) as blocker
      from  pg_locks l 
                     left join pg_database db 
                     on l.database=db.oid
      where 1=1
      order by l.pid, l.mode
      ;
   ```
   ![9_7](/HomeWorks/Lesson9/9_7.png)
   
   Ну. 
   Видно что скл-сессия, какая то, которую обслуживает серверный процесс `1132` - успешно получила все блокировки, эксключивные, в т.ч. `RowExclusiveLock`, на таблицу `testtab`.
   
   Дальше, есть ещё какая то скл-сессия, которую обслуживает серверный процесс `1187`.
   `1187` - открыл две транзакции, одна из них - на ту же таблицу `testtab`, на блок/строку, соотв-но 0/7;
   На что открыта вторая тр-ция - не знаю как посмотреть.
   Возможно, и скорее всего - что то системное.
   На одну из транзакций - `RowExclusiveLock` получен, на другую - не получен.
   В блокерах стоит скл-сессия с `pid=1132`
   
   Есть третья скл-сессия с `pid=1312`, которую лочит скл-сессия с `pid=1187`;
   Которую, в свою очередь, лочит скл-сессия с `pid=1132`
   Третья скл-сессия пытается получить эксклюзивный доступ к той же строке - в том же блоке, в том же тупле: `0/7` таблицы `testtab`, и пока что не получила этого доступа.
   
   Запросом в `pg_catalog.pg_stat_activity` картина дополняется деталями, и получается что это всё - очередь из транзакционно заблокированных скл-сессий, конкрурирющих за доступ к дной и той же строке, одной и той же таблицы.
3. Третье задание:
   ```
   Воспроизведите взаимоблокировку трех транзакций. 
   Можно ли разобраться в ситуации постфактум, изучая журнал сообщений?
   ```
   Выполнил, в одной скл-сессии (сразу, с итоговой ошибкой):
   ```sql
   [local]:5432 #postgres@bmdb > set application_name to task3_sess1;
   SET
   [local]:5432 #postgres@bmdb > begin;
   BEGIN
   [local]:5432 #postgres@bmdb *>  update testtab set line='task3_sess1' where id=1;
   UPDATE 1
   [local]:5432 #postgres@bmdb *>  update testtab set line='task3_sess1' where id=2;
   ERROR:  deadlock detected
   DETAIL:  Process 1132 waits for ShareLock on transaction 23384783; blocked by process 1187.
   Process 1187 waits for ShareLock on transaction 23384782; blocked by process 1132.
   HINT:  See server log for query details.
   CONTEXT:  while updating tuple (0,2) in relation "testtab"
   [local]:5432 #postgres@bmdb !>
   ```
   Во второй скл-сессии было выполнено:
   ```sql 
   [local]:5432 #postgres@bmdb > set application_name to task3_sess2;
   SET
   [local]:5432 #postgres@bmdb > begin;
   BEGIN
   [local]:5432 #postgres@bmdb *> update testtab set line='task3_sess2' where id=2;
   UPDATE 1
   [local]:5432 #postgres@bmdb *> update testtab set line='task3_sess2' where id=1;
   UPDATE 1
   [local]:5432 #postgres@bmdb *>
   ```
   В логе кластера появились сообщения:
   ![9_8](/HomeWorks/Lesson9/9_8.png)
   Т.е. сначала, ещё до дедлока, когда вторая скл-сессия выдала `update testtab set line='task3_sess2' where id=1;` 
   отработала нотификация, по долгому удержанию лока:
   ```
   2022-08-02 20:14:17.178 UTC [1187-23384783-task3_sess2] postgres@bmdbLOG:  process 1187 still waiting for ShareLock on transaction 23384782 after 200.133 ms
   2022-08-02 20:14:17.178 UTC [1187-23384783-task3_sess2] postgres@bmdbDETAIL:  Process holding the lock: 1132. Wait queue: 1187.
   2022-08-02 20:14:17.178 UTC [1187-23384783-task3_sess2] postgres@bmdbCONTEXT:  while updating tuple (0,11) in relation "testtab"
   2022-08-02 20:14:17.178 UTC [1187-23384783-task3_sess2] postgres@bmdbSTATEMENT:  update testtab set line='task3_sess2' where id=1;
   ```
   Тут интересна заявка что `pid=1187` хочет получить `ShareLock` но на тот момент времени это не возможно по работе тр-ции `xid=23384782`, которую ведёт `pid=1132`
   К этому - ниже ещё будет возврат.
   Затем субд детектировала дедлок, и разрешила взаимоблокировку, по таймату в `deadlock_timeout`:
   ```
   2022-08-02 20:14:22.284 UTC [1132-23384782-task3_sess1] postgres@bmdbLOG:  process 1132 detected deadlock while waiting for ShareLock on transaction 23384783 after 200.106 ms
   ```
   Судя по тому что, в скл-сессии, маркированной как `task3_sess2`, т.е. скл-сессия с `pid=1187` - последний апдейт - выполнился полностью: субд просто тупо абортнула всю транзакцию вошедшую в дедлок последней.
   Т.е. абортнуло транзакцию в `1132-23384782-task3_sess1`
   На это, так же есть два намёка.
   Первый
   ![9_9](/HomeWorks/Lesson9/9_9.png)
   Второй:
   ![9_10](/HomeWorks/Lesson9/9_10.png)
   Так оно показывает сфейлившийся транзакционный блок.
   Плюс, судя по записям в логе кластера: `pid=1187` таки получил свой лок, который не мог получить до завершения `xid=23384782`
   Ну т.е. её не стало `xid=23384782`
   
   Ну, с такими знанями, что пг - срубает транзакцию вошедшую в дедлок последней, расшифровать записи в логе кластера вполне возможно и однозначно.
   Особенно, если по параметру `log_line_prefix` настроен вывод с записи лога атрибутов скл-сессий: пид, xid, аппликейшен-нейм.
   ```
   2022-08-02 20:14:22.284 UTC [1132-23384782-task3_sess1] postgres@bmdbLOG:  process 1132 detected deadlock while waiting for ShareLock on transaction 23384783 after 200.106 ms
   ```
   Это сообщение как раз по активность в транзакции, в скл-сессии вошедшей в дедлок последней.
   Ну её транзакцию и отменило, с отчётом - какие именно скл-статементы, на этот момент времени, в какой именно скл-сесси выполнялись.
   Дальше записи про работу скл-сессии с `pid=1187`
   Для завершения гештальта:
   ![9_11](/HomeWorks/Lesson9/9_11.png)
   ![9_12](/HomeWorks/Lesson9/9_12.png)
4. 4-е задание:
   ```
   Могут ли две транзакции, выполняющие единственную команду UPDATE одной и той же таблицы (без where), заблокировать друг друга?
   Попробуйте воспроизвести такую ситуацию.
   ```
   Ну. 
   Первой мыслью было что что нибудь на дмл-обработке мастер-таблицы, особенно в том случае когда в детайл-таблице fk - без индекса, должно создавать хорошие условия для образования дедлоков.
   Погуглил. 
   Да, полно статей на именно такие случаи.
   Но, [оказалось что всё - ещё проще](https://stackoverflow.com/questions/10245560/deadlocks-in-postgresql-when-running-update#10246052), всему причина - обработка апдейт-командами табличных строк в неопределённом их порядке.
   В том смысле что, в рамках работы какого то конкретного update-статемента, который обрабатывает несколько строк - какая, из этих табличная строк будет обраота сначала, а какая потом - вот этот порядок: не определён.
   Кстати, получается что и для delete-статементов: это тоже должно быть актуально.
