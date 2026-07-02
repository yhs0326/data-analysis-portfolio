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



