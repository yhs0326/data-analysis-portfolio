
/* ---------------------------------------------------------
   6) 논리적·수학적 검증 쿼리
--------------------------------------------------------- */

-- 6-1) year 값 분포 확인 (2017, 2023만 존재해야 함)
SELECT year, COUNT(*) AS n
FROM kwcs_analysis
GROUP BY year
ORDER BY year;

-- 6-1-보강) 허용값 외 year 개수
SELECT COUNT(*) AS invalid_year_count
FROM kwcs_analysis
WHERE year NOT IN (2017, 2023) OR year IS NULL;


-- 6-2) age 값 범위(1~6) 확인
SELECT COUNT(*) AS invalid_age_count
FROM kwcs_analysis
WHERE age NOT BETWEEN 1 AND 6 OR age IS NULL;

-- 6-2-참고) age 분포
SELECT age, COUNT(*) AS n
FROM kwcs_analysis
GROUP BY age
ORDER BY age;


-- 6-3) age_group 허용값(youth, middle_old) 확인
SELECT age_group, COUNT(*) AS n
FROM kwcs_analysis
GROUP BY age_group
ORDER BY age_group;

-- 6-3-보강) 허용값 외 age_group 개수
SELECT COUNT(*) AS invalid_age_group_count
FROM kwcs_analysis
WHERE age_group NOT IN ('youth', 'middle_old') OR age_group IS NULL;


-- 6-4) age와 age_group 논리 일치성 확인
-- 규칙:
--   age IN (2,3)      -> age_group='youth'
--   age IN (4,5,6)    -> age_group='middle_old'
-- (age=1은 규칙에서 명시되지 않아 여기서는 불일치 판정 제외)
SELECT COUNT(*) AS age_age_group_mismatch_count
FROM kwcs_analysis
WHERE
    (age IN (2, 3) AND age_group <> 'youth')
 OR (age IN (4, 5, 6) AND age_group <> 'middle_old');

-- 6-4-상세) 불일치 행 확인
SELECT *
FROM kwcs_analysis
WHERE
    (age IN (2, 3) AND age_group <> 'youth')
 OR (age IN (4, 5, 6) AND age_group <> 'middle_old')
ORDER BY year, age;


-- 6-5) quality_of_work 범위(1~5) 확인
SELECT COUNT(*) AS invalid_quality_of_work_count
FROM kwcs_analysis
WHERE quality_of_work IS NOT NULL
  AND (quality_of_work < 1 OR quality_of_work > 5);


-- 6-6) 점수형 변수별 허용 범위 확인 
SELECT
    SUM(CASE WHEN work_life_balance IS NOT NULL
              AND (work_life_balance < 1 OR work_life_balance > 4) THEN 1 ELSE 0 END) AS invalid_work_life_balance,
    SUM(CASE WHEN achievement IS NOT NULL
              AND (achievement < 1 OR achievement > 5) THEN 1 ELSE 0 END) AS invalid_achievement,
    SUM(CASE WHEN work_meaning IS NOT NULL
              AND (work_meaning < 1 OR work_meaning > 5) THEN 1 ELSE 0 END) AS invalid_work_meaning,
    SUM(CASE WHEN stress IS NOT NULL
              AND (stress < 1 OR stress > 5) THEN 1 ELSE 0 END) AS invalid_stress,
    SUM(CASE WHEN satisfaction IS NOT NULL
              AND (satisfaction < 1 OR satisfaction > 4) THEN 1 ELSE 0 END) AS invalid_satisfaction,
    SUM(CASE WHEN job_loss_risk IS NOT NULL
              AND (job_loss_risk < 1 OR job_loss_risk > 5) THEN 1 ELSE 0 END) AS invalid_job_loss_risk,
    SUM(CASE WHEN reemployment_possibility IS NOT NULL
              AND (reemployment_possibility < 1 OR reemployment_possibility > 5) THEN 1 ELSE 0 END) AS invalid_reemployment_possibility
FROM kwcs_analysis;


-- 6-7) 근로시간 비정상치 확인 (0 미만 또는 112 초과)
SELECT
    SUM(CASE WHEN work_hours IS NOT NULL
              AND (work_hours < 0 OR work_hours > 112) THEN 1 ELSE 0 END) AS invalid_work_hours_count,
    SUM(CASE WHEN preferred_hours IS NOT NULL
              AND (preferred_hours < 0 OR preferred_hours > 112) THEN 1 ELSE 0 END) AS invalid_preferred_hours_count
FROM kwcs_analysis;


-- 6-8) income 비정상치 확인 (만 원 단위: 0 미만 또는 10000 초과)
SELECT
    SUM(CASE WHEN income IS NOT NULL AND income < 0 THEN 1 ELSE 0 END) AS negative_income_count,
    SUM(CASE WHEN income IS NOT NULL AND income > 10000 THEN 1 ELSE 0 END) AS extreme_income_count
FROM kwcs_analysis;


