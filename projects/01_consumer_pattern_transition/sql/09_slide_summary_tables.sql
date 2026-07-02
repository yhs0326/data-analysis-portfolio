-- 13. 슬라이드용 수치 테이블 산출
-- ============================================================
----------------슬라이드에 필요한 수치 테이블------------
------공통 cte------
with x as (
  select
    e.*,
    ((e.yq/10)::int*4 + ((e.yq%10)::int - 1)) as q_index,
    lead(((e.yq/10)::int*4 + ((e.yq%10)::int - 1))) over (
      partition by e."상권_코드", e."서비스_업종_코드"
      order by e.yq
    ) as next_q_index,
    lead(e.cl_cluster_name) over (
      partition by e."상권_코드", e."서비스_업종_코드"
      order by e.yq
    ) as next_cluster_name
  from seoul.v_cohort_q_enriched e
),
pairs as (
  select *
  from x
  where next_q_index = q_index + 1  
)
select * from pairs;


------------전이 집단 vs 유지 집단---------
with x as (
  select
    e.*,
    ((e.yq/10)::int*4 + ((e.yq%10)::int - 1)) as q_index,
    lead(((e.yq/10)::int*4 + ((e.yq%10)::int - 1))) over (
      partition by e."상권_코드", e."서비스_업종_코드"
      order by e.yq
    ) as next_q_index,
    lead(e.cl_cluster_name) over (
      partition by e."상권_코드", e."서비스_업종_코드"
      order by e.yq
    ) as next_cluster_name
  from seoul.v_cohort_q_enriched e
),
pairs as (
  select *,
    (next_cluster_name <> cl_cluster_name) as is_transition
  from x
  where next_q_index = q_index + 1
)
select
  case when is_transition then 'TRANSITION' else 'STAY' end as group_name,
  count(*) as n_pairs,
  avg(pk_shift::numeric) as pk_shift_rate,
  sum(pk_shift::numeric * sales_amt) / nullif(sum(sales_amt),0) as pk_shift_rate_wavg
from pairs
group by 1
order by 1;


------------전체 baseline + simple vs weighted-----------
select
  count(*) as n_rows,
  avg(pk_shift::numeric) as simple_rate,
  sum(pk_shift::numeric * sales_amt) / nullif(sum(sales_amt),0) as weighted_rate
from seoul.v_cohort_q_enriched;


---------가장 위험한 전이 Top1------------------
with x as (
  select
    e.*,
    ((e.yq/10)::int*4 + ((e.yq%10)::int - 1)) as q_index,
    lead(((e.yq/10)::int*4 + ((e.yq%10)::int - 1))) over (
      partition by e."상권_코드", e."서비스_업종_코드"
      order by e.yq
    ) as next_q_index,
    lead(e.cl_cluster_name) over (
      partition by e."상권_코드", e."서비스_업종_코드"
      order by e.yq
    ) as next_cluster_name
  from seoul.v_cohort_q_enriched e
),
pairs as (
  select *
  from x
  where next_q_index = q_index + 1
    and next_cluster_name is not null
    and next_cluster_name <> cl_cluster_name  
)
select
  cl_cluster_name as from_cluster,
  next_cluster_name as to_cluster,
  count(*) as n_pairs,
  avg(pk_shift::numeric) as pk_shift_rate,
  sum(pk_shift::numeric * sales_amt) / nullif(sum(sales_amt),0) as pk_shift_rate_wavg
from pairs
group by 1,2
having count(*) >= 30               
order by pk_shift_rate desc, n_pairs desc
limit 10;


