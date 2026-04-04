-- 현재 버전은 포트폴리오용 정리본이며, 로직 수정은 하지 않았습니다.

-- ============================================================
-- 1. Raw table 생성
-- ============================================================
------raw table 생성--------

create schema if not exists seoul;

drop table if exists seoul.card_sales_q_raw;
create table seoul.card_sales_q_raw(
"기준_년분기_코드" int,
  "상권_구분_코드" text,
  "상권_구분_코드_명" text,
  "상권_코드" text,
  "상권_코드_명" text,
  "서비스_업종_코드" text,
  "서비스_업종_코드_명" text,

  "당월_매출_금액" bigint,

  "주중_매출_금액" bigint,
  "주말_매출_금액" bigint,

  "월요일_매출_금액" bigint,
  "화요일_매출_금액" bigint,
  "수요일_매출_금액" bigint,
  "목요일_매출_금액" bigint,
  "금요일_매출_금액" bigint,
  "토요일_매출_금액" bigint,
  "일요일_매출_금액" bigint,

  "시간대_00~06_매출_금액" bigint,
  "시간대_06~11_매출_금액" bigint,
  "시간대_11~14_매출_금액" bigint,
  "시간대_14~17_매출_금액" bigint,
  "시간대_17~21_매출_금액" bigint,
  "시간대_21~24_매출_금액" bigint,

  "남성_매출_금액" bigint,
  "여성_매출_금액" bigint,

  "연령대_10_매출_금액" bigint,
  "연령대_20_매출_금액" bigint,
  "연령대_30_매출_금액" bigint,
  "연령대_40_매출_금액" bigint,
  "연령대_50_매출_금액" bigint,
  "연령대_60_이상_매출_금액" bigint,

  "당월_매출_건수" bigint,

  "주중_매출_건수" bigint,
  "주말_매출_건수" bigint,

  "월요일_매출_건수" bigint,
  "화요일_매출_건수" bigint,
  "수요일_매출_건수" bigint,
  "목요일_매출_건수" bigint,
  "금요일_매출_건수" bigint,
  "토요일_매출_건수" bigint,
  "일요일_매출_건수" bigint,

  "시간대_건수~06_매출_건수" bigint,
  "시간대_건수~11_매출_건수" bigint,
  "시간대_건수~14_매출_건수" bigint,
  "시간대_건수~17_매출_건수" bigint,
  "시간대_건수~21_매출_건수" bigint,
  "시간대_건수~24_매출_건수" bigint,

  "남성_매출_건수" bigint,
  "여성_매출_건수" bigint,

  "연령대_10_매출_건수" bigint,
  "연령대_20_매출_건수" bigint,
  "연령대_30_매출_건수" bigint,
  "연령대_40_매출_건수" bigint,
  "연령대_50_매출_건수" bigint,
  "연령대_60_이상_매출_건수" bigint
);

select count(*) from seoul.card_sales_q_raw;


-- ============================================================
-- 2. 분기 파싱 및 패널 키 정리
-- ============================================================
-------분기 파싱, 패널 키 정리----
drop view if exists seoul.v_card_sales_q_panel;

create or replace view seoul.v_card_sales_q_panel as 
select "기준_년분기_코드",
  ("기준_년분기_코드" / 10) as year,
  ("기준_년분기_코드" % 10) as quarter,

  "상권_코드",
  "상권_코드_명",
  "서비스_업종_코드",
  "서비스_업종_코드_명",

  "당월_매출_금액",
  "당월_매출_건수",

  "주중_매출_금액",
  "주말_매출_금액",

  "시간대_00~06_매출_금액",
  "시간대_06~11_매출_금액",
  "시간대_11~14_매출_금액",
  "시간대_14~17_매출_금액",
  "시간대_17~21_매출_금액",
  "시간대_21~24_매출_금액"
from seoul.card_sales_q_raw;


-- ============================================================
-- 3. 시간대 비중 테이블 생성
-- ============================================================
-------시간대 비중 테이블 생성--------
drop view if exists seoul.v_card_sales_q_ts;