-- 6-9) 주요 변수별 NULL 개수 확인
SELECT
    COUNT(*) AS total_rows,
    SUM(CASE WHEN year IS NULL THEN 1 ELSE 0 END) AS null_year,
    SUM(CASE WHEN age IS NULL THEN 1 ELSE 0 END) AS null_age,
    SUM(CASE WHEN age_group IS NULL THEN 1 ELSE 0 END) AS null_age_group,
    SUM(CASE WHEN gender IS NULL THEN 1 ELSE 0 END) AS null_gender,
    SUM(CASE WHEN emp_type IS NULL THEN 1 ELSE 0 END) AS null_emp_type,
    SUM(CASE WHEN full_part IS NULL THEN 1 ELSE 0 END) AS null_full_part,
    SUM(CASE WHEN income IS NULL THEN 1 ELSE 0 END) AS null_income,
    SUM(CASE WHEN work_hours IS NULL THEN 1 ELSE 0 END) AS null_work_hours,
    SUM(CASE WHEN preferred_hours IS NULL THEN 1 ELSE 0 END) AS null_preferred_hours,
    SUM(CASE WHEN work_life_balance IS NULL THEN 1 ELSE 0 END) AS null_work_life_balance,
    SUM(CASE WHEN achievement IS NULL THEN 1 ELSE 0 END) AS null_achievement,
    SUM(CASE WHEN work_meaning IS NULL THEN 1 ELSE 0 END) AS null_work_meaning,
    SUM(CASE WHEN stress IS NULL THEN 1 ELSE 0 END) AS null_stress,
    SUM(CASE WHEN satisfaction IS NULL THEN 1 ELSE 0 END) AS null_satisfaction,
    SUM(CASE WHEN job_loss_risk IS NULL THEN 1 ELSE 0 END) AS null_job_loss_risk,
    SUM(CASE WHEN reemployment_possibility IS NULL THEN 1 ELSE 0 END) AS null_reemployment_possibility,
    SUM(CASE WHEN quality_of_work IS NULL THEN 1 ELSE 0 END) AS null_quality_of_work
FROM kwcs_analysis;


-- 6-10) 2017/2023 컬럼 비교 A: ordinal_position 기준
WITH c2017 AS (
    SELECT column_name, ordinal_position, data_type
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'work2017_clean'
),
c2023 AS (
    SELECT column_name, ordinal_position, data_type
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'work2023_clean'
)
SELECT
    COALESCE(c2017.ordinal_position, c2023.ordinal_position) AS ordinal_position,
    c2017.column_name AS col_2017,
    c2023.column_name AS col_2023,
    c2017.data_type AS type_2017,
    c2023.data_type AS type_2023,
    CASE
        WHEN c2017.column_name IS NULL THEN 'ONLY_IN_2023'
        WHEN c2023.column_name IS NULL THEN 'ONLY_IN_2017'
        WHEN c2017.column_name <> c2023.column_name THEN 'NAME_MISMATCH_AT_POSITION'
        WHEN c2017.data_type <> c2023.data_type THEN 'TYPE_MISMATCH_AT_POSITION'
        ELSE 'MATCH_AT_POSITION'
    END AS compare_result
FROM c2017
FULL OUTER JOIN c2023
    ON c2017.ordinal_position = c2023.ordinal_position
ORDER BY ordinal_position;


-- 6-11) 2017/2023 컬럼 비교 B: column_name 기준 (순서 무관)
WITH c2017 AS (
    SELECT column_name, data_type
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'work2017_clean'
),
c2023 AS (
    SELECT column_name, data_type
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'work2023_clean'
)
SELECT
    COALESCE(c2017.column_name, c2023.column_name) AS column_name,
    c2017.data_type AS type_2017,
    c2023.data_type AS type_2023,
    CASE
        WHEN c2017.column_name IS NULL THEN 'ONLY_IN_2023'
        WHEN c2023.column_name IS NULL THEN 'ONLY_IN_2017'
        WHEN c2017.data_type <> c2023.data_type THEN 'TYPE_MISMATCH'
        ELSE 'MATCH'
    END AS compare_result
FROM c2017
FULL OUTER JOIN c2023
    ON c2017.column_name = c2023.column_name
ORDER BY column_name;

-- 6-12) 컬럼 수 요약 비교
SELECT
    (SELECT COUNT(*)
     FROM information_schema.columns
     WHERE table_schema='public' AND table_name='work2017_clean') AS col_count_2017,
    (SELECT COUNT(*)
     FROM information_schema.columns
     WHERE table_schema='public' AND table_name='work2023_clean') AS col_count_2023;


/* ---------------------------------------------------------
   7) 테이블별 행 수 확인
--------------------------------------------------------- */
SELECT 'work2017_clean' AS table_name, COUNT(*) AS n FROM work2017_clean
UNION ALL
SELECT 'work2023_clean' AS table_name, COUNT(*) AS n FROM work2023_clean
UNION ALL
SELECT 'kwcs_all' AS table_name, COUNT(*) AS n FROM kwcs_all
UNION ALL
SELECT 'kwcs_analysis' AS table_name, COUNT(*) AS n FROM kwcs_analysis
UNION ALL
SELECT 'kwcs_model_data' AS table_name, COUNT(*) AS n FROM kwcs_model_data
ORDER BY table_name;