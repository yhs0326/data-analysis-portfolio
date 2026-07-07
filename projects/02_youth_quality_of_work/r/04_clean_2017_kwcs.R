#2017년 데이터
getwd()
setwd('C:/kossda 공모전')
work2017_sel <- read.csv('work2017_sel.csv', header = TRUE)
library(dplyr)

work2017_clean <- work2017_sel %>%
  mutate(
    # 월평균 소득 EF11: 888888=모름/무응답, 999999=거절
    income = case_when(
      income %in% c(888888, 999999) ~ NA_real_,
      TRUE ~ as.numeric(income)
    ),
    
    # Q37 워라밸
    # 1=매우 적당하다, 4=전혀 적당하지 않다
    # 높을수록 좋게 변환: 1→4, 2→3, 3→2, 4→1
    work_life_balance = case_when(
      work_life_balance %in% c(8, 9) ~ NA_real_,
      TRUE ~ 5 - as.numeric(work_life_balance)
    ),
    
    # Q49_8 성취감
    # 1=항상 그렇다, 5=전혀 그렇지 않다
    # 높을수록 좋게 변환
    achievement = case_when(
      achievement %in% c(7, 8, 9) ~ NA_real_,
      TRUE ~ 6 - as.numeric(achievement)
    ),
    
    # Q49_10 일의 의미
    # 높을수록 좋게 변환
    work_meaning = case_when(
      work_meaning %in% c(7, 8, 9) ~ NA_real_,
      TRUE ~ 6 - as.numeric(work_meaning)
    ),
    
    # Q49_13 업무 스트레스
    # 1=항상 스트레스 받음, 5=전혀 그렇지 않다
    # 이미 높을수록 좋은 방향
    stress = case_when(
      stress %in% c(7, 8, 9) ~ NA_real_,
      TRUE ~ as.numeric(stress)
    ),
    
    # Q69 근로환경 만족도
    # 1=매우 만족, 4=전혀 만족하지 않음
    # 높을수록 좋게 변환
    satisfaction = case_when(
      satisfaction %in% c(8, 9) ~ NA_real_,
      TRUE ~ 5 - as.numeric(satisfaction)
    ),
    
    # Q70_7 실직 위험
    # 1=매우 동의, 5=전혀 동의하지 않음
    # 이미 높을수록 실직위험이 낮음 = 좋음
    job_loss_risk = case_when(
      job_loss_risk %in% c(7, 8, 9) ~ NA_real_,
      TRUE ~ as.numeric(job_loss_risk)
    ),
    
    # Q70_8 재취업 가능성
    # 1=매우 동의(좋음), 5=전혀 동의하지 않음(나쁨)
    # 높을수록 좋게 변환
    reemployment_possibility = case_when(
      reemployment_possibility %in% c(7, 8, 9) ~ NA_real_,
      TRUE ~ 6 - as.numeric(reemployment_possibility)
    ),
    # 전일제/시간제 KQ08: 1=전일제, 2=시간제, 888/999 결측
    full_part = case_when(
      full_part %in% c(8, 9, 88, 99, 888, 999) ~ NA_real_,
      TRUE ~ as.numeric(full_part)
    )
  ) %>%
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
    ),
    # 실제 주당 근로시간 Q22_1: 888=모름/무응답, 999=거절
    work_hours = case_when(
      work_hours %in% c(888, 999, 888888, 999999) ~ NA_real_,
      TRUE ~ as.numeric(work_hours)
    ),
    
    # 희망 주당 근로시간 Q23_1
    # 777=현재와 동일 → 실제 근로시간으로 대체
    # 888=모름/무응답, 999=거절
    preferred_hours = case_when(
      preferred_hours == 777 ~ as.numeric(work_hours),
      preferred_hours %in% c(888, 999, 888888, 999999) ~ NA_real_,
      TRUE ~ as.numeric(preferred_hours)
    )
  )

work2017_clean <- work2017_clean %>%
  mutate(
    age_group = case_when(
      age %in% c(2, 3) ~ "youth",
      age %in% c(4, 5, 6) ~ "middle_old",
      TRUE ~ NA_character_
    )
  )

summary(work2017_clean)

write.csv(work2017_clean, "work2017_clean.csv", row.names = FALSE, fileEncoding = "UTF-8")