create or replace view seoul.v_card_sales_q_ts as
select 기준_년분기_코드,
  year,
  quarter,
  상권_코드,
  상권_코드_명,
  서비스_업종_코드,
  서비스_업종_코드_명,

  당월_매출_금액 as sales_amt,
  주말_매출_금액 as wkend_amt,
  주중_매출_금액 as wkday_amt,

  ("시간대_00~06_매출_금액"
  + "시간대_06~11_매출_금액"
  + "시간대_11~14_매출_금액"
  + "시간대_14~17_매출_금액"
  + "시간대_17~21_매출_금액"
  + "시간대_21~24_매출_금액") as ts_sum,

  "시간대_00~06_매출_금액"::numeric / nullif(
    ("시간대_00~06_매출_금액"
    + "시간대_06~11_매출_금액"
    + "시간대_11~14_매출_금액"
    + "시간대_14~17_매출_금액"
    + "시간대_17~21_매출_금액"
    + "시간대_21~24_매출_금액"), 0) as ts_0_6,

  "시간대_06~11_매출_금액"::numeric / nullif(
    ("시간대_00~06_매출_금액"
    + "시간대_06~11_매출_금액"
    + "시간대_11~14_매출_금액"
    + "시간대_14~17_매출_금액"
    + "시간대_17~21_매출_금액"
    + "시간대_21~24_매출_금액"), 0) as ts_6_11,

  "시간대_11~14_매출_금액"::numeric / nullif(
    ("시간대_00~06_매출_금액"
    + "시간대_06~11_매출_금액"
    + "시간대_11~14_매출_금액"
    + "시간대_14~17_매출_금액"
    + "시간대_17~21_매출_금액"
    + "시간대_21~24_매출_금액"), 0) as ts_11_14,

  "시간대_14~17_매출_금액"::numeric / nullif(
    ("시간대_00~06_매출_금액"
    + "시간대_06~11_매출_금액"
    + "시간대_11~14_매출_금액"
    + "시간대_14~17_매출_금액"
    + "시간대_17~21_매출_금액"
    + "시간대_21~24_매출_금액"), 0) as ts_14_17,

  "시간대_17~21_매출_금액"::numeric / nullif(
    ("시간대_00~06_매출_금액"
    + "시간대_06~11_매출_금액"
    + "시간대_11~14_매출_금액"
    + "시간대_14~17_매출_금액"
    + "시간대_17~21_매출_금액"
    + "시간대_21~24_매출_금액"), 0) as ts_17_21,

  "시간대_21~24_매출_금액"::numeric / nullif(
    ("시간대_00~06_매출_금액"
    + "시간대_06~11_매출_금액"
    + "시간대_11~14_매출_금액"
    + "시간대_14~17_매출_금액"
    + "시간대_17~21_매출_금액"
    + "시간대_21~24_매출_금액"), 0) as ts_21_24,

  주말_매출_금액::numeric / nullif(당월_매출_금액, 0) as share_wkend,
  주중_매출_금액::numeric / nullif(당월_매출_금액, 0) as share_wkday

from seoul.v_card_sales_q_panel;


-- ============================================================
-- 4. 분석 가능한 시간대 비중 테이블 생성
-- ============================================================
-----분석가능한 시간대 비중 테이블 만들기
-----(기존 테이블에는 분모가 0인 경우가 있어 분석불가능)
drop view if exists seoul.v_card_sales_q_ts_clean;

create or replace view seoul.v_card_sales_q_ts_clean as
select *
from seoul.v_card_sales_q_ts
where ts_sum > 0;


-- ============================================================
-- 5. 피크 시간대 테이블 생성
-- ============================================================
-----피크 시간대 테이블 만들기----
create or replace view seoul.v_card_sales_q_ts_peak as
select  기준_년분기_코드,
  year,
  quarter,
  상권_코드,
  상권_코드_명,
  서비스_업종_코드,
  서비스_업종_코드_명,

  share_wkend,

  case
    when ts_0_6 >= greatest(ts_6_11, ts_11_14, ts_14_17, ts_17_21, ts_21_24) then '0_6'
    when ts_6_11 >= greatest(ts_11_14, ts_14_17, ts_17_21, ts_21_24) then '6_11'
    when ts_11_14 >= greatest(ts_14_17, ts_17_21, ts_21_24) then '11_14'
    when ts_14_17 >= greatest(ts_17_21, ts_21_24) then '14_17'
    when ts_17_21 >= ts_21_24 then '17_21'
    else '21_24'
  end as pk_ts,

  greatest(
    ts_0_6, ts_6_11, ts_11_14,
    ts_14_17, ts_17_21, ts_21_24
  ) as pk_share

