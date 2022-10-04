Подготовка вм в YC
В своём каталоге - создать днс-зону, для днс-записей внутренней подсети, которая будет использоваться для интерконнекта, между виртуалками:

![1](/HomeWorks/project/1.png)

Завести в днс-зоне записи, в моём примере - частная подсеть:
![2](/HomeWorks/project/2.png)

При заведении вм - указывать им ip-адреса из внутренней сети:
![3](/HomeWorks/project/3.png)

PTR-записи будут определены автоматически.

Заготовка для выполнения команд на нодах:
```shell
eval "$(ssh-agent -s)"
ssh-add ~/otus/yacloud

export RED='\033[0;31m'
export GREEN='\033[0;32m'
export BLANK='\033[0m'
export HOST_USER="student"

run_remote_ssh()
{
  local HOST=$1
  local CMD=$2
  local EXIT_ON_ERROR=$4
  local PRINT_SSH_COMMAND=$3
  if [[ "$PRINT_SSH_COMMAND" == "ECHO" ]]; then
    echo -e "${GREEN}#$HOST_USER@$HOST:\n${CMD}${BLANK}"
  fi
  local S
  S=$(ssh -o StrictHostKeyChecking=no -o PasswordAuthentication=no student@"$HOST" "$CMD")
  RES=$?
  if [[ $RES -ne 0 ]] && [[ "$EXIT_ON_ERROR" == "EXIT_ON_ERROR" ]]; then
    echo -e "${RED}Error ${RES}${BLANK}" >&2
    echo -e "$S" >&2
    echo -e "#$HOST:\n$CMD" >&2
    exit $RES
  fi
  echo "$S"
}

v_hosts=( 158.160.14.15 158.160.11.86 )
for i in ${!v_hosts[@]}; do
    v_host=${v_hosts[$i]}
    v_cmd="date; hostname -f; whoami"
    run_remote_ssh "$v_host" "$v_cmd" "ECHO" #&
done
#wait
```




