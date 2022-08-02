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
