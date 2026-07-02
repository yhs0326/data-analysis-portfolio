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


-- ============================================================
