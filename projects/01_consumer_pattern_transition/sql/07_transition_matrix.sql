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
