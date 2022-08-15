 
Полезные статьи:
1. [статья про настройку памяти, sysctl для пг](https://habr.com/ru/post/458860/) - комментарии на порядок полезнее самой статьи.
   [официоз от пг-комьюнити](https://www.postgresql.org/docs/current/kernel-resources.html)
3. [референс]([https://www.postgresql.org/docs/current/kernel-resources.html](https://www.kernel.org/doc/html/latest/admin-guide/sysctl/index.html)) по параметрам линукс-ядра.
4. [прикольная справка по параметрам конф-ции пг](https://postgresqlco.nf/doc/ru/param/effective_cache_size/)
5. Отличная вещь для пг, прямо таки - awr-like approach [pg_profiler](https://github.com/zubkov-andrei/pg_profile)

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
   [make_snap.sh]()
