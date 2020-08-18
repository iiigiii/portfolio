--1. В каких городах больше одного аэропорта?

select city, count(airport_code) as count_airports
from airports 
group by city
having count(airport_code) > 1;

--2. В каких аэропортах есть рейсы, которые обслуживаются самолетами с максимальной дальностью перелетов?

select distinct f.departure_airport airport_code, ap.airport_name, ap.city from flights f
left join airports ap on ap.airport_code = f.departure_airport
where aircraft_code in (select ac.aircraft_code 
	from aircrafts ac
	order by ac.range desc 
	limit 1
	);

--3. Были ли брони, по которым не совершались перелеты?

select b.book_ref from bookings b 
left join tickets t on t.book_ref = b.book_ref 
left join ticket_flights tf on tf.ticket_no = t.ticket_no 
left join boarding_passes bp on (bp.ticket_no, bp.flight_id) = (tf.ticket_no, tf.flight_id)
where bp.flight_id isnull;

--4. Самолеты каких моделей совершают наибольший % перелетов?

with one_proc as(
	select count(f.aircraft_code) / 100 ::float 
	from flights f 
	where f.status != 'Cancelled'
) 
select f.aircraft_code, ac.model, 
count(f.aircraft_code) as count_flights,
count(f.aircraft_code) / (select * from one_proc) as procent_flights
from flights f 
left join aircrafts ac on ac.aircraft_code = f.aircraft_code 
where f.status != 'Cancelled'
group by 1,2
order by count(f.aircraft_code) desc
limit 3;

--5. Были ли города, в которые можно  добраться бизнес - классом дешевле, чем эконом-классом?

create view cheap_business as(
with
	grouped_flight as(
		select tf.flight_id, tf.fare_conditions,
		min(tf.amount) min_amount,
		row_number() over (partition by tf.flight_id order by min(tf.amount)) rank_amount
		from ticket_flights tf 
		group by 1,2 
		order by flight_id
	),
	variants_fare_conditions as(
		select flight_id, count(rank_amount) count_variant 
		from grouped_flight 
		group by flight_id 
		having count(rank_amount) > 1
	)
select flight_id 
from grouped_flight 
where rank_amount = 1 and fare_conditions = 'Business' and flight_id in(
	select flight_id 
	from variants_fare_conditions)
);

select distinct ap.city 
from flights f
left join airports ap on ap.airport_code = f.departure_airport
where f.flight_id in(select * from cheap_business);

--6. Узнать максимальное время задержки вылетов самолетов

select flight_id, actual_departure - scheduled_departure as delay from flights 
where actual_arrival notnull
order by delay desc 
limit 1;

--7. Между какими городами нет прямых рейсов*?

create view direct_flights as(
	select distinct departure_airport, arrival_airport 
	from flights f 
	order by departure_airport, arrival_airport
	);

with direct_city as(
	select a1.city city_a, a2.city city_b 
	from direct_flights d_f
	left join airports a1 on a1.airport_code = d_f.departure_airport
	left join airports a2 on a2.airport_code = d_f.arrival_airport
),
all_city_combination as(
	select distinct a1.city || ' => ' || a2.city as routes 
	from airports a1, airports a2
	where a1.city != a2.city
)
select * from all_city_combination
where routes not in(
	select direct_city.city_a || ' => ' || direct_city.city_b 
	from direct_city)
;

--8. Между какими городами пассажиры делали пересадки*?

/* В ходе обсуждения этого вопроса с Николаем Хащановым выяснилось, что для ответа на данный вопрос не хватает данных в базе, 
так как база урезана для аналитиков в отличии от той же базы для програмистов. 
"В реальной жизни в базе будут столбцы отвечающие за пересадку, время пересадки, требуется ли гостиница и т.д. и т.п.
Здесь задача простая, были ли пересадки между городами..." - его слова. Получается вопрос в итоговой задан не корректно. Николай пообещал исправить это на следующих потоках.
Поэтому правильным решением можно считать скрипт который выдает перелеты которые по сути являются составными в маршрутах с пересадками. 
Прим.: билет с пересадкой LED => DME , DME => OVB в результаты попадет LED => DME и DME => OVB
 */

