
/* ---------------------------------------------------------
   4) year, age_group별 표본 수와 quality_of_work 평균
--------------------------------------------------------- */
SELECT
    year,
    age_group,
    COUNT(*) AS sample_n,
    ROUND(AVG(quality_of_work)::numeric, 4) AS mean_quality_of_work
FROM kwcs_model_data
GROUP BY year, age_group
ORDER BY year, age_group;


/* ---------------------------------------------------------
   5) year, age_group별 주요 지표 평균
   - satisfaction, work_life_balance, stress,
     job_loss_risk, reemployment_possibility
--------------------------------------------------------- */
SELECT
    year,
    age_group,
    ROUND(AVG(satisfaction)::numeric, 4) AS mean_satisfaction,
    ROUND(AVG(work_life_balance)::numeric, 4) AS mean_work_life_balance,
    ROUND(AVG(stress)::numeric, 4) AS mean_stress,
    ROUND(AVG(job_loss_risk)::numeric, 4) AS mean_job_loss_risk,
    ROUND(AVG(reemployment_possibility)::numeric, 4) AS mean_reemployment_possibility
FROM kwcs_model_data
GROUP BY year, age_group
ORDER BY year, age_group;

