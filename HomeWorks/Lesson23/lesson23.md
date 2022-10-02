Понял ДЗ таким образом: по легенде - выполнять скл-запрос
```sql
SELECT G.good_name, sum(G.good_price * S.sales_qty)
FROM goods G
INNER JOIN sales S ON S.good_id = G.goods_id
GROUP BY G.good_name;
```

Стало слишком дорого.
Соответственно надо чтобы, в витрине данных актуальность итоговых данных по продажам каждого конкретного продукта обновлялась, так сказать - инткрементально.
Т.е.: вот есть в витрине данных итоговая цифра, по выручке с продаж какого то конкретного товара и вот в таблицу с данными по продахам - прилетел какой то дмл, который как то изменяет данные по продажам этого товара.
Ну, например: новые продажи, изменение старых продаж, удаление старых продаж.

Так пусть дмл-триггер высчитывает выручку по изменениям которым этого, конкретного дмл-я и плюсует(или вычитает, смотря - что за изменение) в итоговую цифру в витрине.

Ну. Накодировал такую триггерную ф-цию и такой триггер:
```sql
CREATE OR REPLACE FUNCTION func1() 
RETURNS TRIGGER
AS
$$
DECLARE
    v_new_sales_rec       sales%rowtype := NEW;
    v_old_sales_rec       sales%rowtype := OLD;
    v_new_good_rec        goods%rowtype;
    v_old_good_rec        goods%rowtype;
    v_new_gsm_rec         good_sum_mart%rowtype;
    v_old_gsm_rec         good_sum_mart%rowtype;
    v_empty_flag          integer := 0;
    v_old_empty_flag      integer := 0;
    v_delta               integer;
BEGIN
    select * into v_new_good_rec from goods g where g.goods_id=v_new_sales_rec.good_id;
    begin
        --https://www.postgresql.org/docs/14/plpgsql-statements.html
        select gsm.* into strict v_new_gsm_rec from good_sum_mart gsm where gsm.good_name=v_new_good_rec.good_name;
        v_empty_flag := 1;
    exception
            when no_data_found then null;
    end;
    
    if v_empty_flag = 0 then
       v_new_gsm_rec.good_name:= v_new_good_rec.good_name;
       select sum(s.sales_qty) into v_new_gsm_rec.sum_sale from sales s where s.good_id=v_new_sales_rec.good_id;
       --Не понятно почему надо минусить данные от текущей тр-ции. При том что она - ещё не закоммитилась. 
       --Типа - триггер уже видит, в таблице, изменения от текущей тр-ции?
       v_new_gsm_rec.sum_sale := (v_new_gsm_rec.sum_sale-v_new_sales_rec.sales_qty)*v_new_good_rec.good_price;
    end if;
    
    if (TG_OP = 'INSERT') then
           raise info 'TG_OP Ins; empty_flag: %, good_id: %, sales_qty: %, price: %;', v_empty_flag, v_new_sales_rec.good_id, v_new_sales_rec.sales_qty, v_new_good_rec.good_price; 
           v_new_gsm_rec.sum_sale:=v_new_gsm_rec.sum_sale+(v_new_sales_rec.sales_qty*v_new_good_rec.good_price);
           if v_empty_flag = 0 then
               insert into good_sum_mart(good_name, sum_sale) values(v_new_gsm_rec.good_name, v_new_gsm_rec.sum_sale);
           else
               update good_sum_mart set sum_sale=v_new_gsm_rec.sum_sale where good_name=v_new_gsm_rec.good_name;
           end if;
    elsif (TG_OP = 'UPDATE') then
           raise info 'TG_OP Upd; empty_flag: %, good_id: %, sales_qty: %, price: %;', v_empty_flag, v_new_sales_rec.good_id, v_new_sales_rec.sales_qty, v_new_good_rec.good_price; 
           if ( v_old_sales_rec.good_id != v_new_sales_rec.good_id ) then
                raise info 'TG_OP Upd; old.good_id %, new.good_id %; o/n sales_qty: the same', v_old_sales_rec.good_id, v_new_sales_rec.good_id;
                select * into v_old_good_rec from goods g where g.goods_id=v_old_sales_rec.good_id;
                v_old_empty_flag := 0; --типа: надеемся что в good_sum_mart - уже есть строка с данными по старому продукту.
                begin
                    select gsm.* into strict v_old_gsm_rec from good_sum_mart gsm where gsm.good_name=v_old_good_rec.good_name;
                    v_old_gsm_rec.sum_sale := v_old_gsm_rec.sum_sale - (v_old_sales_rec.sales_qty*v_old_good_rec.good_price);
                    update good_sum_mart set sum_sale=v_old_gsm_rec.sum_sale where good_name=v_old_gsm_rec.good_name;
                exception when no_data_found then v_old_empty_flag := 1;
                end;
                
                if v_old_empty_flag = 1 then
                   -- нет, не было. Ну. Надо вставить. Помним что триггер: уже видит результат выполнения апдейта над sales;
                   select sum(s.sales_qty) into v_old_gsm_rec.sum_sale from sales s where s.good_id=v_old_sales_rec.good_id;
                   v_old_gsm_rec.sum_sale  := v_old_gsm_rec.sum_sale*v_old_good_rec.good_price;
                   v_old_gsm_rec.good_name := v_old_good_rec.good_name;
                   insert into good_sum_mart(good_name, sum_sale) values(v_old_gsm_rec.good_name, v_old_gsm_rec.sum_sale);
                end if;
                
                --теперь обрабатываем данные, в good_sum_mart, по продаже по продукту с новым good_id;
                v_new_gsm_rec.sum_sale:=v_new_gsm_rec.sum_sale+(v_new_sales_rec.sales_qty*v_new_good_rec.good_price);
                if v_empty_flag = 0 then
                   insert into good_sum_mart(good_name, sum_sale) values(v_new_gsm_rec.good_name, v_new_gsm_rec.sum_sale);
                else
                   update good_sum_mart set sum_sale=v_new_gsm_rec.sum_sale where good_name=v_new_gsm_rec.good_name;
                end if;
           end if;

           --если код продукта, в изменяемой продаже, не поменялся. Но поменялось кол-во проданного продукта.
           if ( v_old_sales_rec.good_id = v_new_sales_rec.good_id and v_old_sales_rec.sales_qty != v_new_sales_rec.sales_qty ) then
               raise info 'TG_OP Upd; o/n-good_id: the same, old.sales_qty: %, new.sales_qty: %', v_old_sales_rec.sales_qty, v_new_sales_rec.sales_qty;
               v_delta:=(v_new_sales_rec.sales_qty - v_old_sales_rec.sales_qty);
               v_new_gsm_rec.sum_sale:=v_new_gsm_rec.sum_sale+(v_delta*v_new_good_rec.good_price);
               if v_empty_flag = 0 then
                   insert into good_sum_mart(good_name, sum_sale) values(v_new_gsm_rec.good_name, v_new_gsm_rec.sum_sale);
               else
                  update good_sum_mart set sum_sale=v_new_gsm_rec.sum_sale where good_name=v_new_gsm_rec.good_name;
               end if;
           end if;
    elsif (TG_OP = 'DELETE') then
           raise info 'TG_OP Del; empty_flag: %, good_id: %, sales_qty: %', v_empty_flag, v_old_sales_rec.good_id, v_old_sales_rec.sales_qty; 
           select * into v_old_good_rec from goods g where g.goods_id=v_old_sales_rec.good_id;
           v_old_empty_flag:=1;
           begin
               --надеемся что в good_sum_mart уже есть сумма по всем продажам данного товара.
               --надо только уменьшить эту сумму, на сумму удаляемой продажи.
               select gsm.* into strict v_old_gsm_rec from good_sum_mart gsm where gsm.good_name=v_old_good_rec.good_name;
               v_old_gsm_rec.sum_sale := v_old_gsm_rec.sum_sale - (v_old_sales_rec.sales_qty*v_old_good_rec.good_price);
               update good_sum_mart set sum_sale=v_old_gsm_rec.sum_sale where good_name=v_old_gsm_rec.good_name;
           exception when no_data_found then v_old_empty_flag:=0;
           end; 
           if v_old_empty_flag = 0 then
              --т.е.: в good_sum_mart не было данных по данному товару. Ну. Надо вставить.
              --помним что триггер - уже видит итог текущего делита в sales;
              select sum(s.sales_qty) into v_old_gsm_rec.sum_sale from sales s where s.good_id=v_old_sales_rec.good_id;
              v_old_gsm_rec.sum_sale := v_old_gsm_rec.sum_sale*v_old_good_rec.good_price;
              v_old_gsm_rec.good_name := v_old_good_rec.good_name;
              insert into good_sum_mart(good_name, sum_sale) values(v_old_gsm_rec.good_name, v_old_gsm_rec.sum_sale);
           end if;
    end if;
    return null;
end;
$$
LANGUAGE plpgsql;
```

