이 SQL쿼리는 원본 분석 스크립트 일부가 저장 과정에서 유실되어,
분석에 사용된 CSV 결과와 Python 코드 흐름을 기준으로
데이터 처리 및 feature 생성 과정을 재구성한 포트폴리오용 SQL입니다.

============================================================================
   RAW 테이블 생성 (CSV 적재용)
   - 아래 CREATE TABLE까지가 “스키마 정의”
   - CSV 적재는 psql의 \copy 또는 pgAdmin import 기능으로 수행
============================================================================ 

 =====1) 외국인 블록 데이터====
DROP TABLE IF EXISTS foreign_block_clean;

CREATE TABLE foreign_block_clean (
  blck_cd      integer,
  sf_upjong_cd text,
  ts_ym        integer,
  ts_ymd       integer,
  tm_cd        text,
  tm_range     text,
  amt_corr     numeric,
  usect_corr   numeric,
  data         date
);

=====2) 내국인 블록 데이터====== 
DROP TABLE IF EXISTS local_block_clean;

CREATE TABLE local_block_clean (
  blck_cd      integer,
  sb_upjong_cd text,
  ts_ym        integer,
  ts_ymd       integer,
  tm           text,
  amt_corr     numeric,
  usect_corr   numeric,
  daw          text,
  tm_cd        text,
  tm_range     text,
  data         date
);

========3) 내국인 업종 코드=========
DROP TABLE IF EXISTS local_code_clean;

CREATE TABLE local_code_clean (
  sb_l_upjong_nm text,
  sb_m_upjong_nm text,
  sb_upjong_nm   text,
  sb_upjong_cd   text
);

=======4) 외국인 업종 코드========
DROP TABLE IF EXISTS foreign_code_clean;

CREATE TABLE foreign_code_clean (
  sf_l_upjong_cd text,
  sf_l_upjong_nm text,
  sf_m_upjong_cd text,
  sf_m_upjong_nm text,
  sf_upjong_cd   text,
  sf_upjong_nm   text
);

============================================================================
   [1] CSV 적재 후 row count 확인
============================================================================
SELECT COUNT(*) FROM local_block_clean;
SELECT COUNT(*) FROM local_code_clean;
SELECT COUNT(*) FROM foreign_block_clean;
SELECT COUNT(*) FROM foreign_code_clean;


 ============================================================================
   [2] 내국인: 코드 정규화 + local_final 생성 + data -> date
============================================================================ 

=======2-1) 조인 키 정규화(대문자/공백 문제 방지)=======
UPDATE local_block_clean
SET sb_upjong_cd = lower(trim(sb_upjong_cd))
WHERE sb_upjong_cd IS NOT NULL;

UPDATE local_code_clean
SET sb_upjong_cd = lower(trim(sb_upjong_cd))
WHERE sb_upjong_cd IS NOT NULL;

=======2-2) local_final 생성(내국인 블록 + 업종명 매핑)=====
DROP TABLE IF EXISTS local_final;

CREATE TABLE local_final AS
SELECT
  l.*,
  c.sb_l_upjong_nm,
  c.sb_m_upjong_nm,
  c.sb_upjong_nm
FROM local_block_clean l
LEFT JOIN local_code_clean c
  ON l.sb_upjong_cd = c.sb_upjong_cd;

=======2-3) 날짜 컬럼명 정리: data -> date===========
ALTER TABLE local_final RENAME COLUMN data TO date;

========2-4) 날짜 범위/행 수 확인========
-- SELECT MIN(date) AS min_date, MAX(date) AS max_date, COUNT(*) AS n_rows FROM local_final;

========2-5) 기간 분할 행 수 확인========
SELECT
   SUM(CASE WHEN date BETWEEN '2017-01-01' AND '2019-12-31' THEN 1 ELSE 0 END) AS pre_rows,
   SUM(CASE WHEN date BETWEEN '2020-01-01' AND '2021-07-29' THEN 1 ELSE 0 END) AS post_rows