---------------전이 감지 후 평균 X분기 내 위험 증가------------
with base as (
  select
    e."상권_코드",
    e."서비스_업종_코드",
    e.yq,
    ((e.yq/10)::int*4 + ((e.yq%10)::int - 1)) as q_index,
    e.cl_cluster_name,
    e.pk_shift,
    e.sales_amt
  from seoul.v_cohort_q_enriched e
),
t_signal as (
  select
    b.*,
    lag(b.cl_cluster_name) over (
      partition by b."상권_코드", b."서비스_업종_코드"
      order by b.yq
    ) as prev_cluster,
    lag(b.q_index) over (
      partition by b."상권_코드", b."서비스_업종_코드"
      order by b.yq
    ) as prev_q_index
  from base b
),
signals as (
  select
    "상권_코드","서비스_업종_코드",
    q_index as t_q_index,
    sales_amt as t_sales
  from t_signal
  where prev_cluster is not null
    and prev_q_index = q_index - 1       -- 연속분기에서만 신호 인정
    and prev_cluster <> cl_cluster_name  -- 전이 발생 시점 t
),
future as (
  select
    s.*,
    b1.pk_shift as pk_t1,
    b2.pk_shift as pk_t2,
    b3.pk_shift as pk_t3
  from signals s
  left join base b1
    on b1."상권_코드"=s."상권_코드" and b1."서비스_업종_코드"=s."서비스_업종_코드"
   and b1.q_index = s.t_q_index + 1
  left join base b2
    on b2."상권_코드"=s."상권_코드" and b2."서비스_업종_코드"=s."서비스_업종_코드"
   and b2.q_index = s.t_q_index + 2
  left join base b3
    on b3."상권_코드"=s."상권_코드" and b3."서비스_업종_코드"=s."서비스_업종_코드"
   and b3.q_index = s.t_q_index + 3
)
select
  count(*) as n_signals,
  avg(pk_t1::numeric) as pk_shift_rate_t_plus_1,
  avg(pk_t2::numeric) as pk_shift_rate_t_plus_2,
  avg(pk_t3::numeric) as pk_shift_rate_t_plus_3,
  -- 가중(매출) 버전도 같이
  sum(pk_t1::numeric * t_sales) / nullif(sum(t_sales),0) as pk_shift_rate_t_plus_1_wavg,
  sum(pk_t2::numeric * t_sales) / nullif(sum(t_sales),0) as pk_shift_rate_t_plus_2_wavg,
  sum(pk_t3::numeric * t_sales) / nullif(sum(t_sales),0) as pk_shift_rate_t_plus_3_wavg
from future
where pk_t1 is not null;  -- t+1 관측 가능한 신호만


-------------Top 위험 전이의 실제 사례 1개-------------
with x as (
  select
    e.*,
    ((e.yq/10)::int*4 + ((e.yq%10)::int - 1)) as q_index,
    lead(((e.yq/10)::int*4 + ((e.yq%10)::int - 1))) over (
      partition by e."상권_코드", e."서비스_업종_코드"
      order by e.yq
    ) as next_q_index,
    lead(e.cl_cluster_name) over (
      partition by e."상권_코드", e."서비스_업종_코드"
      order by e.yq
    ) as next_cluster_name
  from seoul.v_cohort_q_enriched e
),
pairs as (
  select *
  from x
  where next_q_index = q_index + 1
)
select
  "상권_코드",
  "서비스_업종_코드",
  yq,
  cl_cluster_name as from_cluster,
  next_cluster_name as to_cluster,
  pk_shift,
  sales_amt
from pairs
where cl_cluster_name = '퇴근·주말 집중형'   
  and next_cluster_name = '오전 중심형'      
order by sales_amt desc
limit 1;


-----군집별 평균 시간대 비중---
with ts as (
  select
    상권_코드,
    서비스_업종_코드,
    (year*10 + quarter) as yq,
    ts_0_6, ts_6_11, ts_11_14, ts_14_17, ts_17_21, ts_21_24
  from seoul.v_card_sales_q_ts_clean
)
select
  e.cl_cluster_name,

  avg(ts.ts_0_6)   as avg_0_6,
  avg(ts.ts_6_11)  as avg_6_11,
  avg(ts.ts_11_14) as avg_11_14,
  avg(ts.ts_14_17) as avg_14_17,
  avg(ts.ts_17_21) as avg_17_21,
  avg(ts.ts_21_24) as avg_21_24

from seoul.v_cohort_q_enriched e
join ts
  on e."상권_코드" = ts.상권_코드
 and e."서비스_업종_코드" = ts.서비스_업종_코드
 and e."yq" = ts.yq
group by 1
order by 1;



select count(*)
from seoul.v_cohort_q_enriched;

---------슬라이드6 테이블-------
with x as (
  select
    e.*,
    ((e.yq/10)::int*4 + ((e.yq%10)::int - 1)) as q_index,
    lead(((e.yq/10)::int*4 + ((e.yq%10)::int - 1))) over (
      partition by e."상권_코드", e."서비스_업종_코드"
      order by e.yq
    ) as next_q_index,
    lead(e.cl_cluster_name) over (
      partition by e."상권_코드", e."서비스_업종_코드"
      order by e.yq
    ) as next_cluster_name
  from seoul.v_cohort_q_enriched e
),
pairs as (
  select
    *,
    (next_cluster_name <> cl_cluster_name) as is_transition
  from x
  where next_q_index = q_index + 1
    and next_cluster_name is not null
)
select * from pairs limit 1;


