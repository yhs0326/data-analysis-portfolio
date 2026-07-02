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

