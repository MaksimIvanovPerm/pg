 
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