--------
with x as (
  select
    e.*,
    ((e.yq/10)::int*4 + ((e.yq%10)::int - 1)) as q_index,
    lead(((e.yq/10)::int*4 + ((e.yq%10)::int - 1))) over (
      partition by e."상권_코드", e."서비스_업종_코드"
      order by e.yq
    ) as next_q_index,
    lead(e.cl_cluster_name) over (
      partition by e."상권_코드", e."서비스_업종_코드"
      order by e.yq
    ) as next_cluster_name
  from seoul.v_cohort_q_enriched e
),
pairs as (
  select *,
    (next_cluster_name <> cl_cluster_name) as is_transition
  from x
  where next_q_index = q_index + 1
    and next_cluster_name is not null
)
select
  case when is_transition then 'TRANSITION' else 'STAY' end as group_name,
  count(*) as n_pairs,
  avg(pk_shift::numeric) as pk_shift_rate,
  sum(pk_shift::numeric * sales_amt) / nullif(sum(sales_amt),0) as pk_shift_rate_wavg
from pairs
group by 1
order by 1;

-------
with x as (
  select
    e.*,
    ((e.yq/10)::int*4 + ((e.yq%10)::int - 1)) as q_index,
    lead(((e.yq/10)::int*4 + ((e.yq%10)::int - 1))) over (
      partition by e."상권_코드", e."서비스_업종_코드"
      order by e.yq
    ) as next_q_index,
    lead(e.cl_cluster_name) over (
      partition by e."상권_코드", e."서비스_업종_코드"
      order by e.yq
    ) as next_cluster_name
  from seoul.v_cohort_q_enriched e
),
pairs as (
  select *
  from x
  where next_q_index = q_index + 1
    and next_cluster_name is not null
)
select
  count(*) as n_pairs_total,
  avg(pk_shift::numeric) as baseline_pk_shift_rate,
  sum(pk_shift::numeric * sales_amt) / nullif(sum(sales_amt),0) as baseline_pk_shift_rate_wavg
from pairs;


------------
with x as (
  select
    e.*,
    ((e.yq/10)::int*4 + ((e.yq%10)::int - 1)) as q_index,
    lead(((e.yq/10)::int*4 + ((e.yq%10)::int - 1))) over (
      partition by e."상권_코드", e."서비스_업종_코드"
      order by e.yq
    ) as next_q_index,
    lead(e.cl_cluster_name) over (
      partition by e."상권_코드", e."서비스_업종_코드"
      order by e.yq
    ) as next_cluster_name
  from seoul.v_cohort_q_enriched e
),
pairs as (
  select *
  from x
  where next_q_index = q_index + 1
    and next_cluster_name is not null
    and next_cluster_name <> cl_cluster_name
)
select
  cl_cluster_name as from_cluster,
  next_cluster_name as to_cluster,
  count(*) as n_pairs,
  avg(pk_shift::numeric) as pk_shift_rate,
  sum(pk_shift::numeric * sales_amt) / nullif(sum(sales_amt),0) as pk_shift_rate_wavg
from pairs
group by 1,2
having count(*) >= 30
order by pk_shift_rate desc, n_pairs desc
limit 10;

---------
with x as (
  select
    e.*,
    ((e.yq/10)::int*4 + ((e.yq%10)::int - 1)) as q_index,
    lead(((e.yq/10)::int*4 + ((e.yq%10)::int - 1))) over (
      partition by e."상권_코드", e."서비스_업종_코드"
      order by e.yq
    ) as next_q_index,
    lead(e.cl_cluster_name) over (
      partition by e."상권_코드", e."서비스_업종_코드"
      order by e.yq
    ) as next_cluster_name
  from seoul.v_cohort_q_enriched e
),
pairs as (
  select *,
    (next_cluster_name <> cl_cluster_name) as is_transition
  from x
  where next_q_index = q_index + 1
    and next_cluster_name is not null
),
agg as (
  select
    is_transition,
    avg(pk_shift::numeric) as rate_simple,
    sum(pk_shift::numeric * sales_amt) / nullif(sum(sales_amt),0) as rate_wavg
  from pairs
  group by 1
)
select
  max(rate_simple) filter (where is_transition=false) as stay_rate,
  max(rate_simple) filter (where is_transition=true ) as trans_rate,
  (max(rate_simple) filter (where is_transition=true ))
    / nullif(max(rate_simple) filter (where is_transition=false),0) as lift_simple,

  max(rate_wavg) filter (where is_transition=false) as stay_rate_wavg,
  max(rate_wavg) filter (where is_transition=true ) as trans_rate_wavg,
  (max(rate_wavg) filter (where is_transition=true ))
    / nullif(max(rate_wavg) filter (where is_transition=false),0) as lift_wavg
