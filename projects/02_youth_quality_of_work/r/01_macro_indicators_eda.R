getwd()
setwd('C:/kossda 공모전')
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

