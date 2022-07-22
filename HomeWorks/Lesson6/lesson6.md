 
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
2. Контроль состояния кластера. Текущая дата-директория: `/var/lib/postgresql/14/main`; Создание тестовой таблицы:
   ![6_3](/HomeWorks/Lesson6/6_3.png) 
3. В жизни: продукционную бд - конечно же не 1) оставливать будет сложно из за сопровотивления бизнеса и 2) бизнес будет принуждать к возможно меньшему даунтайму. 
   Поэтому и з любопытства перемещение датафайлов выполнил в две операции.
   ```shell
   sudo chown -R postgres:postgres /mnt/pgdata
   export PGCONF="/etc/postgresql/14/main/postgresql.conf"
   export RSYNC="/usr/bin/rsync"
   export SOURCE_DIR="/var/lib/postgresql/14/main"
   export TARGET_DIR="/mnt/pgdata"
   
   #### Directory deals
   cd
   cat /dev/null > ./temp.txt
   find "$SOURCE_DIR" -type d | tee -a ./temp.txt

   cat /dev/null > ./cmd.txt
   while read line; do 
         #echo "$line"
         v_str="$line"
         v_str=${v_str/#${SOURCE_DIR}/"$TARGET_DIR"}
         #echo "${line} -> ${v_str}"
         echo "mkdir ${v_str}" | tee -a "./cmd.txt"
   done < <(cat ./temp.txt)
   chmod u+x ./cmd.txt; ./cmd.txt

   #### if necessery
   find "$TARGET_DIR" -type f -delete; find "$TARGET_DIR" -type d -delete

   function rcopy(){
   local v_file="$1"
   local v_cmd=""
   local v_path=""
 
   #[ ! -d "$SOURCE_DIR" ] && exit 3
   #[ ! -d "$TARGET_DIR" ] && exit 4
 
   if [ -f "$v_file" ]; then
      v_path=$(dirname "$v_file" )
      v_path=${v_path/#${SOURCE_DIR}/"$TARGET_DIR"}
      v_cmd="${RSYNC} ${ROPTIONS} \"$v_file\" \"${v_path}\""
      #echo "$v_cmd"
      eval "$v_cmd"
   else
      exit 4
   fi
   }
   export -f rcopy

   #### initial copy, making files at remote-site
   DOP="3"
   export ROPTIONS="-pogtD --progress --inplace --partial -4 -v --checksum --ignore-existing"
   time find "$SOURCE_DIR" -type f | xargs -n 1 -P "$DOP" -d "\n" -I {} -t bash -c rcopy\ \"\{\}\"
 
   find "$SOURCE_DIR" -type f | wc -l
   find "$TARGET_DIR" -type f | wc -l

   #### control
   cat /dev/null > ./temp.txt
   for i in $( find "$SOURCE_DIR" -type f ); do
       v_file=$( basename "$i" )
       v_path=$(dirname "$i" )
       v_path=${v_path/#${SOURCE_DIR}/"$TARGET_DIR"}
       v_file="${v_path}/${v_file}"
       #echo "$i $v_file"
       v_md5_1=$( md5sum "$i" | cut -f 1 -d " " )
       v_md5_2="-"
       [ -f "$v_file" ] && v_md5_2=$( md5sum "$v_file" | cut -f 1 -d " " )
       echo "$i $v_file $v_md5_1 $v_md5_2" >> ./temp.txt
   done
   
   cat ./temp.txt | wc -l
   cat ./temp.txt | awk '{if ( $3 != $4 ){ printf "%s %s\n", $1, $2; }}' | wc -l
   ```
   Т.е.: не останавливая кластер - откопировал всё, в онлайне.
   После остановки кластера - докопировал, только изменения файлов, из исходной директори, в целевую:
   ```shell
   DOP="3"
   export ROPTIONS="-pogtD --progress --inplace --partial -4 -v --checksum --ignore-existing"
   time find "$SOURCE_DIR" -type f | xargs -n 1 -P "$DOP" -d "\n" -I {} -t bash -c rcopy\ \"\{\}\"
   ```
   ![6_4](/HomeWorks/Lesson6/6_4.png)