from agg;



------------전개 곡선 테이블 생성--------
drop table if exists seoul.slide7_risk_curve;

create table seoul.slide7_risk_curve as
with base as (
  select
    e."상권_코드",
    e."서비스_업종_코드",
    e.yq,
    ((e.yq/10)::int*4 + ((e.yq%10)::int - 1)) as q_index,
    e.cl_cluster_name,
    e.pk_shift,
    e.sales_amt
  from seoul.v_cohort_q_enriched e
),
lagged as (
  select
    b.*,
    lag(b.cl_cluster_name) over (
      partition by b."상권_코드", b."서비스_업종_코드"
      order by b.yq
    ) as prev_cluster,
    lag(b.q_index) over (
      partition by b."상권_코드", b."서비스_업종_코드"
      order by b.yq
    ) as prev_q_index
  from base b
),
events as (
  select
    "상권_코드","서비스_업종_코드",
    q_index as t_q_index,
    sales_amt as t_sales,
    case
      when prev_cluster is not null
       and prev_q_index = q_index - 1
       and prev_cluster <> cl_cluster_name
      then 'TRANSITION'
      when prev_cluster is not null
       and prev_q_index = q_index - 1
       and prev_cluster = cl_cluster_name
      then 'STAY'
      else null
    end as event_group
  from lagged
),
events_clean as (
  select *
  from events
  where event_group is not null
),
future as (
  select
    e.event_group,
    e.t_sales,

    b0.pk_shift as pk_t0,
    b1.pk_shift as pk_t1,
    b2.pk_shift as pk_t2,
    b3.pk_shift as pk_t3

  from events_clean e
  left join base b0
    on b0."상권_코드"=e."상권_코드" and b0."서비스_업종_코드"=e."서비스_업종_코드"
   and b0.q_index = e.t_q_index

  left join base b1
    on b1."상권_코드"=e."상권_코드" and b1."서비스_업종_코드"=e."서비스_업종_코드"
   and b1.q_index = e.t_q_index + 1

  left join base b2
    on b2."상권_코드"=e."상권_코드" and b2."서비스_업종_코드"=e."서비스_업종_코드"
   and b2.q_index = e.t_q_index + 2

  left join base b3
    on b3."상권_코드"=e."상권_코드" and b3."서비스_업종_코드"=e."서비스_업종_코드"
   and b3.q_index = e.t_q_index + 3
),
stack as (
  select event_group, 0 as age, pk_t0 as pk, t_sales from future where pk_t0 is not null
  union all
  select event_group, 1 as age, pk_t1 as pk, t_sales from future where pk_t1 is not null
  union all
  select event_group, 2 as age, pk_t2 as pk, t_sales from future where pk_t2 is not null
  union all
  select event_group, 3 as age, pk_t3 as pk, t_sales from future where pk_t3 is not null
)
select
  event_group,                 -- 'TRANSITION' or 'STAY' (슬라이드에는 용어만 바꿔서)
  age,                         -- 0~3
  count(*) as n_events,
  avg(pk::numeric) as risk_rate,
  sum(pk::numeric * t_sales) / nullif(sum(t_sales),0) as risk_rate_wavg
from stack
group by 1,2
order by 1,2;



select
  age,
  round(100 * 
    max(case when event_group='STAY' 
             then risk_rate_wavg end)::numeric
  ,1) as stay_pct,
  round(100 * 
    max(case when event_group='TRANSITION' 
             then risk_rate_wavg end)::numeric
  ,1) as transition_pct
from seoul.slide7_risk_curve
group by age
order by age;



