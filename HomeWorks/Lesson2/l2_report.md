1. Создал вм в YC: ![ВМ](/HomeWorks/Lesson2/2_1.png)
2. Сгенерировал ссш-ключ, запустил и прописал ключ в ссш-агента: 
```ssh-keygen -t rsa -b 4096 -f yacloud -N ...
eval 'ssh-agent' #cygwin eval < <(ssh-agent)
ssh-add -v
ssh-add -l
```
3. Прописал публичную часть ключа в соот-е поле, в диалоге создания вм: ![public_key](/HomeWorks/Lesson2/2_2.png)
4. Выполнил, по [инструкции](https://www.postgresql.org/download/linux/ubuntu/) из док-ции установку 14-й версии postgresql:
```bash
sudo su root
apt update
apt upgrade
sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
apt-get update
apt-get install postgresql
pg_lsclusters
```
5. В документации вычитал про `.psqlrc` файл, выполнил:
```
[ -f "~/.psql_history" ] && touch "~/.psql_history"
cat << __EOF__ > ~/.psqlrc
\set AUTOCOMMIT off
\set COMP_KEYWORD_CASE preserve-upper
\set HISTFILE ~/.psql_history
\set HISTCONTROL none
\set HISTSIZE 1000
\set FETCH_COUNT 100
\set PROMPT1 '%m:%> %#%n@%/ %x> '
\set ROW_COUNT
__EOF__
cat ~/.psqlrc
```
Проверка: ![image](/HomeWorks/Lesson2/2_3.png)
6. Обратил внимание что ддл-команда, при `AUTOCOMMIT off`, открывает транзакцию и автоматом, по факту своего успешного выполнения - не коммитится:
```sql
[local]:5432 #postgres@postgres > create table persons(id serial, first_name text, second_name text);
CREATE TABLE
[local]:5432 #postgres@postgres *> commit
postgres-*#
postgres-*#
postgres-*# ;
COMMIT
[local]:5432 #postgres@postgres >
```
В параллельной скл-сессии таблицу, по `\dt` не было видно, до выполнения коммита, сразу после выполнения коммита - таблица появилась в листинге.
Несколько не привычный модус выполнения ддл-команд.
Это т.е., что, при выдаче какого нибудь `alter table drop column` или `create index` оно - пока не закоммитится, не видно никому? А если таблица большая и там работы на N-е кол-во гигабайт сделать надо при выполнении ддл-я, а потом что, rollback - всё откатывать? А как с совместным доступом к обрабатываемому ддл-ем ресурсу, к каталожным данным по ресурсу.
Не понятно. Везде вроде как, ддл-команды - должны коммитится сразу после своего успешного выполнения.
7. По умолчанию выставляется режим изоляции `read commited`:
```sql
[local]:5432 #postgres@postgres > show transaction isolation level;
 transaction_isolation
-----------------------
 read committed
(1 row)

[local]:5432 #postgres@postgres *> commit;
COMMIT
```
Этот уровень изоляции [комментируется](https://www.postgresql.org/docs/current/transaction-iso.html#XACT-READ-COMMITTED) так что дмл-запросы (включая select) видят данные в том состоянии в котором они были после последнего коммита перед запускаом данного дмл-запроса.
В комментарии, в документации, по последней ссылке, один момент показался особенно важным:
> UPDATE, DELETE, SELECT FOR UPDATE, and SELECT FOR SHARE commands behave the same as SELECT in terms of searching for target rows: they will only find target rows that were committed as of the command start time. 
> However, such a target row might have already been updated (or deleted or locked) by another concurrent transaction by the time it is found. In this case, the would-be updater will wait for the first updating transaction to commit or roll back (if it is still in progress). 
> If the first updater rolls back, then its effects are negated and the second updater can proceed with updating the originally found row. 
> If the first updater commits, the second updater will ignore the row if the first updater deleted it, otherwise it will attempt to apply its operation to the updated version of the row. 
> **The search condition of the command (the WHERE clause) is re-evaluated to see if the updated version of the row still matches the search condition.**
Правильно ли я понимаю: если, в read commited-моде сериалзиции, блокируемая тр-ция выдала свой запрос, с дорогим, в смысле стоимости выполнения, where-предложеним, встала в блокировку, то, после коммита в блокирующей тр-ции, у блокруемой тр-ции where-предложение будет выполняться по новой?
8. В моде сериализации read commited выполнил
   1. В 1-й sql-сессии выполнил:
```sql
postgres@postgresql1:/home/student$ psql
psql (14.4 (Ubuntu 14.4-1.pgdg20.04+1))
Type "help" for help.

[local]:5432 #postgres@postgres > insert into persons(first_name, second_name) values('sergey', 'sergeev');
INSERT 0 1
[local]:5432 #postgres@postgres *>
```
   2. Во 2-й скл-сессии выполнил:
```sql
[local]:5432 #postgres@postgres >
[local]:5432 #postgres@postgres > select * from persons;
 id | first_name | second_name
----+------------+-------------
  1 | ivan       | ivanov
  2 | petr       | petrov
(2 rows)

[local]:5432 #postgres@postgres *>
```
Обе скл-сессии начали и продолжают, к этому моменту времени транзакции, это видно по значку `*` в промпте
2-я скл-сессия не видит изменений сделанных 1-й скл-сессии, потому что эти изменения не были закоммичены к моменту запуска select-запроса в 2-й скл-сессии.
   3. В 1-й скл-сессии выполнил commit; Транзакция 1-й скл-сессии - закрылась.
   4. Во 2-й скл-сессии выполнил select-запрос к таблице. Новая запись - отобразилась, поскольку транзакция, создавшая эту, новую запись - была закоммичена до запуска данного select-статемента:
```sql
[local]:5432 #postgres@postgres *> select * from persons;
 id | first_name | second_name
----+------------+-------------
  1 | ivan       | ivanov
  2 | petr       | petrov
  3 | sergey     | sergeev
(3 rows)

[local]:5432 #postgres@postgres *>
```
