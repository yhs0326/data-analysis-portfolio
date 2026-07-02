-- 9. 가중치 평균용 테이블 생성
-- ============================================================
----가중치 평균용 테이블 만들기---
drop view if exists seoul.v_cohort_q_enriched;

create or replace view seoul.v_cohort_q_enriched as
select c."상권_코드",
  c."서비스_업종_코드",
  c."yq",
  c."pk_shift",
  c."cl_cluster_shift",
  c."cl_cluster_name",
  
  t.sales_amt,
  t.ts_sum
from seoul.cohort_q c
join (select 상권_코드,
    서비스_업종_코드,
    (year*10 + quarter) as yq,
    sales_amt,
    ts_sum
    from seoul.v_card_sales_q_ts_clean) t
on c."상권_코드" = t.상권_코드
and c."서비스_업종_코드" = t.서비스_업종_코드
and c."yq" = t.yq;




select
  min(sales_amt) as min_w,
  max(sales_amt) as max_w,
  sum(sales_amt) as sum_w
from seoul.v_cohort_q_enriched;



-- 상위 5% 매출이 전체 매출의 몇 %를 차지하는지
with p as (
  select
    percentile_cont(0.95) within group (order by sales_amt) as p95
  from seoul.v_cohort_q_enriched
),
x as (
  select
    e.sales_amt,
    p.p95
  from seoul.v_cohort_q_enriched e
  cross join p
)
select
  max(p95) as p95,
  sum(case when sales_amt >= p95 then sales_amt else 0 end)::numeric
    / nullif(sum(sales_amt), 0) as top5pct_share
from x;



with p as (
  select percentile_cont(0.99) within group (order by sales_amt) as p99
  from seoul.v_cohort_q_enriched
),
x as (
  select e.sales_amt, p.p99
  from seoul.v_cohort_q_enriched e
  cross join p
)
select
  max(p99) as p99,
  sum(case when sales_amt >= p99 then sales_amt else 0 end)::numeric
    / nullif(sum(sales_amt), 0) as top1pct_share
from x;


select
  avg(pk_shift::numeric) as simple_rate,
  sum(pk_shift::numeric * sales_amt) / nullif(sum(sales_amt),0) as weighted_rate
from seoul.v_cohort_q_enriched;


with x as (
  select *,
         ntile(100) over (order by sales_amt desc) as tile
  from seoul.v_cohort_q_enriched
)
select
  avg(pk_shift::numeric) as simple_rate_trim,
  sum(pk_shift::numeric * sales_amt) / nullif(sum(sales_amt),0) as weighted_rate_trim
from x
where tile > 1;  -- 상위 1% 제거


select
  corr(sales_amt::numeric, ts_sum::numeric) as corr_amt_ts
from seoul.v_cohort_q_enriched;


select
  percentile_cont(0.5) within group (order by (ts_sum::numeric / nullif(sales_amt,0))) as med_ratio,
  percentile_cont(0.1) within group (order by (ts_sum::numeric / nullif(sales_amt,0))) as p10_ratio,
  percentile_cont(0.9) within group (order by (ts_sum::numeric / nullif(sales_amt,0))) as p90_ratio
from seoul.v_cohort_q_enriched
where sales_amt > 0;



select
  count(*) as n_keys,
  count(*) filter (where cohort_start_yq is null) as n_null
from (
  select
    "상권_코드","서비스_업종_코드",
    min(yq) filter (where cl_cluster_shift = 1) as cohort_start_yq
  from seoul.v_cohort_q_enriched
  group by 1,2
) t;


-- ============================================================