```sql
--drop trigger change_sales_trig on sales;
CREATE or replace TRIGGER change_sales_trig
AFTER INSERT OR UPDATE OR DELETE ON sales
FOR EACH ROW EXECUTE FUNCTION func1();
```

Несколько поотлаживал её.
Потом пришла в голову мысль: как проверить - надо удалить все данные из sales-таблицы.
После этого, в витрине: должны остаться записи по всем товарам, удалённым из sales-таблицы.
И с одинаковым итогом, по продажам: 0, раз все продажи - удалили.

Потом добавить записи в sales-таблицу, так как это деается в скрипте `hw_triggers.sql`
Триггер должен их обработать, в витрине должны появится все товары по которым есть продажи в sales;
И итоги, по продажам, которые можно перепроверить аналитическим sql-запросом - должны сопадать.

И да - совпадают:
![1](/HomeWorks/Lesson23/1.png)

Теперь попробую поменять код товара в 24-й продаже, с 1-го на 2-й.
Без изменения кол-ва проданного товара.
В витрине, итог по продаже спичек - должен уменьшится на 0.5 условных единиц.
А итог по продажам феррари - заплюсоваться на стоимость одной феррари (185000000.01 у.е.)

![2](/HomeWorks/Lesson23/2.png)

Добавление продажи 10 штук спичек, при цене в 0.5 у.е. - итог по продажам спичек, в витрине, должен прирасти на 5 у.е.
![3](/HomeWorks/Lesson23/3.png)

Ну. Вроде работает, как надо, по заданию.

```
Чем такая схема (витрина+триггер) предпочтительнее отчета, создаваемого "по требованию" (кроме производительности)?
Подсказка: В реальной жизни возможны изменения цен.
```

Ну. После изменения прайсовых цен на номенклатуру товаров - витрина и аналитический скл-запрос: начнут выдавать разные данных по продажам.
В витрине - находятся итоговые цифры которые инкрементируются/декрментируются, триггером, по новым транзакциям, по продажам.
Т.е. в эти итоговые цифры, изменения прайсовой цены на товары будет сказываться только через значения, которые добавляются/отнимаются от итогов триггером.
Вот эти добавки/уменьшения - они будут триггером вычисляться, по новым прайсовым ценам и именно после изменения прайсовых цен.
А скл-запрос, аналитический, будет высчитывать итоги по продажам (всем) используя новые прайсовые цены для всех продаж, в т.ч. и тех которые делались до изменения прайсовых цен.