from seoul.v_card_sales_q_ts_clean;


-- ============================================================
-- 6. 분기별 패턴 이동 확인 테이블 생성
-- ============================================================
------분기별 패턴 이동 확인 테이블------
drop view if exists seoul.v_card_sales_q_pk_shift;

create or replace view seoul.v_card_sales_q_pk_shift as
with base as (
  select
    a."상권_코드",
    a."상권_코드_명",
    a."서비스_업종_코드",
    a."서비스_업종_코드_명",
    a.year,
    a.quarter,
    (a.year * 10 + a.quarter) as yq,
    (a.year * 4 + (a.quarter - 1)) as q_index,
    a.pk_ts   as pk_ts_t,
    a.pk_share as pk_share_t,
    a.share_wkend as share_wkend_t
  from seoul.v_card_sales_q_ts_peak a
),
joined as (
  select
    a.*,
    b.pk_ts_t       as pk_ts_t1,
    b.pk_share_t    as pk_share_t1,
    b.share_wkend_t as share_wkend_t1
  from base a
  left join base b
    on a."상권_코드" = b."상권_코드"
   and a."서비스_업종_코드" = b."서비스_업종_코드"
   and b.q_index = a.q_index + 1
)
select
  "상권_코드",
  "상권_코드_명",
  "서비스_업종_코드",
  "서비스_업종_코드_명",
  year,
  quarter,
  yq,
  pk_ts_t,
  pk_ts_t1,
  pk_share_t,
  pk_share_t1,
  share_wkend_t,
  share_wkend_t1,
  case
    when pk_ts_t1 is null then null
    when pk_ts_t <> pk_ts_t1 then 1
    else 0
  end as pk_shift
from joined;

--------------------------------
select
  year, quarter,
  count(*) as n_rows,
  count(*) filter (where pk_shift is null) as n_pk_null
from seoul.v_card_sales_q_pk_shift
group by 1,2
order by 1,2;



select
  year, quarter,
  count(*) as n_rows,
  count(*) filter (where pk_shift is null) as n_pk_null,
  (count(*) filter (where pk_shift is null))::numeric / count(*) as null_rate
from seoul.v_card_sales_q_pk_shift
group by 1,2
order by 1,2;

with a as (
  select
    "상권_코드","서비스_업종_코드",
    year, quarter,
    (year*4 + (quarter-1)) as q_index
  from seoul.v_card_sales_q_pk_shift
  where pk_shift is null
)
select
  a.year, a.quarter,
  count(*) as n_null,
  count(*) filter (where b."상권_코드" is null) as n_no_next_in_peak
from a
left join (
  select
    "상권_코드","서비스_업종_코드",
    (year*4 + (quarter-1)) as q_index
  from seoul.v_card_sales_q_ts_peak
) b
  on a."상권_코드"=b."상권_코드"
 and a."서비스_업종_코드"=b."서비스_업종_코드"
 and b.q_index = a.q_index + 1
group by 1,2
order by 1,2;


select *
from seoul.v_card_sales_q_pk_shift
where pk_shift is null
order by year, quarter
limit 20;


-- ============================================================
-- 7. 학습용 데이터셋 생성
-- ============================================================
-----------학습용 데이터 셋 만들기------
create or replace view seoul.v_train_dataset_pk_shift as
select f.상권_코드,
  f.상권_코드_명,
  f.서비스_업종_코드,
  f.서비스_업종_코드_명,

  f.year,
  f.quarter,
  (f.year * 10 + f.quarter) as yq,

  s.pk_shift,

  f.ts_0_6,
  f.ts_6_11,
  f.ts_11_14,
  f.ts_14_17,
  f.ts_17_21,
  f.ts_21_24,
  f.share_wkend
from seoul.v_card_sales_q_ts_clean f
join seoul.v_card_sales_q_pk_shift s
on f.상권_코드 = s.상권_코드
and f.서비스_업종_코드 = s.서비스_업종_코드
and f.year = s.year
and f.quarter = s.quarter
where s.pk_shift is not null;

