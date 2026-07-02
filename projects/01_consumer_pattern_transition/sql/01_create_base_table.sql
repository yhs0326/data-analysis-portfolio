-- 원본 SQL의 내용과 실행 순서는 변경하지 않았습니다.
-- 가독성을 위해 섹션 주석만 추가했습니다.
-- 원본에 있던 검증용/점검용 쿼리도 그대로 유지했습니다.
-- 현재 버전은 포트폴리오용 정리본이며, 로직 수정은 하지 않았습니다.

-- ============================================================
-- 1. Raw table 생성
-- ============================================================
------raw table 생성--------

create schema if not exists seoul;

drop table if exists seoul.card_sales_q_raw;
create table seoul.card_sales_q_raw(
"기준_년분기_코드" int,
  "상권_구분_코드" text,
  "상권_구분_코드_명" text,
  "상권_코드" text,
  "상권_코드_명" text,
  "서비스_업종_코드" text,
  "서비스_업종_코드_명" text,

  "당월_매출_금액" bigint,

  "주중_매출_금액" bigint,
  "주말_매출_금액" bigint,

  "월요일_매출_금액" bigint,
  "화요일_매출_금액" bigint,
  "수요일_매출_금액" bigint,
  "목요일_매출_금액" bigint,
  "금요일_매출_금액" bigint,
  "토요일_매출_금액" bigint,
  "일요일_매출_금액" bigint,

  "시간대_00~06_매출_금액" bigint,
  "시간대_06~11_매출_금액" bigint,
  "시간대_11~14_매출_금액" bigint,
  "시간대_14~17_매출_금액" bigint,
  "시간대_17~21_매출_금액" bigint,
  "시간대_21~24_매출_금액" bigint,

  "남성_매출_금액" bigint,
  "여성_매출_금액" bigint,

  "연령대_10_매출_금액" bigint,
  "연령대_20_매출_금액" bigint,
  "연령대_30_매출_금액" bigint,
  "연령대_40_매출_금액" bigint,
  "연령대_50_매출_금액" bigint,
  "연령대_60_이상_매출_금액" bigint,

  "당월_매출_건수" bigint,

  "주중_매출_건수" bigint,
  "주말_매출_건수" bigint,

  "월요일_매출_건수" bigint,
  "화요일_매출_건수" bigint,
  "수요일_매출_건수" bigint,
  "목요일_매출_건수" bigint,
  "금요일_매출_건수" bigint,
  "토요일_매출_건수" bigint,
  "일요일_매출_건수" bigint,

  "시간대_건수~06_매출_건수" bigint,
  "시간대_건수~11_매출_건수" bigint,
  "시간대_건수~14_매출_건수" bigint,
  "시간대_건수~17_매출_건수" bigint,
  "시간대_건수~21_매출_건수" bigint,
  "시간대_건수~24_매출_건수" bigint,

  "남성_매출_건수" bigint,
  "여성_매출_건수" bigint,

  "연령대_10_매출_건수" bigint,
  "연령대_20_매출_건수" bigint,
  "연령대_30_매출_건수" bigint,
  "연령대_40_매출_건수" bigint,
  "연령대_50_매출_건수" bigint,
  "연령대_60_이상_매출_건수" bigint
);

select count(*) from seoul.card_sales_q_raw;