-------연도 편향 검증--------
WITH base AS (
  SELECT
    e."상권_코드",
    e."서비스_업종_코드",
    e.yq,
    ((e.yq/10)::int*4 + ((e.yq%10)::int - 1)) AS q_index,
    e.cl_cluster_name,
    e.pk_shift,
    e.sales_amt
  FROM seoul.v_cohort_q_enriched e
),
lagged AS (
  SELECT
    b.*,
    LAG(b.cl_cluster_name) OVER (
      PARTITION BY b."상권_코드", b."서비스_업종_코드"
      ORDER BY b.yq
    ) AS prev_cluster,
    LAG(b.q_index) OVER (
      PARTITION BY b."상권_코드", b."서비스_업종_코드"
      ORDER BY b.yq
    ) AS prev_q_index
  FROM base b
),
events AS (
  SELECT
    "상권_코드","서비스_업종_코드",
    yq AS t_yq,
    q_index AS t_q_index,
    sales_amt AS t_sales,
    CASE
      WHEN prev_cluster IS NOT NULL
       AND prev_q_index = q_index - 1
       AND prev_cluster <> cl_cluster_name
      THEN 'TRANSITION'
      WHEN prev_cluster IS NOT NULL
       AND prev_q_index = q_index - 1
       AND prev_cluster = cl_cluster_name
      THEN 'STAY'
      ELSE NULL
    END AS event_group
  FROM lagged
),
events_clean AS (
  SELECT *
  FROM events
  WHERE event_group IS NOT NULL
),
future AS (
  SELECT
    e.event_group,
    e.t_yq,
    e.t_q_index,
    e.t_sales,
    b0.pk_shift AS pk_t0,
    b1.pk_shift AS pk_t1,
    b2.pk_shift AS pk_t2,
    b3.pk_shift AS pk_t3
  FROM events_clean e
  LEFT JOIN base b0
    ON b0."상권_코드"=e."상권_코드" AND b0."서비스_업종_코드"=e."서비스_업종_코드"
   AND b0.q_index = e.t_q_index
  LEFT JOIN base b1
    ON b1."상권_코드"=e."상권_코드" AND b1."서비스_업종_코드"=e."서비스_업종_코드"
   AND b1.q_index = e.t_q_index + 1
  LEFT JOIN base b2
    ON b2."상권_코드"=e."상권_코드" AND b2."서비스_업종_코드"=e."서비스_업종_코드"
   AND b2.q_index = e.t_q_index + 2
  LEFT JOIN base b3
    ON b3."상권_코드"=e."상권_코드" AND b3."서비스_업종_코드"=e."서비스_업종_코드"
   AND b3.q_index = e.t_q_index + 3
),
stack AS (
  SELECT event_group, (t_yq/10)::int AS t_year, 0 AS age, pk_t0 AS pk, t_sales FROM future WHERE pk_t0 IS NOT NULL
  UNION ALL
  SELECT event_group, (t_yq/10)::int AS t_year, 1 AS age, pk_t1 AS pk, t_sales FROM future WHERE pk_t1 IS NOT NULL
  UNION ALL
  SELECT event_group, (t_yq/10)::int AS t_year, 2 AS age, pk_t2 AS pk, t_sales FROM future WHERE pk_t2 IS NOT NULL
  UNION ALL
  SELECT event_group, (t_yq/10)::int AS t_year, 3 AS age, pk_t3 AS pk, t_sales FROM future WHERE pk_t3 IS NOT NULL
)
SELECT
  t_year,
  age,
  event_group,
  COUNT(*) AS n_events,
  AVG(pk::numeric) AS risk_simple,
  SUM(pk::numeric * t_sales) / NULLIF(SUM(t_sales),0) AS risk_wavg
FROM stack
GROUP BY 1,2,3
ORDER BY 1,2,3;

