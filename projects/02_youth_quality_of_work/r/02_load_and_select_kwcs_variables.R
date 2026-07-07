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




