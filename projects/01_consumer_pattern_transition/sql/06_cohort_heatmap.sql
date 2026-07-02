-- 10. 코호트 히트맵 테이블 생성
-- ============================================================
------코호트 히트맵 테이블 만들기-----
drop table if exists seoul.cohort_signal_heatmap;

create table seoul.cohort_signal_heatmap as
with base as (
  select
    "상권_코드",
    "서비스_업종_코드",
    yq,
    pk_shift,
    cl_cluster_shift,
    sales_amt,
    dense_rank() over (order by yq) - 1 as q_index
  from seoul.v_cohort_q_enriched
),
first_signal as (
  select
    "상권_코드",
    "서비스_업종_코드",
    min(q_index) filter (where cl_cluster_shift = 1) as start_q_index
  from base
  group by 1,2
),
joined as (
  select
    b.*,
    fs.start_q_index,
    (b.q_index - fs.start_q_index) as age
  from base b
  join first_signal fs
    on b."상권_코드" = fs."상권_코드"
   and b."서비스_업종_코드" = fs."서비스_업종_코드"
  where fs.start_q_index is not null
    and (b.q_index - fs.start_q_index) >= 0
)
select
  start_q_index as cohort_start_yq,
  age,
  count(*) as n_rows,
  avg(pk_shift::numeric) as pk_shift_rate,
  sum(pk_shift::numeric * sales_amt) / nullif(sum(sales_amt),0) as pk_shift_rate_wavg
from joined
group by 1,2
order by 1,2;


select count(*) as n_rows,
       count(distinct cohort_start_yq) as n_cohorts,
       max(age) as max_age
from seoul.cohort_signal_heatmap;


select *
from seoul.cohort_signal_heatmap
where pk_shift_rate < 0 or pk_shift_rate > 1
   or pk_shift_rate_wavg < 0 or pk_shift_rate_wavg > 1
   or n_rows <= 0
order by cohort_start_yq, age
limit 50;


-- 음수 age 존재 여부
select count(*) as n_bad
from seoul.cohort_signal_heatmap
where age < 0;

-- cohort별 최소 age가 0인지
select cohort_start_yq, min(age) as min_age
from seoul.cohort_signal_heatmap
group by 1
having min(age) <> 0
order by 1;


with base as (
  select
    "상권_코드","서비스_업종_코드", yq,
    cl_cluster_shift,
    dense_rank() over (order by yq) - 1 as q_index
  from seoul.v_cohort_q_enriched
),
first_signal as (
  select
    "상권_코드","서비스_업종_코드",
    min(q_index) filter (where cl_cluster_shift = 1) as start_q_index
  from base
  group by 1,2
),
check_start as (
  select
    fs.start_q_index as cohort_start_yq,
    count(*) as n_keys,
    count(*) filter (where b.cl_cluster_shift <> 1) as n_not_shift1_at_start
  from first_signal fs
  join base b
    on b."상권_코드"=fs."상권_코드"
   and b."서비스_업종_코드"=fs."서비스_업종_코드"
   and b.q_index = fs.start_q_index
  where fs.start_q_index is not null
  group by 1
)
select *
from check_start
where n_not_shift1_at_start > 0
order by cohort_start_yq;



with base as (
  select
    "상권_코드","서비스_업종_코드",
    pk_shift, sales_amt,
    dense_rank() over (order by yq) - 1 as q_index,
    cl_cluster_shift
  from seoul.v_cohort_q_enriched
),
first_signal as (
  select
    "상권_코드","서비스_업종_코드",
    min(q_index) filter (where cl_cluster_shift = 1) as start_q_index
  from base
  group by 1,2
),
joined as (
  select
    b.*,
    fs.start_q_index as cohort_start_yq,
    (b.q_index - fs.start_q_index) as age
  from base b
  join first_signal fs
    on b."상권_코드"=fs."상권_코드"
   and b."서비스_업종_코드"=fs."서비스_업종_코드"
  where fs.start_q_index is not null
    and (b.q_index - fs.start_q_index) >= 0
),
recalc as (
  select
    cohort_start_yq,
    age,
    count(*) as n_rows_calc,
    avg(pk_shift::numeric) as pk_shift_rate_calc,
    sum(pk_shift::numeric * sales_amt) / nullif(sum(sales_amt),0) as pk_shift_rate_wavg_calc
  from joined
  group by 1,2
),
diff as (
  select
    h.cohort_start_yq, h.age,
    h.n_rows, r.n_rows_calc,
    h.pk_shift_rate, r.pk_shift_rate_calc,
    h.pk_shift_rate_wavg, r.pk_shift_rate_wavg_calc
  from seoul.cohort_signal_heatmap h
  join recalc r
    on h.cohort_start_yq = r.cohort_start_yq
   and h.age = r.age
)
select *
from diff
where n_rows <> n_rows_calc
   or abs(pk_shift_rate - pk_shift_rate_calc) > 1e-12
   or abs(pk_shift_rate_wavg - pk_shift_rate_wavg_calc) > 1e-9
order by cohort_start_yq, age
limit 50;



with x as (
  select
    cohort_start_yq,
    age,
    n_rows,
    lag(n_rows) over (partition by cohort_start_yq order by age) as prev_n
  from seoul.cohort_signal_heatmap
)
select
  cohort_start_yq,
  count(*) filter (where prev_n is not null) as n_steps,
  count(*) filter (where prev_n is not null and n_rows > prev_n) as n_increase_steps
from x
group by 1
order by n_increase_steps desc, cohort_start_yq
limit 30;



select
  cohort_start_yq,
  n_rows,
  pk_shift_rate,
  pk_shift_rate_wavg
from seoul.cohort_signal_heatmap
where age = 0
order by cohort_start_yq;


-- ============================================================