with tickets_with_change as(
	select tf.ticket_no,
		max(f.scheduled_departure) - min(f.scheduled_arrival ) as change_time
	from ticket_flights tf
	left join flights f on f.flight_id = tf.flight_id
	group by tf.ticket_no
	having max(f.scheduled_departure) - min(f.scheduled_arrival ) < '24:00:00' and
	max(f.scheduled_departure) - min(f.scheduled_arrival ) > '00:00:00'
	)
select distinct departure_airport, arrival_airport, a.city as departure_city, b.city as arrival_city
from tickets_with_change
left join ticket_flights tf on tickets_with_change.ticket_no = tf.ticket_no
left join flights f on f.flight_id = tf.flight_id
left join airports a on a.airport_code = departure_airport 
left join airports b on b.airport_code = arrival_airport;

/* В свою очередь изначально я пытался ответить непосредственно на поставленный вопрос и получить:
Прим.: билет с пересадкой LED => DME , DME => OVB в результаты попадет LED => OVB т.е. пассажир сделал пересадку между городами Санкт-Петербург и Новосибирск.
Что и было бы ответом на вопрос между какими городами делали пересадки.
Скрипт конечно получился крайне не оптимальным в данных условиях. Зато он выдает ответ именно на этот вопрос.
Единственный нюанс который заключается в том что в результаты не попадают случаи когда пересадок было больше одной.
 */

create view tickets_with_change as( 
with change_airplane as(
	select tf.ticket_no, count(tf.ticket_no) 
	from ticket_flights tf 
	group by tf.ticket_no 
	having count(tf.ticket_no) != 1 
	order by tf.ticket_no 
	)
select tf.ticket_no, 
	max(f.scheduled_departure) - min(f.scheduled_arrival ) as change_time
from ticket_flights tf
left join flights f on f.flight_id = tf.flight_id
where tf.ticket_no in(
	select ticket_no 
	from change_airplane
	)
group by tf.ticket_no 
having max(f.scheduled_departure) - min(f.scheduled_arrival ) < '24:00:00'
);

create materialized view change_ways as(
with not_direct_flight as(
with dep_port as(
	select tf.ticket_no, f.departure_airport  
	from ticket_flights tf 
	left join flights f on f.flight_id = tf.flight_id 
	where tf.ticket_no in(select ticket_no from tickets_with_change)
	order by tf.ticket_no, f.scheduled_departure
),
arr_port as(
	select tf.ticket_no, f.arrival_airport 
	from ticket_flights tf 
	left join flights f on f.flight_id = tf.flight_id 
	where tf.ticket_no in(select ticket_no from tickets_with_change)
	order by tf.ticket_no, f.scheduled_departure desc
)
select dep_port.ticket_no,
dep_port.departure_airport,
arr_port.arrival_airport,
row_number() over (partition by dep_port.ticket_no) as rank_
from dep_port
left join arr_port on dep_port.ticket_no = arr_port.ticket_no
)
select distinct departure_airport, arrival_airport from not_direct_flight
where rank_ = 1 and departure_airport != arrival_airport
) with data;

select distinct a.city city_a, b.city city_b from change_ways
left join airports a on a.airport_code = change_ways.departure_airport
left join airports b on b.airport_code = change_ways.arrival_airport;

--9. Вычислите расстояние между аэропортами, связанными прямыми рейсами, сравните с допустимой максимальной дальностью перелетов  в самолетах, обслуживающих эти рейсы **

create materialized view max_range as(
	select distinct f.departure_airport airport_code, 
		max(ac.range) as max_range
	from flights f
	left join airports ap on ap.airport_code = f.departure_airport
	left join aircrafts ac on ac.aircraft_code = f.aircraft_code 
	group by f.departure_airport 
	order by f.departure_airport
);

select direct_flights.departure_airport,
	direct_flights.arrival_airport,
	max_range.max_range,
	6371 * acos(sin(radians(a.latitude)) * sin(radians(b.latitude)) + cos(radians(a.latitude)) * cos(radians(b.latitude)) * cos(radians(a.longitude - b.longitude))) as distance
from direct_flights
left join airports a on a.airport_code = direct_flights.departure_airport
left join airports b on b.airport_code = direct_flights.arrival_airport
left join max_range on max_range.airport_code = direct_flights.departure_airport;
