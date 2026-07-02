-- 8. 코호트 분석 테이블 생성
-- ============================================================
-------코호트 분석 테이블 만들기------
truncate table seoul.cohort_q;
drop table if exists seoul.cohort_q;

create table seoul.cohort_q (
  "상권_코드" text,
  "서비스_업종_코드" text,
  "yq" int,
  "pk_shift" int,
  "cl_cluster_shift" int,
  "cl_cluster_name" text
);

select count(*) from seoul.cohort_q;

-----성능을 위한 인덱스-----
create index if not exists ix_cohort_q_key_yq
on seoul.cohort_q("상권_코드","서비스_업종_코드","yq");

create index if not exists ix_cohort_q_yq
on seoul.cohort_q("yq");


-- ============================================================