-----------------연도 구간(2021~2022 vs 2023~2025)으로 묶어서 보기
WITH base AS (
  SELECT
    e."상권_코드",
    e."서비스_업종_코드",
    e.yq,
    ((e.yq/10)::int*4 + ((e.yq%10)::int - 1)) AS q_index,
    e.cl_cluster_name,
    e.pk_shift,
    e.sales_amt
  FROM seoul.v_cohort_q_enriched e
),
lagged AS (
  SELECT
    b.*,
    LAG(b.cl_cluster_name) OVER (
      PARTITION BY b."상권_코드", b."서비스_업종_코드"
      ORDER BY b.yq
    ) AS prev_cluster,
    LAG(b.q_index) OVER (
      PARTITION BY b."상권_코드", b."서비스_업종_코드"
      ORDER BY b.yq
    ) AS prev_q_index
  FROM base b
),
events AS (
  SELECT
    "상권_코드","서비스_업종_코드",
    yq AS t_yq,
    q_index AS t_q_index,
    sales_amt AS t_sales,
    CASE
      WHEN prev_cluster IS NOT NULL
       AND prev_q_index = q_index - 1
       AND prev_cluster <> cl_cluster_name
      THEN 'TRANSITION'
      WHEN prev_cluster IS NOT NULL
       AND prev_q_index = q_index - 1
       AND prev_cluster = cl_cluster_name
      THEN 'STAY'
      ELSE NULL
    END AS event_group
  FROM lagged
),
events_clean AS (
  SELECT *
  FROM events
  WHERE event_group IS NOT NULL
),
future AS (
  SELECT
    e.event_group,
    e.t_yq,
    e.t_q_index,
    e.t_sales,
    b0.pk_shift AS pk_t0,
    b1.pk_shift AS pk_t1,
    b2.pk_shift AS pk_t2,
    b3.pk_shift AS pk_t3
  FROM events_clean e
  LEFT JOIN base b0
    ON b0."상권_코드"=e."상권_코드" AND b0."서비스_업종_코드"=e."서비스_업종_코드"
   AND b0.q_index = e.t_q_index
  LEFT JOIN base b1
    ON b1."상권_코드"=e."상권_코드" AND b1."서비스_업종_코드"=e."서비스_업종_코드"
   AND b1.q_index = e.t_q_index + 1
  LEFT JOIN base b2
    ON b2."상권_코드"=e."상권_코드" AND b2."서비스_업종_코드"=e."서비스_업종_코드"
   AND b2.q_index = e.t_q_index + 2
  LEFT JOIN base b3
    ON b3."상권_코드"=e."상권_코드" AND b3."서비스_업종_코드"=e."서비스_업종_코드"
   AND b3.q_index = e.t_q_index + 3
),
stack AS (
  SELECT event_group, (t_yq/10)::int AS t_year, 0 AS age, pk_t0 AS pk, t_sales FROM future WHERE pk_t0 IS NOT NULL
  UNION ALL
  SELECT event_group, (t_yq/10)::int AS t_year, 1 AS age, pk_t1 AS pk, t_sales FROM future WHERE pk_t1 IS NOT NULL
  UNION ALL
  SELECT event_group, (t_yq/10)::int AS t_year, 2 AS age, pk_t2 AS pk, t_sales FROM future WHERE pk_t2 IS NOT NULL
  UNION ALL
  SELECT event_group, (t_yq/10)::int AS t_year, 3 AS age, pk_t3 AS pk, t_sales FROM future WHERE pk_t3 IS NOT NULL
)
SELECT
  CASE WHEN t_year <= 2022 THEN '2021-2022' ELSE '2023-2025' END AS year_band,
  age,
  event_group,
  COUNT(*) AS n_events,
  AVG(pk::numeric) AS risk_simple,
  SUM(pk::numeric * t_sales) / NULLIF(SUM(t_sales),0) AS risk_wavg
FROM stack
GROUP BY 1,2,3
ORDER BY 1,2,3;