--------------------------------
select count(*) 
from seoul.v_train_dataset_pk_shift;

select
  count(*) filter (where ts_0_6 is null) as n_null_ts0,
  count(*) filter (where ts_6_11 is null) as n_null_ts1,
  count(*) filter (where ts_11_14 is null) as n_null_ts2,
  count(*) filter (where ts_14_17 is null) as n_null_ts3,
  count(*) filter (where ts_17_21 is null) as n_null_ts4,
  count(*) filter (where ts_21_24 is null) as n_null_ts5,
  count(*) filter (where share_wkend is null) as n_null_wkend
from seoul.v_train_dataset_pk_shift;



select
  min(yq) as min_yq,
  max(yq) as max_yq,
  min(year) as min_year,
  max(year) as max_year,
  min(quarter) as min_quarter,
  max(quarter) as max_quarter
from seoul.v_train_dataset_pk_shift;


select
  yq,
  count(*) as n
from seoul.v_train_dataset_pk_shift
group by yq
order by yq;


-- ============================================================
-- 8. 코호트 분석 테이블 생성
-- ============================================================
-------코호트 분석 테이블 만들기------
truncate table seoul.cohort_q;
drop table if exists seoul.cohort_q;

create table seoul.cohort_q (
  "상권_코드" text,
  "서비스_업종_코드" text,
  "yq" int,
  "pk_shift" int,
  "cl_cluster_shift" int,
  "cl_cluster_name" text
);

select count(*) from seoul.cohort_q;

-----성능을 위한 인덱스-----
create index if not exists ix_cohort_q_key_yq
on seoul.cohort_q("상권_코드","서비스_업종_코드","yq");

create index if not exists ix_cohort_q_yq
on seoul.cohort_q("yq");


-- ============================================================
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
-- 11. 전이행렬 생성
-- ============================================================
-----------전이행렬 (이전 군집 → 현재 군집) + 빈도/가중--------------
drop table if exists seoul.cohort_transition_matrix;

create table seoul.cohort_transition_matrix as with x as(
select "상권_코드","서비스_업종_코드","yq",
    cl_cluster_name,
    sales_amt,
	lag(cl_cluster_name) over (partition by "상권_코드","서비스_업종_코드"
	order by yq
	) as prev_cluster_name
from seoul.v_cohort_q_enriched
)
select prev_cluster_name as from_cluster,
  cl_cluster_name as to_cluster,
  count(*) as n_rows,
  (sum(sales_amt)) as sum_sales_amt,
  (count(*)::numeric / nullif(sum(count(*)) over 
  (partition by prev_cluster_name),0)) as rate_by_from_cluster,
  (sum(sales_amt)::numeric / nullif(sum(sum(sales_amt)) over 
  (partition by prev_cluster_name),0)) as rate_by_from_cluster_wavg
from x
where prev_cluster_name is not null
group by 1,2
order by 1,2;





-- ============================================================
-- 12. 유지율 + pk_shift 연계 테이블 생성
-- ============================================================
------------유지율 (다음 분기에도 같은 군집인가?) + pk_shift 연계---------------------------
drop table if exists seoul.cohort_retention_by_quarter;

