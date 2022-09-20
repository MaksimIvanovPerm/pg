psql -d demo -t -c "select ticket_no, flight_id from ticket_flights order by 1, 2;" > /tmp/temp.txt
v_count="1"
v_count2="1"
v_trshld="105000"
v_x=""
v_tf=()
while read line; do
      if [ "$v_count2" -eq "1" ]; then
         v_x=$(echo -n "$line" | cut -f 1 -d "|" | tr -d [:space:] )
         echo "$v_count2 $v_x"
         v_tf+=($v_x)
      fi
      v_count=$((v_count+1))
      v_count2=$((v_count2+1))
      if [ "$v_count" -eq "$v_trshld" ]; then
         v_x=$(echo -n "$line" | cut -f 1 -d "|" | tr -d [:space:] )
         echo "$v_count2 $v_x"
         v_tf+=($v_x)
         v_count="1"
      fi
done < <(cat /tmp/temp.txt)

v_x=""
v_y=""
v_str=""
cat /dev/null > /tmp/temp2.txt
for i in ${!v_tf[@]}; do
    echo "${v_tf[$i]}"
    if [ "$i" -eq "0" ]; then
       v_x="${v_tf[$i]}"
    else
       v_y="${v_tf[$i]}"
       v_y=$( echo -n ${v_y} | sed -r "s/^0+//" )
       v_y=$((v_y-1))
       v_y="000${v_y}" #yes, I know
       v_str=$(echo -n "select min(flight_id) as co1l, max(flight_id) as col2 from ticket_flights where ticket_no>='${v_x}' and ticket_no<'${v_y}';")
       v_str=$( psql -d demo -t -q -c "$v_str" | tr -d [:cntrl:] )
       v_low=$( echo -n "$v_str" | cut -f 1 -d "|" )
       v_hi=$( echo -n "$v_str" | cut -f 2 -d "|" )
       echo "${v_x} ${v_y} ${v_low} ${v_hi}" | tee -a "/tmp/temp2.txt"
       v_x="${v_tf[$i]}"
    fi
done

cat "/tmp/temp2.txt" | awk '{printf "create table ticket_flights_range_p%d partition of ticket_flights_range for values from ('\''%s'\'', %d) to ('\''%s'\'', %d);\n", NR, $1, $3, $2, $4;}'
