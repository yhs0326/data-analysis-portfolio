/* =========================================================
   KOSSDA 청년 고용 분석 SQL (PostgreSQL)
   - 핵심 테이블: work2017_clean, work2023_clean
   - 트랜잭션(BEGIN/COMMIT) 사용하지 않음
   ========================================================= */


/* ---------------------------------------------------------
   0) 기존 생성 테이블 삭제
--------------------------------------------------------- */
DROP TABLE IF EXISTS kwcs_model_data;
DROP TABLE IF EXISTS kwcs_analysis;
DROP TABLE IF EXISTS kwcs_all;


/* ---------------------------------------------------------
   1) 2017 + 2023 결합 테이블 생성 (UNION ALL)
--------------------------------------------------------- */
CREATE TABLE kwcs_all AS
SELECT *
FROM work2017_clean
UNION ALL
SELECT *
FROM work2023_clean;


/* ---------------------------------------------------------
   2) age_group이 NULL이 아닌 행만 남긴 분석 테이블 생성
--------------------------------------------------------- */
CREATE TABLE kwcs_analysis AS
SELECT *
FROM kwcs_all
WHERE age_group IS NOT NULL;


/* ---------------------------------------------------------
   3) Python 분석용 최종 테이블 생성
   - 조건: age_group IS NOT NULL, quality_of_work IS NOT NULL
   - 변수: 요청한 17개 변수만 포함
--------------------------------------------------------- */
CREATE TABLE kwcs_model_data AS
SELECT
    year,
    age,
    age_group,
    gender,
    emp_type,
    full_part,
    income,
    work_hours,
    preferred_hours,
    work_life_balance,
    achievement,
    work_meaning,
    stress,
    satisfaction,
    job_loss_risk,
    reemployment_possibility,
    quality_of_work
FROM kwcs_analysis
WHERE age_group IS NOT NULL
  AND quality_of_work IS NOT NULL;

