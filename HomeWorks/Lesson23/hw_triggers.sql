-- ДЗ тема: триггеры, поддержка заполнения витрин

DROP SCHEMA IF EXISTS pract_functions CASCADE;
CREATE SCHEMA pract_functions;

SET search_path = pract_functions, public;

-- товары:
CREATE TABLE goods
(
    goods_id    integer PRIMARY KEY,
    good_name   varchar(63) NOT NULL,
    good_price  numeric(12, 2) NOT NULL CHECK (good_price > 0.0)
);

INSERT INTO goods (goods_id, good_name, good_price) VALUES (1, 'Спички хозайственные', .50);
INSERT INTO goods (goods_id, good_name, good_price) VALUES (2, 'Автомобиль Ferrari FXX K', 185000000.01);

-- Продажи
CREATE TABLE sales
(
    sales_id    integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    good_id     integer REFERENCES goods (goods_id),
    sales_time  timestamp with time zone DEFAULT now(),
    sales_qty   integer CHECK (sales_qty > 0)
);

INSERT INTO sales (good_id, sales_qty) VALUES (1, 10), (1, 1), (1, 120), (2, 1);

-- отчет:
SELECT G.good_name, sum(G.good_price * S.sales_qty)
FROM goods G
INNER JOIN sales S ON S.good_id = G.goods_id
GROUP BY G.good_name;

-- с увеличением объёма данных отчет стал создаваться медленно
-- Принято решение денормализовать БД, создать таблицу
CREATE TABLE good_sum_mart
(
good_name   varchar(63) NOT NULL,
sum_sale    numeric(16, 2)NOT NULL
);

-- Создать триггер (на таблице sales) для поддержки.
-- Подсказка: не забыть, что кроме INSERT есть еще UPDATE и DELETE

-- Чем такая схема (витрина+триггер) предпочтительнее отчета, создаваемого "по требованию" (кроме производительности)?
-- Подсказка: В реальной жизни возможны изменения цен.

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
           if ( v_old_sales_rec.good_id != v_new_sales_rec.good_id ) then
                select * into v_old_good_rec from goods g where g.goods_id=v_old_sales_rec.good_id;
                begin
                    select gsm.* into strict v_old_gsm_rec from good_sum_mart gsm where gsm.good_name=v_old_good_rec.good_name;
                    v_old_gsm_rec.sum_sale := v_old_gsm_rec.sum_sale - (v_old_sales_rec.sales_qty*v_old_good_rec.good_price);
                    update good_sum_mart set sum_sale=v_old_gsm_rec.sum_sale where good_name=v_old_gsm_rec.good_name;
                exception when no_data_found then null;
                end;
                v_new_gsm_rec.sum_sale:=v_new_gsm_rec.sum_sale+(v_new_sales_rec.sales_qty*v_new_good_rec.good_price);
                if v_empty_flag = 0 then
                   insert into good_sum_mart(good_name, sum_sale) values(v_new_gsm_rec.good_name, v_new_gsm_rec.sum_sale);
                else
                   update good_sum_mart set sum_sale=v_new_gsm_rec.sum_sale where good_name=v_new_gsm_rec.good_name;
                end if;
           end if;
           if ( v_old_sales_rec.good_id = v_new_sales_rec.good_id and v_old_sales_rec.sales_qty != v_new_sales_rec.sales_qty ) then
               v_delta:=(v_new_sales_rec.sales_qty - v_old_sales_rec.sales_qty);
               v_new_gsm_rec.sum_sale:=v_new_gsm_rec.sum_sale+(v_delta*v_new_good_rec.good_price);
               if v_empty_flag = 0 then
                   insert into good_sum_mart(good_name, sum_sale) values(v_new_gsm_rec.good_name, v_new_gsm_rec.sum_sale);
               else
                  update good_sum_mart set sum_sale=v_new_gsm_rec.sum_sale where good_name=v_new_gsm_rec.good_name;
               end if;
           end if;
    elsif (TG_OP = 'DELETE') then
           select * into v_old_good_rec from goods g where g.goods_id=v_old_sales_rec.good_id;
           v_empty_flag:=1;
           begin
               --надеемся что в good_sum_mart уже есть сумма по всем продажам данного товара.
               --надо только уменьшить эту сумму, на сумму удаляемой продажи.
               select gsm.* into strict v_old_gsm_rec from good_sum_mart gsm where gsm.good_name=v_old_good_rec.good_name;
               v_old_gsm_rec.sum_sale := v_old_gsm_rec.sum_sale - (v_old_sales_rec.sales_qty*v_old_good_rec.good_price);
               update good_sum_mart set sum_sale=v_old_gsm_rec.sum_sale where good_name=v_old_gsm_rec.good_name;
           exception when no_data_found then v_empty_flag:=0;
           end; 
           if v_empty_flag = 0 then
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


drop trigger change_sales_trig on sales;
CREATE or replace TRIGGER change_sales_trig
AFTER INSERT OR UPDATE OR DELETE ON sales
FOR EACH ROW EXECUTE FUNCTION func1();

select t.* from sales t order by t.sales_id asc;
select t.* from good_sum_mart t;


update sales set sales_qty=11 where sales_id=1;
INSERT INTO sales (good_id, sales_qty) VALUES (1, 1);