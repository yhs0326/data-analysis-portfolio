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



