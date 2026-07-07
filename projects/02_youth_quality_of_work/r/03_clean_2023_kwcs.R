# ==========================================
# 2023 근로환경조사 설문 응답값 전처리
# ==========================================
# 숫자형 그대로 두는 변수:
# age, income, work_hours, preferred_hours, year
#
# 범주형/순서형으로 재코딩할 변수:
# gender, emp_type, full_part,
# work_life_balance, achievement, work_meaning,
# stress, satisfaction,
# job_loss_risk, reemployment_possibility
#
# 원칙:
# 1. 결측 코드(7, 8, 9)는 NA로 변환
# 2. 모든 변수는 "값이 클수록 좋음" 방향으로 통일
# 3. 최종 점수 범위는 대부분 1~5
# ==========================================
getwd()
setwd('C:/kossda 공모전')
work2023_sel <- read.csv('work2023_sel.csv', header = TRUE)
library(dplyr)

work2023_clean <- work2023_sel %>%
  mutate(
    
    # --------------------------------------
    # 1. 성별
    # 원자료: 1=남자, 2=여자
    # 분석용: 1=남자, 0=여자
    # --------------------------------------
    gender = case_when(
      gender == 1 ~ 1,
      gender == 2 ~ 0,
      TRUE ~ NA_real_
    ),
    
    # --------------------------------------
    # 2. 종사상 지위(emp_type)
    # 원자료 코드북 기준 범주형 변수
    # 값 자체는 유지하고, 결측만 NA 처리
    # --------------------------------------
    emp_type = na_if(emp_type, 9),
    
    # --------------------------------------
    # 3. 전일제/시간제(full_part)
    # 원자료 코드북 기준 범주형 변수
    # 값 자체는 유지하고, 결측만 NA 처리
    # --------------------------------------
    full_part = case_when(
      full_part %in% c(8, 9) ~ NA_real_,
      TRUE ~ as.numeric(full_part)
    ),
    
    # --------------------------------------
    # 4. Work-Life Balance
    # 코드북:
    # 1 매우 적당하다
    # 2 적당하다
    # 3 적당하지 않다
    # 4 전혀 적당하지 않다
    # 8,9 결측
    #
    # 값이 클수록 좋게:
    # 1 -> 4
    # 2 -> 3
    # 3 -> 2
    # 4 -> 1
    # --------------------------------------
    work_life_balance = case_when(
      work_life_balance %in% c(8, 9) ~ NA_real_,
      TRUE ~ 5 - work_life_balance
    ),
    
    # --------------------------------------
    # 5. 성취감(achievement)
    # 1 항상 그렇다 ... 5 전혀 그렇지 않다
    # 값이 클수록 좋게:
    # 1 -> 5, 2 -> 4, ..., 5 -> 1
    # --------------------------------------
    achievement = case_when(
      achievement %in% c(7, 8, 9) ~ NA_real_,
      TRUE ~ 6 - achievement
    ),
    
    # --------------------------------------
    # 6. 일의 의미(work_meaning)
    # 동일 방식
    # --------------------------------------
    work_meaning = case_when(
      work_meaning %in% c(7, 8, 9) ~ NA_real_,
      TRUE ~ 6 - work_meaning
    ),
    
    # --------------------------------------
    # 7. 스트레스(stress)
    # 원자료:
    # 1 항상 스트레스를 받음
    # 5 전혀 스트레스를 받지 않음
    #
    # 이미 값이 클수록 좋음
    # --------------------------------------
    stress = case_when(
      stress %in% c(7, 8, 9) ~ NA_real_,
      TRUE ~ stress
    ),
    
    # --------------------------------------
    # 8. 근로환경 만족도(satisfaction)
    # 1 매우 만족, 4 전혀 만족하지 않음
    # 값이 클수록 좋게:
    # 1 -> 4, 2 -> 3, 3 -> 2, 4 -> 1
    # --------------------------------------
    satisfaction = case_when(
      satisfaction %in% c(8, 9) ~ NA_real_,
      TRUE ~ 5 - satisfaction
    ),
    
    # --------------------------------------
    # 9. 실직 위험(job_loss_risk)
    # wstat6
    # 코드북 확인 결과 일반적으로
    # 1 매우 그렇다 (실직 위험 큼)
    # ...
    # 5 전혀 그렇지 않다 (실직 위험 낮음)
    #
    # 이미 값이 클수록 좋음
    # --------------------------------------
    job_loss_risk = case_when(
      job_loss_risk %in% c(7, 8, 9) ~ NA_real_,
      TRUE ~ job_loss_risk
    ),
    
    # --------------------------------------
    # 10. 재취업 가능성(reemployment_possibility)
    # 1 매우 어렵다 ... 5 매우 쉽다 (또는 유사 구조)
    # 값이 클수록 좋다고 가정
    # --------------------------------------
    reemployment_possibility = case_when(
      reemployment_possibility %in% c(7, 8, 9) ~ NA_real_,
      TRUE ~ reemployment_possibility
    ),
    
    # --------------------------------------
    # 11. 소득 결측 처리
    # --------------------------------------
    income = case_when(
      income %in% c(7777, 8888, 9999) ~ NA_real_,
      TRUE ~ as.numeric(income)
    ),
    # --------------------------------------
    # 12. 희망 근로시간(preferred_hours) 결측 처리
    # ptime_r 변수는 숫자형 근로시간이며,
    # 코드북 기준 무응답/거절 값은 매우 큰 특수코드로 저장될 수 있음.
    # 현재 데이터에서는 income과 동일하게
    # 888888 = 모름/무응답
    # 999999 = 거절
    # 로 처리
    # --------------------------------------
    preferred_hours = case_when(
      preferred_hours %in% c(888, 999) ~ NA_real_,
      TRUE ~ as.numeric(preferred_hours)
    ),
    work_hours = case_when(
      work_hours %in% c(888, 999, 888888, 999999) ~ NA_real_,
      TRUE ~ as.numeric(work_hours)
    )
  )

# ==========================================
# 노동의 질(Quality of Work Life) 지수 생성
# 모든 변수는 값이 클수록 좋은 방향으로 통일됨
# ==========================================
work2023_clean <- work2023_clean %>%
  mutate(
    quality_of_work = rowMeans(
      select(
        .,
        work_life_balance,
        achievement,
        work_meaning,
        stress,
        satisfaction,
        job_loss_risk,
        reemployment_possibility
      ),
      na.rm = TRUE
    )
  )


# 2023 실제 나이를 2017과 동일한 연령대 코드로 변환
work2023_clean <- work2023_clean %>%
  mutate(
    age = case_when(
      age >= 15 & age <= 19 ~ 1,
      age >= 20 & age <= 29 ~ 2,
      age >= 30 & age <= 39 ~ 3,
      age >= 40 & age <= 49 ~ 4,
      age >= 50 & age <= 59 ~ 5,
      age >= 60 ~ 6,
      TRUE ~ NA_real_
    ),
    
    # 청년(20~39세) vs 중장년·고령(40세 이상)
    age_group = case_when(
      age %in% c(2, 3) ~ "youth",
      age %in% c(4, 5, 6) ~ "middle_old",
      TRUE ~ NA_character_
    )
  )
# ==========================================
# 확인
# ==========================================
summary(work2023_clean)
write.csv(work2023_clean, "work2023_clean.csv", row.names = FALSE, fileEncoding = "UTF-8")


