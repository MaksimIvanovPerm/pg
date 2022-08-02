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
3. 
   
