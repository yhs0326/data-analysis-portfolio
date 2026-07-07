getwd()
# ======================
# 프로젝트 기준 경로 설정
# ======================
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("--file=", args, value = TRUE)
if (length(file_arg) > 0) {
  script_path <- normalizePath(sub("--file=", "", file_arg), mustWork = FALSE)
  project_dir <- normalizePath(file.path(dirname(script_path), ".."), mustWork = FALSE)
} else {
  wd <- normalizePath(getwd(), mustWork = FALSE)
  if (basename(wd) %in% c("r", "python", "sql")) {
    project_dir <- normalizePath(file.path(wd, ".."), mustWork = FALSE)
  } else {
    project_dir <- wd
  }
}
data_dir <- file.path(project_dir, "data")
output_dir <- file.path(project_dir, "outputs")
figure_dir <- file.path(output_dir, "figures")
table_dir <- file.path(output_dir, "tables")
dir.create(data_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(figure_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(table_dir, showWarnings = FALSE, recursive = TRUE)
setwd(data_dir)
labor <- read.csv('고용보조지표_청년.csv', header = TRUE)
unemploy <- read.csv("성_연령별_실업률.csv", header = TRUE)
dis_worker <- read.csv("성별_구직단념자.csv", header = TRUE)

plot(unemploy$계.1, type = "l",
     main = "청년 실업률 추이")

plot(labor$고용보조지표3..., type = "l",
     main = "청년 체감실업률 추이")

plot(dis_worker$계, type = "l",
     main = "청년 구직단념자 추이")

summary(unemploy$계.1)

# 1행 제거
unemploy2 <- unemploy[-1, ]

# 문자형을 숫자형으로 변환
unemploy2$계.1 <- as.numeric(unemploy2$계.1)

#시점 날짜형으로 전환 
unemploy2$시점 <- as.Date(paste0(unemploy2$시점, "-01"),
                        format = "%Y.%m-%d")
# 청년 실업률 그래프
plot(unemploy2$시점, unemploy2$계.1,
     type = "l",
     main = "청년 실업률 추이",
     xlab = "시점",
     ylab = "실업률(%)")


# 체감실업률
labor$시점 <- as.Date(paste0(labor$시점, "-01"),
                    format = "%Y.%m-%d")

labor <- labor[order(labor$시점), ]

plot(labor$시점, labor$고용보조지표3...,
     type = "l",
     main = "청년 체감실업률 추이",
     xlab = "시점",
     ylab = "고용보조지표3(%)")


# 구직단념자
dis_worker$시점 <- as.Date(paste0(dis_worker$시점, "-01"),
                         format = "%Y.%m-%d")

dis_worker <- dis_worker[order(dis_worker$시점), ]

plot(dis_worker$시점, dis_worker$계,
     type = "l",
     main = "청년 구직단념자 추이",
     xlab = "시점",
     ylab = "구직단념자(천명)")

work_en <- read.csv('근로환경조사_2023.csv', header = TRUE, sep = '\t')

#2017근로환경조사 데이터 열기 
install.packages('haven')
library(haven)
work2017 <- read_sav("근로환경조사2017.sav")
colnames(work2017)

#2023근로환경조사 데이터 열기 
library(readr)

# 기존 객체 삭제
rm(list = ls())

# 작업 폴더 설정
setwd(normalizePath(getwd(), mustWork = FALSE))


library(readr)

work2023 <- read_csv(
  "근로환경조사_2023_utf8.csv.csv",
  na = c("", "NA")
)

dim(work2023)
names(work2023)[1:20]

#필요한 열 추출 
# 2017
library(dplyr)
work2017_sel <- work2017 %>%
  select(
    TAGE, TSEX,
    Q06, KQ08, EF11,
    Q22_1, Q23_1,
    Q37,
    Q49_8, Q49_10, Q49_13,
    Q69, Q70_7, Q70_8
  ) %>%
  rename(
    age = TAGE,
    gender = TSEX,
    emp_type = Q06,
    full_part = KQ08,
    income = EF11,
    work_hours = Q22_1,
    preferred_hours = Q23_1,
    work_life_balance = Q37,
    achievement = Q49_8,
    work_meaning = Q49_10,
    stress = Q49_13,
    satisfaction = Q69,
    job_loss_risk = Q70_7,
    reemployment_possibility = Q70_8
  ) %>%
  mutate(year = 2017)

# 2023
work2023_sel <- work2023 %>%
  select(
    age, gender,
    emp_stat, emp_fptime, earning1_r,
    wtime_r, ptime_r,
    wbalance,
    wsituation8, wsituation10, wsituation12,
    satisfaction, wstat6, wstat7
  ) %>%
  rename(
    emp_type = emp_stat,
    full_part = emp_fptime,
    income = earning1_r,
    work_hours = wtime_r,
    preferred_hours = ptime_r,
    work_life_balance = wbalance,
    achievement = wsituation8,
    work_meaning = wsituation10,
    stress = wsituation12,
    job_loss_risk = wstat6,
    reemployment_possibility = wstat7
  ) %>%
  mutate(year = 2023)

write.csv(work2017_sel, "work2017_sel.csv", row.names = FALSE, fileEncoding = "UTF-8")
write.csv(work2023_sel, "work2023_sel.csv", row.names = FALSE, fileEncoding = "UTF-8")




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
setwd(normalizePath(getwd(), mustWork = FALSE))
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


#2017년 데이터
getwd()
setwd(normalizePath(getwd(), mustWork = FALSE))
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
