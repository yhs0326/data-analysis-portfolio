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

getwd()
setwd(normalizePath(getwd(), mustWork = FALSE))
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