FROM local_final;


 ============================================================================
   [3] 내국인: pre_feat / post_feat 생성
   - 중분류(sb_m_upjong_nm) 기준 “리듬 피처”
   - NULL은 COALESCE로 0 처리하여 군집분석에서 NaN 방지
============================================================================

========3-1) pre_feat (2017~2019)========
DROP TABLE IF EXISTS pre_feat;

CREATE TABLE pre_feat AS
WITH agg AS (
  SELECT
    sb_m_upjong_nm,
    MIN(sb_l_upjong_nm) AS sb_l_upjong_nm,

    SUM(amt_corr)   AS total_amt,
    SUM(usect_corr) AS total_usect,

    COALESCE(SUM(amt_corr) FILTER (WHERE tm_cd='T1'), 0) AS amt_t1,
    COALESCE(SUM(amt_corr) FILTER (WHERE tm_cd='T2'), 0) AS amt_t2,
    COALESCE(SUM(amt_corr) FILTER (WHERE tm_cd='T3'), 0) AS amt_t3,
    COALESCE(SUM(amt_corr) FILTER (WHERE tm_cd='T4'), 0) AS amt_t4,
    COALESCE(SUM(amt_corr) FILTER (WHERE tm_cd='T5'), 0) AS amt_t5,
    COALESCE(SUM(amt_corr) FILTER (WHERE tm_cd='T6'), 0) AS amt_t6,

    COALESCE(SUM(amt_corr) FILTER (WHERE daw IN ('토요일','일요일')), 0) AS amt_wknd
  FROM local_final
  WHERE date BETWEEN '2017-01-01' AND '2019-12-31'
  GROUP BY sb_m_upjong_nm
)
SELECT
  sb_l_upjong_nm,
  sb_m_upjong_nm,
  total_amt,
  total_usect,
  total_amt / NULLIF(total_usect, 0) AS avg_pay,

  amt_t1 / NULLIF(total_amt, 0) AS s_t1,
  amt_t2 / NULLIF(total_amt, 0) AS s_t2,
  amt_t3 / NULLIF(total_amt, 0) AS s_t3,
  amt_t4 / NULLIF(total_amt, 0) AS s_t4,
  amt_t5 / NULLIF(total_amt, 0) AS s_t5,
  amt_t6 / NULLIF(total_amt, 0) AS s_t6,

  amt_wknd / NULLIF(total_amt, 0) AS s_wknd,

  GREATEST(amt_t1, amt_t2, amt_t3, amt_t4, amt_t5, amt_t6) / NULLIF(total_amt, 0) AS s_peak
FROM agg
WHERE total_amt IS NOT NULL AND total_amt <> 0;

========3-2) post_feat (2020~2021-07-29)============
DROP TABLE IF EXISTS post_feat;

CREATE TABLE post_feat AS
WITH agg AS (
  SELECT
    sb_m_upjong_nm,
    MIN(sb_l_upjong_nm) AS sb_l_upjong_nm,

    SUM(amt_corr)   AS total_amt,
    SUM(usect_corr) AS total_usect,

    COALESCE(SUM(amt_corr) FILTER (WHERE tm_cd='T1'), 0) AS amt_t1,
    COALESCE(SUM(amt_corr) FILTER (WHERE tm_cd='T2'), 0) AS amt_t2,
    COALESCE(SUM(amt_corr) FILTER (WHERE tm_cd='T3'), 0) AS amt_t3,
    COALESCE(SUM(amt_corr) FILTER (WHERE tm_cd='T4'), 0) AS amt_t4,
    COALESCE(SUM(amt_corr) FILTER (WHERE tm_cd='T5'), 0) AS amt_t5,
    COALESCE(SUM(amt_corr) FILTER (WHERE tm_cd='T6'), 0) AS amt_t6,

    COALESCE(SUM(amt_corr) FILTER (WHERE daw IN ('토요일','일요일')), 0) AS amt_wknd
  FROM local_final
  WHERE date BETWEEN '2020-01-01' AND '2021-07-29'
  GROUP BY sb_m_upjong_nm
)
SELECT
  sb_l_upjong_nm,
  sb_m_upjong_nm,
  total_amt,
  total_usect,
  total_amt / NULLIF(total_usect, 0) AS avg_pay,

  amt_t1 / NULLIF(total_amt, 0) AS s_t1,
  amt_t2 / NULLIF(total_amt, 0) AS s_t2,
  amt_t3 / NULLIF(total_amt, 0) AS s_t3,
  amt_t4 / NULLIF(total_amt, 0) AS s_t4,
  amt_t5 / NULLIF(total_amt, 0) AS s_t5,
  amt_t6 / NULLIF(total_amt, 0) AS s_t6,

  amt_wknd / NULLIF(total_amt, 0) AS s_wknd,

  GREATEST(amt_t1, amt_t2, amt_t3, amt_t4, amt_t5, amt_t6) / NULLIF(total_amt, 0) AS s_peak
