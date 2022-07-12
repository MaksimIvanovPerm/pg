1.  Создал вторую вм в YC: ![ВМ](/HomeWorks/Lesson3/3_1.png)
2.  Подключился к новой вм, выполнил:
    ```shell
    sudo su root
    apt update; apt upgrade -y
    apt install ca-certificates curl gnupg lsb-release net-tools screen -y
    ```
    Установка докер-а, [документация, для убунту](https://docs.docker.com/engine/install/ubuntu/)
    Подключение пакетного репозитория
    ```shell
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update
    apt-get install docker-ce docker-ce-cli containerd.io docker-compose-plugin
    ```
    Проверка, по `docker run hello-world`: ![im3](/HomeWorks/Lesson3/3_2.png)
3.  Выполнил:
    ```shell
    root@postgresql3:/home/student# mkdir -p /var/lib/postgres/
    root@postgresql3:/home/student# id student
    uid=1000(student) gid=1001(student) groups=1001(student)
    root@postgresql3:/home/student# chown -R student:student /var/lib/postgres/
    root@postgresql3:/home/student# usermod -aG docker student
    root@postgresql3:/home/student# id student
    uid=1000(student) gid=1001(student) groups=1001(student),998(docker)
    ```
    Под ОС-пользователем `student` выполнил
    ```shell
    student@postgresql3:~$ docker run --name pg-docker --network pg-net -e POSTGRES_PASSWORD=postgres -d -p 5432:5432 -v /var/lib/postgres:/var/lib/postgresql/data postgres:14
    Unable to find image 'postgres:14' locally
    14: Pulling from library/postgres
    461246efe0a7: Pull complete
    8d6943e62c54: Pull complete
    558c55f04e35: Pull complete
    186be55594a7: Pull complete
    f38240981157: Pull complete
    e0699dc58a92: Pull complete
    066f440c89a6: Pull complete
    ce20e6e2a202: Pull complete
    c0f13eb40c44: Pull complete
    3d7e9b569f81: Pull complete
    2ab91678d745: Pull complete
    ffc80af02e8a: Pull complete
    f3a57056b036: Pull complete
    Digest: sha256:ae12ee9329e599d73f867f2878657422ab93f80dba695e193c2b815e876d08d6
    Status: Downloaded newer image for postgres:14
    1e445a69996f6014e7af03de392482273550f5c2cafa2a8a09eddd0021bb890c
    student@postgresql3:~$ docker ps -a
    CONTAINER ID   IMAGE         COMMAND                  CREATED          STATUS                      PORTS                                       NAMES
    1e445a69996f   postgres:14   "docker-entrypoint.s…"   15 minutes ago   Up 15 minutes               0.0.0.0:5432->5432/tcp, :::5432->5432/tcp   pg-docker
    38ebe10a99b0   hello-world   "/hello"                 56 minutes ago   Exited (0) 56 minutes ago                                               tender_almeida
    student@postgresql3:~$
    ```
    Зашёл в докер-контейнер `pg-docker` увидел что база - есть, внутри:
    ![im4](/HomeWorks/Lesson3/3_3.png)
4.  Аналогично запустил второй докер-контейнер `pg-client`. 
    Только папку, для маппинга из/в контейнер - сделал и задал другую.
    И задал другой порт, чтобы случайно не подключится к экземпляру pg-бд в этом же контейнере.
    ```shell
    root@postgresql3:/home/student# mkdir -p /var/lib/postgres-client/
    root@postgresql3:/home/student# chown -R student:student /var/lib/postgres-client/
    ```
    ```shell
    docker run --name pg-client --network pg-net -e POSTGRES_PASSWORD=postgres -d -p 5433:5433 -v /var/lib/postgres-client:/var/lib/postgresql/data postgres:14
    student@postgresql3:~$ docker run --name pg-client --network pg-net -e POSTGRES_PASSWORD=postgres -d -p 5433:5433 -v /var/lib/postgres-client:/var/lib/postgresql/data postgres:14
    b32c329e0f570b72f6c50f51029b3deb9a26e440157b2acf5f62df4cb20313b7
    student@postgresql3:~$ docker ps -a
    CONTAINER ID   IMAGE         COMMAND                  CREATED             STATUS                         PORTS                                                 NAMES
    b32c329e0f57   postgres:14   "docker-entrypoint.s…"   11 seconds ago      Up 10 seconds                  5432/tcp, 0.0.0.0:5433->5433/tcp, :::5433->5433/tcp   pg-client
    1e445a69996f   postgres:14   "docker-entrypoint.s…"   33 minutes ago      Up 33 minutes                  0.0.0.0:5432->5432/tcp, :::5432->5432/tcp             pg-docker
    38ebe10a99b0   hello-world   "/hello"                 About an hour ago   Exited (0) About an hour ago                                                         tender_almeida
    ```
    Поподключался из контейнера `pg-client`, в `pg-docker`:
    ![im4](/HomeWorks/Lesson3/3_4.png)
    Не очень только понял - как определить ип-адрес, к которому надо подключаться. 
    Взял просто хостовые ип-шники. Судя по правилам маппирования портов, в выводе docker ps -a - достаточно обратится на любой доступный ип хостовой ОС-и и на порт соответствующий контейнеру.
5.  Зашёл с другой вм, из YC, создал таблицу:
    ![im4](/HomeWorks/Lesson3/3_62.png)
    ![im5](/HomeWorks/Lesson3/3_7.png)
    Потом сообразил что по заданию - надо подключаться вообще извне клауд-инстансов.
    Ну поставил себе на домашний компьютер цигвин, в него поставил его стандратный пакет `postgresql-client` подключился, увидел таблицу, её строки:
    ![im5](/HomeWorks/Lesson3/3_8.png)
6.  Остановил и удалил докер-контейнер `pg-docker`:
    ```shell
    docker ps -a
    docker stop -t 1 pg-docker
    docker rm pg-docker
    docker ps -a
    sudo ls -lthr /var/lib/postgres/
    ```
    ![im5](/HomeWorks/Lesson3/3_9.png)
    [Дока](https://docs.docker.com/engine/reference/commandline/rm/) по cli-опциям docker-утилиты.
    Создал контейнер `pg-docker` заново. 
    Зашёл во вновь созданный контейнер, поскольку датадир-я: не удалялась и правило маппинга хост-директории в контейнер - осталось тем же: физическая компонента pg-инстаном увиделась, примонтировалась, и таблица и её данные - видны:
    ![im5](/HomeWorks/Lesson3/3_10.png)
    Что, на мой взгляд, несколько странно.
    Ибо остановка контейнера по `docker stop -t 1 pg-docker` - вроде как не очень похожа и распологает к корректной остановке экземпляра субд внутри контейнера.
    Когда и как pg-субд успела засинкаться и согласованно закрыться.

[Занятная статья.](https://citizix.com/running-postgresql-14-with-docker-and-docker-compose/)