---------표본 수 점검-------------
WITH base AS (
  SELECT
    e."상권_코드",
    e."서비스_업종_코드",
    e.yq,
    ((e.yq/10)::int*4 + ((e.yq%10)::int - 1)) AS q_index,
    e.cl_cluster_name,
    e.pk_shift,
    e.sales_amt
  FROM seoul.v_cohort_q_enriched e
),
lagged AS (
  SELECT
    b.*,
    LAG(b.cl_cluster_name) OVER (
      PARTITION BY b."상권_코드", b."서비스_업종_코드"
      ORDER BY b.yq
    ) AS prev_cluster,
    LAG(b.q_index) OVER (
      PARTITION BY b."상권_코드", b."서비스_업종_코드"
      ORDER BY b.yq
    ) AS prev_q_index
  FROM base b
),
events AS (
  SELECT
    "상권_코드","서비스_업종_코드",
    yq AS t_yq,
    q_index AS t_q_index,
    sales_amt AS t_sales,
    CASE
      WHEN prev_cluster IS NOT NULL
       AND prev_q_index = q_index - 1
       AND prev_cluster <> cl_cluster_name
      THEN 'TRANSITION'
      WHEN prev_cluster IS NOT NULL
       AND prev_q_index = q_index - 1
       AND prev_cluster = cl_cluster_name
      THEN 'STAY'
      ELSE NULL
    END AS event_group
  FROM lagged
),
events_clean AS (
  SELECT *
  FROM events
  WHERE event_group IS NOT NULL
),
future AS (
  SELECT
    e.event_group,
    e.t_yq,
    e.t_q_index,
    e.t_sales,
    b0.pk_shift AS pk_t0,
    b1.pk_shift AS pk_t1,
    b2.pk_shift AS pk_t2,
    b3.pk_shift AS pk_t3
  FROM events_clean e
  LEFT JOIN base b0
    ON b0."상권_코드"=e."상권_코드" AND b0."서비스_업종_코드"=e."서비스_업종_코드"
   AND b0.q_index = e.t_q_index
  LEFT JOIN base b1
    ON b1."상권_코드"=e."상권_코드" AND b1."서비스_업종_코드"=e."서비스_업종_코드"
   AND b1.q_index = e.t_q_index + 1
  LEFT JOIN base b2
    ON b2."상권_코드"=e."상권_코드" AND b2."서비스_업종_코드"=e."서비스_업종_코드"
   AND b2.q_index = e.t_q_index + 2
  LEFT JOIN base b3
    ON b3."상권_코드"=e."상권_코드" AND b3."서비스_업종_코드"=e."서비스_업종_코드"
   AND b3.q_index = e.t_q_index + 3
),
stack AS (
  SELECT event_group, 0 AS age, pk_t0 AS pk, t_sales FROM future WHERE pk_t0 IS NOT NULL
  UNION ALL
  SELECT event_group, 1 AS age, pk_t1 AS pk, t_sales FROM future WHERE pk_t1 IS NOT NULL
  UNION ALL
  SELECT event_group, 2 AS age, pk_t2 AS pk, t_sales FROM future WHERE pk_t2 IS NOT NULL
  UNION ALL
  SELECT event_group, 3 AS age, pk_t3 AS pk, t_sales FROM future WHERE pk_t3 IS NOT NULL
)
SELECT
  event_group,
  age,
  COUNT(*) AS n_events
FROM stack
GROUP BY 1,2
ORDER BY 1,2;

----------이상치(초대형 매출) 영향 점검-----------
WITH base AS (
  SELECT
    e."상권_코드",
    e."서비스_업종_코드",
    e.yq,
    ((e.yq/10)::int*4 + ((e.yq%10)::int - 1)) AS q_index,
    e.cl_cluster_name,
    e.pk_shift,
    e.sales_amt
  FROM seoul.v_cohort_q_enriched e
),
lagged AS (
  SELECT
    b.*,
    LAG(b.cl_cluster_name) OVER (
      PARTITION BY b."상권_코드", b."서비스_업종_코드"
      ORDER BY b.yq
    ) AS prev_cluster,
    LAG(b.q_index) OVER (
      PARTITION BY b."상권_코드", b."서비스_업종_코드"
      ORDER BY b.yq
    ) AS prev_q_index
  FROM base b
),
events AS (
  SELECT
    "상권_코드","서비스_업종_코드",
    q_index AS t_q_index,
    sales_amt AS t_sales,
    CASE
      WHEN prev_cluster IS NOT NULL
       AND prev_q_index = q_index - 1
       AND prev_cluster <> cl_cluster_name
      THEN 'TRANSITION'
      WHEN prev_cluster IS NOT NULL
       AND prev_q_index = q_index - 1
       AND prev_cluster = cl_cluster_name
      THEN 'STAY'
      ELSE NULL
    END AS event_group
  FROM lagged
),
events_clean AS (
  SELECT *
  FROM events
  WHERE event_group IS NOT NULL
),
future AS (
  SELECT
    e.event_group,
    e.t_sales,
    b0.pk_shift AS pk_t0,
    b1.pk_shift AS pk_t1,
    b2.pk_shift AS pk_t2,
    b3.pk_shift AS pk_t3
  FROM events_clean e
  LEFT JOIN base b0
    ON b0."상권_코드"=e."상권_코드" AND b0."서비스_업종_코드"=e."서비스_업종_코드"
   AND b0.q_index = e.t_q_index
  LEFT JOIN base b1
    ON b1."상권_코드"=e."상권_코드" AND b1."서비스_업종_코드"=e."서비스_업종_코드"
   AND b1.q_index = e.t_q_index + 1
  LEFT JOIN base b2
    ON b2."상권_코드"=e."상권_코드" AND b2."서비스_업종_코드"=e."서비스_업종_코드"
   AND b2.q_index = e.t_q_index + 2
  LEFT JOIN base b3
    ON b3."상권_코드"=e."상권_코드" AND b3."서비스_업종_코드"=e."서비스_업종_코드"
   AND b3.q_index = e.t_q_index + 3
),
stack AS (
  SELECT event_group, 0 AS age, pk_t0 AS pk, t_sales FROM future WHERE pk_t0 IS NOT NULL
  UNION ALL
  SELECT event_group, 1 AS age, pk_t1 AS pk, t_sales FROM future WHERE pk_t1 IS NOT NULL
  UNION ALL
  SELECT event_group, 2 AS age, pk_t2 AS pk, t_sales FROM future WHERE pk_t2 IS NOT NULL
  UNION ALL
  SELECT event_group, 3 AS age, pk_t3 AS pk, t_sales FROM future WHERE pk_t3 IS NOT NULL
),
ranked AS (
  SELECT
    s.*,
    NTILE(100) OVER (PARTITION BY event_group, age ORDER BY t_sales DESC) AS tile
  FROM stack s
)
SELECT
  event_group,
  age,
  COUNT(*) AS n_events_trim,
  AVG(pk::numeric) AS risk_simple_trim,
  SUM(pk::numeric * t_sales) / NULLIF(SUM(t_sales),0) AS risk_wavg_trim