FROM agg
WHERE total_amt IS NOT NULL AND total_amt <> 0;

==========3-3) share 합 검증============
SELECT sb_m_upjong_nm, (s_t1+s_t2+s_t3+s_t4+s_t5+s_t6) AS sum_share
FROM pre_feat
ORDER BY ABS(1-(s_t1+s_t2+s_t3+s_t4+s_t5+s_t6)) DESC
LIMIT 10;


============================================================================
   [4] 외국인: 코드 정규화 + foreign_final 생성 + data -> date + daw(요일) 생성
============================================================================

==========4-1) 조인 키 정규화============
UPDATE foreign_block_clean
SET sf_upjong_cd = lower(trim(sf_upjong_cd))
WHERE sf_upjong_cd IS NOT NULL;

UPDATE foreign_code_clean
SET sf_upjong_cd = lower(trim(sf_upjong_cd))
WHERE sf_upjong_cd IS NOT NULL;

========4-2) foreign_final 생성(외국인 블록 + 업종명 매핑)=========
DROP TABLE IF EXISTS foreign_final;

CREATE TABLE foreign_final AS
SELECT
  f.*,
  c.sf_l_upjong_nm,
  c.sf_m_upjong_nm,
  c.sf_upjong_nm
FROM foreign_block_clean f
LEFT JOIN foreign_code_clean c
  ON f.sf_upjong_cd = c.sf_upjong_cd;

===========4-3) 날짜 컬럼명 정리: data -> date===========
ALTER TABLE foreign_final RENAME COLUMN data TO date;

========4-4) 외국인 요일 컬럼(daw) 추가 및 채우기=========
ALTER TABLE foreign_final ADD COLUMN daw text;

UPDATE foreign_final
SET daw = CASE EXTRACT(DOW FROM date)
  WHEN 0 THEN '일요일'
  WHEN 1 THEN '월요일'
  WHEN 2 THEN '화요일'
  WHEN 3 THEN '수요일'
  WHEN 4 THEN '목요일'
  WHEN 5 THEN '금요일'
  WHEN 6 THEN '토요일'
END;

============================================================================
   [5] 외국인: f_pre_feat / f_post_feat 생성
============================================================================ 

===============5-1) f_pre_feat (2017~2019)=============
DROP TABLE IF EXISTS f_pre_feat;

