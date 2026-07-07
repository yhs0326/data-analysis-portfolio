-------2017,2023 raw table 생성---------
DROP TABLE IF EXISTS work2017_clean;
DROP TABLE IF EXISTS work2023_clean;

CREATE TABLE work2017_clean (
    age numeric,
    gender numeric,
    emp_type numeric,
    full_part numeric,
    income numeric,
    work_hours numeric,
    preferred_hours numeric,
    work_life_balance numeric,
    achievement numeric,
    work_meaning numeric,
    stress numeric,
    satisfaction numeric,
    job_loss_risk numeric,
    reemployment_possibility numeric,
    year numeric,
    quality_of_work numeric,
    age_group text
);

CREATE TABLE work2023_clean (
    age numeric,
    gender numeric,
    emp_type numeric,
    full_part numeric,
    income numeric,
    work_hours numeric,
    preferred_hours numeric,
    work_life_balance numeric,
    achievement numeric,
    work_meaning numeric,
    stress numeric,
    satisfaction numeric,
    job_loss_risk numeric,
    reemployment_possibility numeric,
    year numeric,
    quality_of_work numeric,
    age_group text
);

SELECT COUNT(*) FROM work2017_clean;
SELECT COUNT(*) FROM work2023_clean;