FROM ranked
WHERE tile > 1  -- 상위 1% 제거
GROUP BY 1,2
ORDER BY 1,2;



---------최종 코호트 히트맵용 테이블 생성 쿼리-----------
drop table if exists seoul.cohort_heatmap_final;

create table seoul.cohort_heatmap_final as
with base as (
    -- 코호트 분석에 필요한 기본 데이터 구성
    select
        e."상권_코드",
        e."서비스_업종_코드",
        e.yq,
        ((e.yq / 10)::int * 4 + ((e.yq % 10)::int - 1)) as q_index,
        e.cl_cluster_name,
        e.pk_shift,
        e.sales_amt
    from seoul.v_cohort_q_enriched e
),
lagged as (
    -- 전분기 군집 정보 생성
    select
        b.*,
        lag(b.cl_cluster_name) over (
            partition by b."상권_코드", b."서비스_업종_코드"
            order by b.q_index
        ) as prev_cluster_name,
        lag(b.q_index) over (
            partition by b."상권_코드", b."서비스_업종_코드"
            order by b.q_index
        ) as prev_q_index
    from base b
),
events as (
    -- 군집 변화 여부에 따라 전이/유지 이벤트 정의
    select
        "상권_코드",
        "서비스_업종_코드",
        yq as cohort_yq,
        ((yq / 10)::int)::text || 'Q' || ((yq % 10)::int)::text as cohort_label,
        q_index as cohort_q_index,
        prev_cluster_name as from_cluster,
        cl_cluster_name as to_cluster,
        sales_amt as event_sales,
        case
            when prev_cluster_name is not null
             and prev_q_index = q_index - 1
             and prev_cluster_name <> cl_cluster_name
            then 'TRANSITION'

            when prev_cluster_name is not null
             and prev_q_index = q_index - 1
             and prev_cluster_name = cl_cluster_name
            then 'STAY'

            else null
        end as event_group
    from lagged
),
events_clean as (
    -- 전이/유지 판단이 가능한 이벤트만 사용
    select *
    from events
    where event_group is not null
),
future as (
    -- 이벤트 발생 이후 0~3분기 위험률 추적
    select
        e.event_group,
        e.cohort_yq,
        e.cohort_label,
        e.cohort_q_index,
        e.from_cluster,
        e.to_cluster,
        a.age,
        b.pk_shift,
        e.event_sales
    from events_clean e
    cross join generate_series(0, 3) as a(age)
    join base b
      on b."상권_코드" = e."상권_코드"
     and b."서비스_업종_코드" = e."서비스_업종_코드"
     and b.q_index = e.cohort_q_index + a.age
    where b.pk_shift is not null
)
-- 코호트 시작 분기와 경과 분기별 위험률 집계
select
    event_group,
    cohort_yq,
    cohort_label,
    cohort_q_index,
    age,
    count(*) as n_obs,
    avg(pk_shift::numeric) as risk_rate,
    avg(pk_shift::numeric) * 100 as risk_rate_pct,
    sum(pk_shift::numeric * event_sales) / nullif(sum(event_sales), 0) as risk_rate_wavg,
    100 * sum(pk_shift::numeric * event_sales) / nullif(sum(event_sales), 0) as risk_rate_wavg_pct
from future
group by
    event_group,
    cohort_yq,
    cohort_label,
    cohort_q_index,
    age
order by
    event_group,
    cohort_q_index,
    age;

select count(*) from seoul.cohort_heatmap_final;

