# Consumer Pattern Transition Analysis
# R script for missing-value handling and statistical testing.

# ============================================================
# 1. 데이터 불러오기
# ============================================================
####### 파일 가져오기 #######
getwd()

data_path <- file.path("data", "processed", "pk_shift_detail.csv")
data <- read.csv(data_path, encoding = "UTF-8")
colnames(data)

# ============================================================
# 2. 결측 제거 및 변수형 정리
# ============================================================

## 2) 필수 전처리
##   - 비교 불가능 행 제거
data <- data[
  !is.na(data$pk_shift) &
    !is.na(data$pk_share_t) &
    !is.na(data$pk_share_t1),
]

data$pk_shift <- as.integer(data$pk_shift)

# ============================================================
# 3. 피크 집중도 변화량 생성
# ============================================================
## 3) 피크 집중도 변화량
## -----------------------------
data$delta_pk_share <- abs(
  data$pk_share_t1 - data$pk_share_t
)

# ============================================================
# 4. 그룹별 요약 통계
# ============================================================
## -----------------------------
## 4) 요약 통계 (핵심)
## -----------------------------
summary_tbl <- aggregate(
  delta_pk_share ~ pk_shift,
  data = data,
  FUN = function(x) c(
    n = length(x),
    mean = mean(x),
    median = median(x),
    q25 = quantile(x, 0.25),
    q75 = quantile(x, 0.75)
  )
)

# ============================================================
# 5. Mann–Whitney U test
# ============================================================
## 5) Mann–Whitney U test
##   H1: pk_shift = 1 이 더 큼
## -----------------------------
g0 <- data$delta_pk_share[data$pk_shift == 0]
g1 <- data$delta_pk_share[data$pk_shift == 1]

mw_test <- wilcox.test(
  g0,
  g1,
  alternative = "less",
  exact = FALSE
)

p_value <- mw_test$p.value
W_stat  <- mw_test$statistic

# ============================================================
# 6. 결과 출력
# ============================================================
summary_tbl
p_value
W_stat