create table seoul.cohort_retention_by_quarter as
with x as (
  select
    e.*,
    ((e.yq/10)::int*4 + ((e.yq%10)::int - 1)) as q_index,

    lead(e.yq) over (
      partition by e."상권_코드", e."서비스_업종_코드"
      order by e.yq
    ) as next_yq,

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
  yq,
  cl_cluster_name as cluster_name_t,

  count(*) as n_pairs,

  avg((next_cluster_name = cl_cluster_name)::int::numeric) as retain_rate,

  sum(((next_cluster_name = cl_cluster_name)::int::numeric) * sales_amt)
    / nullif(sum(sales_amt),0) as retain_rate_wavg,

  avg(pk_shift::numeric) as pk_shift_rate,

  sum(pk_shift::numeric * sales_amt)
    / nullif(sum(sales_amt),0) as pk_shift_rate_wavg

from pairs
group by 1,2
order by 1,2;





-------------------------------------------------------------
WITH chk AS (
  SELECT
    e."상권_코드",
    e."서비스_업종_코드",
    e.yq,
    ((e.yq/10)::int*4 + ((e.yq%10)::int - 1)) AS q_index,
    LEAD(e.yq) OVER (
      PARTITION BY e."상권_코드", e."서비스_업종_코드"
      ORDER BY e.yq
    ) AS next_yq,
    LEAD(((e.yq/10)::int*4 + ((e.yq%10)::int - 1))) OVER (
      PARTITION BY e."상권_코드", e."서비스_업종_코드"
      ORDER BY e.yq
    ) AS next_q_index
  FROM seoul.v_cohort_q_enriched e
)
SELECT
  "상권_코드",
  "서비스_업종_코드",
  yq,
  next_yq,
  q_index,
  next_q_index,
  (next_q_index - q_index) AS jump
FROM chk
WHERE next_q_index IS NOT NULL
  AND next_q_index <> q_index + 1
ORDER BY jump DESC, yq
LIMIT 50;


WITH chk AS (
  SELECT
    e.yq,
    ((e.yq/10)::int*4 + ((e.yq%10)::int - 1)) AS q_index,
    LEAD(((e.yq/10)::int*4 + ((e.yq%10)::int - 1))) OVER (
      PARTITION BY e."상권_코드", e."서비스_업종_코드"
      ORDER BY e.yq
    ) AS next_q_index
  FROM seoul.v_cohort_q_enriched e
)
SELECT
  yq,
  COUNT(*) AS n_rows,
  COUNT(*) FILTER (WHERE next_q_index IS NOT NULL) AS n_has_next,
  COUNT(*) FILTER (
    WHERE next_q_index IS NOT NULL
      AND next_q_index <> q_index + 1
  ) AS n_fake_lead
FROM chk
GROUP BY 1
ORDER BY 1;




WITH pairs AS (
  SELECT
    e."상권_코드",
    e."서비스_업종_코드",
    e.yq,
    ((e.yq/10)::int*4 + ((e.yq%10)::int - 1)) AS q_index,
    LEAD(e.yq) OVER (
      PARTITION BY e."상권_코드", e."서비스_업종_코드"
      ORDER BY e.yq
    ) AS next_yq,
    LEAD(((e.yq/10)::int*4 + ((e.yq%10)::int - 1))) OVER (
      PARTITION BY e."상권_코드", e."서비스_업종_코드"
      ORDER BY e.yq
    ) AS next_q_index
  FROM seoul.v_cohort_q_enriched e
)
SELECT
  COUNT(*) FILTER (WHERE next_yq IS NOT NULL) AS n_pairs_all,
  COUNT(*) FILTER (WHERE next_yq IS NOT NULL AND next_q_index = q_index + 1) AS n_pairs_consecutive,
  COUNT(*) FILTER (WHERE next_yq IS NOT NULL AND next_q_index <> q_index + 1) AS n_pairs_fake
FROM pairs;


with chk as (
  select
    e."상권_코드",
    e."서비스_업종_코드",
    ((e.yq/10)::int*4 + ((e.yq%10)::int - 1)) as q_index,
    lead(((e.yq/10)::int*4 + ((e.yq%10)::int - 1))) over (
      partition by e."상권_코드", e."서비스_업종_코드"
      order by e.yq
    ) as next_q_index
  from seoul.v_cohort_q_enriched e
)
select
  count(*) as n_pairs_all,
  count(*) filter (where next_q_index = q_index + 1) as n_pairs_consecutive,
  count(*) filter (where next_q_index is not null and next_q_index <> q_index + 1) as n_fake
from chk;


select
  yq,
  sum(n_pairs) as total_pairs_retention
from seoul.cohort_retention_by_quarter
group by 1
order by 1;



with x as (
  select
    e.yq,
    ((e.yq/10)::int*4 + ((e.yq%10)::int - 1)) as q_index,
    lead(((e.yq/10)::int*4 + ((e.yq%10)::int - 1))) over (
      partition by e."상권_코드", e."서비스_업종_코드"
      order by e.yq
    ) as next_q_index
  from seoul.v_cohort_q_enriched e
)
select
  yq,
  count(*) as total_pairs_consecutive
from x
where next_q_index = q_index + 1
group by 1
order by 1;


-- ============================================================
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
