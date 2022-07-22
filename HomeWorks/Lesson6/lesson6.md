 
1. Присоединил к вм дополнительный диск, на 8Гб: ![6_1](/HomeWorks/Lesson6/6_1.png)
   Выполнил:
   ```shell
   (echo n; echo p; echo ""; echo ""; echo ""; echo w) | fdisk /dev/vdb
   fdisk -l /dev/vdb
   ```
   Выполнил:
   ```shell
   root@postgresql1:~# mkfs.xfs /dev/vdb1
   meta-data=/dev/vdb1              isize=512    agcount=4, agsize=524224 blks
            =                       sectsz=4096  attr=2, projid32bit=1
            =                       crc=1        finobt=1, sparse=1, rmapbt=0
            =                       reflink=1
   data     =                       bsize=4096   blocks=2096896, imaxpct=25
            =                       sunit=0      swidth=0 blks
   naming   =version 2              bsize=4096   ascii-ci=0, ftype=1
   log      =internal log           bsize=4096   blocks=2560, version=2
            =                       sectsz=4096  sunit=1 blks, lazy-count=1
   realtime =none                   extsz=4096   blocks=0, rtextents=0
   root@postgresql1:~# mkdir /mnt/pgdata
   root@postgresql1:~# mount -t xfs -o noatime,nodiratime /dev/vdb1 /mnt/pgdata
   root@postgresql1:~# cat /proc/mounts | grep "/mnt/pgdata"
   /dev/vdb1 /mnt/pgdata xfs rw,noatime,nodiratime,attr2,inode64,logbufs=8,logbsize=32k,noquota 0 0
   root@postgresql1:~# echo "/dev/vdb1 /mnt/pgdata xfs noatime,nodiratime 0 0" >> /etc/fstab
   root@postgresql1:~# shutdown -r now
   ```
   ![6_2_1](/HomeWorks/Lesson6/6_2_1.png)
