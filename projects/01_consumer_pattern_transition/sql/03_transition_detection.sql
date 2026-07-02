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


