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
