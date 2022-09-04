 
Тематические ссылки:
1. [https://habr.com/ru/company/veeam/blog/508426/](https://habr.com/ru/company/veeam/blog/508426/) - тут именно про сам xfs-функционал `reflink`
2. [О провиженинге тестовых баз](https://habr.com/ru/post/542366/) - тут больше про саму тему CoW-подхода к провиженингу тестовых баз.
3. man-ы по xfs и вот такая [замечательная pdf-ка](http://ftp.ntu.edu.tw/linux/utils/fs/xfs/docs/xfs_filesystem_structure.pdf)

Действия.
Добавляем, в ОС-ь, новое дисковое уст-во, создаём, на нём, xfs, с поддержкой reflink, монтируем.
```shell
mkfs.xfs -b size=4096 -m reflink=1,crc=1 /dev/vdb
xfs_info /dev/vdb
mount -t xfs -o noatime,nodiratime /dev/vdb /mnt/postgres
echo "/dev/vdb  /mnt/postgres xfs noatime,nodiratime 0 0" >> /etc/fstab
mkdir -p /mnt/postgres/14/main
mkdir -p /mnt/postgres/14/main_clone
chown -R postgres:postgres /mnt/postgres/
chmod -R 700 /mnt/postgres/
```

Создаём, два, пг-кластера, с дата-директориями в `/mnt/postgres/14/main_clone` и `/mnt/postgres/14/main`
Соответственно именования пг-кластеров: `main_clone, main`
Порты придётся задать разные, кластерам.

пг-кластер `main`: типа клонируемый. В практике это может быть физический standby, от какого то продового кластера.
пг-кластер `main_clone`: типа будет клон, от main-а

Концепция, на примере одного файла:
![1.png](/HomeWorks/xfs_cow/1.png)