CREATE TABLE f_pre_feat AS
WITH agg AS (
  SELECT
    sf_m_upjong_nm,
    MIN(sf_l_upjong_nm) AS sf_l_upjong_nm,

    SUM(amt_corr)   AS total_amt,
    SUM(usect_corr) AS total_usect,

    COALESCE(SUM(amt_corr) FILTER (WHERE tm_cd='T1'), 0) AS amt_t1,
    COALESCE(SUM(amt_corr) FILTER (WHERE tm_cd='T2'), 0) AS amt_t2,
    COALESCE(SUM(amt_corr) FILTER (WHERE tm_cd='T3'), 0) AS amt_t3,
    COALESCE(SUM(amt_corr) FILTER (WHERE tm_cd='T4'), 0) AS amt_t4,
    COALESCE(SUM(amt_corr) FILTER (WHERE tm_cd='T5'), 0) AS amt_t5,
    COALESCE(SUM(amt_corr) FILTER (WHERE tm_cd='T6'), 0) AS amt_t6,

    COALESCE(SUM(amt_corr) FILTER (WHERE daw IN ('토요일','일요일')), 0) AS amt_wknd
  FROM foreign_final
  WHERE date BETWEEN '2017-01-01' AND '2019-12-31'
  GROUP BY sf_m_upjong_nm
)
SELECT
  sf_l_upjong_nm,
  sf_m_upjong_nm,
  total_amt,
  total_usect,
  total_amt / NULLIF(total_usect, 0) AS avg_pay,

  amt_t1 / NULLIF(total_amt, 0) AS s_t1,
  amt_t2 / NULLIF(total_amt, 0) AS s_t2,
  amt_t3 / NULLIF(total_amt, 0) AS s_t3,
  amt_t4 / NULLIF(total_amt, 0) AS s_t4,
  amt_t5 / NULLIF(total_amt, 0) AS s_t5,
  amt_t6 / NULLIF(total_amt, 0) AS s_t6,

  amt_wknd / NULLIF(total_amt, 0) AS s_wknd,

  GREATEST(amt_t1, amt_t2, amt_t3, amt_t4, amt_t5, amt_t6) / NULLIF(total_amt, 0) AS s_peak
FROM agg
WHERE total_amt IS NOT NULL AND total_amt <> 0;

============5-2) f_post_feat (2020~2021-07-29)==========
DROP TABLE IF EXISTS f_post_feat;

CREATE TABLE f_post_feat AS
WITH agg AS (
  SELECT
    sf_m_upjong_nm,
    MIN(sf_l_upjong_nm) AS sf_l_upjong_nm,

    SUM(amt_corr)   AS total_amt,
    SUM(usect_corr) AS total_usect,

    COALESCE(SUM(amt_corr) FILTER (WHERE tm_cd='T1'), 0) AS amt_t1,
    COALESCE(SUM(amt_corr) FILTER (WHERE tm_cd='T2'), 0) AS amt_t2,
    COALESCE(SUM(amt_corr) FILTER (WHERE tm_cd='T3'), 0) AS amt_t3,
    COALESCE(SUM(amt_corr) FILTER (WHERE tm_cd='T4'), 0) AS amt_t4,
    COALESCE(SUM(amt_corr) FILTER (WHERE tm_cd='T5'), 0) AS amt_t5,
    COALESCE(SUM(amt_corr) FILTER (WHERE tm_cd='T6'), 0) AS amt_t6,

    COALESCE(SUM(amt_corr) FILTER (WHERE daw IN ('토요일','일요일')), 0) AS amt_wknd
  FROM foreign_final
  WHERE date BETWEEN '2020-01-01' AND '2021-07-29'
  GROUP BY sf_m_upjong_nm
)
SELECT
  sf_l_upjong_nm,
  sf_m_upjong_nm,
  total_amt,
  total_usect,
  total_amt / NULLIF(total_usect, 0) AS avg_pay,

  amt_t1 / NULLIF(total_amt, 0) AS s_t1,
  amt_t2 / NULLIF(total_amt, 0) AS s_t2,
  amt_t3 / NULLIF(total_amt, 0) AS s_t3,
  amt_t4 / NULLIF(total_amt, 0) AS s_t4,
  amt_t5 / NULLIF(total_amt, 0) AS s_t5,
  amt_t6 / NULLIF(total_amt, 0) AS s_t6,

  amt_wknd / NULLIF(total_amt, 0) AS s_wknd,

  GREATEST(amt_t1, amt_t2, amt_t3, amt_t4, amt_t5, amt_t6) / NULLIF(total_amt, 0) AS s_peak
FROM agg
WHERE total_amt IS NOT NULL AND total_amt <> 0;
