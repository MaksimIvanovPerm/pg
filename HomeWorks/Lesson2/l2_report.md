1. Создал вм в YC: ![ВМ](/HomeWorks/Lesson2/2_1.png)
2. Сгенерировал ссш-ключ, запустил и прописал ключ в ссш-агента: 
```ssh-keygen -t rsa -b 4096 -f yacloud -N ...
eval 'ssh-agent' #cygwin eval < <(ssh-agent)
ssh-add -v
ssh-add -l
```
3. Прописал публичную часть ключа в соот-е поле, в диалоге создания вм: ![public_key](/HomeWorks/Lesson2/2_2.png)
4. Выполнил, по [инструкции](https://www.postgresql.org/download/linux/ubuntu/) из док-ции установку 14-й версии postgresql:
```
sudo su root
apt update
apt upgrade
sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
apt-get update
apt-get install postgresql
```
