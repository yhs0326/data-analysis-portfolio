# 1. 데이터 전처리 및 변환
getwd()
setwd("C:/포트폴리오")
library(data.table)
library(dplyr)
install.packages("arrow")
library(arrow)
install.packages("tidyverse")
library(tidyverse)
library(ggplot2)
install.packages("reshape2")
library(reshape2)
외국인 <- fread('외국인(블록) 일자별시간대별.csv',
             sep = ",",
             quote = "\"",
             encoding = "UTF-8",   
             fill = TRUE)


#csv파일이 안 열려 cp949로 바꾸고 다시 utf8로 교체 utf8로 안 읽힘 깨짐.
x <- read.csv("외국인(블록) 일자별시간대별.csv",
              fileEncoding = "CP949",
              sep = ",", quote="\"",
              fill = TRUE, comment.char = "",
              stringsAsFactors = FALSE,
              check.names = FALSE)

write.csv(x, "외국인_utf8.csv", row.names = FALSE, fileEncoding = "UTF-8")

getwd()
normalizePath("외국인_utf8.csv")
fwrite(x, "C:/포트폴리오/외국인_utf8.csv", bom = TRUE)

summary(x)

컬럼수정 <- c(
  "가맹점블록코드(BLCK_CD)" = "blck_cd",
  "외국인관광업종코드(SF_UPJONG_CD)" = "sf_upjong_cd",
  "기준년월(TS_YM)" = "ts_ym",
  "일별(TS_YMD)" = "ts_ymd",
  "시간대구간(TM_CD)" = "tm_cd",
  "카드이용금액계(AMT_CORR)" = "amt_corr",
  "카드이용건수(USECT_CORR)" = "usect_corr"
)
#열 이름 교체하기 
f_modify <- x %>%
  rename(blck_cd      = `가맹점블록코드(BLCK_CD)`,
         sf_upjong_cd = `외국인관광업종코드(SF_UPJONG_CD)`,
         ts_ym        = `기준년월(TS_YM)`,
         ts_ymd       = `일별(TS_YMD)`,
         tm_cd        = `시간대구간(TM_CD)`,
         amt_corr     = `카드이용금액계(AMT_CORR)`,
         usect_corr   = `카드이용건수(USECT_CORR)`)
str(f_modify)
#지침서 기준 시간 구간 나누기 
f_modify <- f_modify%>%
  mutate(
    tm_range = case_when(
      tm_cd == 'T1' ~ '00~06시미만',
      tm_cd == 'T2' ~ '06~11시미만',
      tm_cd == 'T3' ~ '11~14시미만',
      tm_cd == 'T4' ~ '14~17시미만',
      tm_cd == 'T5' ~ '17~21시미만',
      tm_cd == 'T6' ~ '21~24시미만',
      TRUE ~ NA_character_
    )
  )

f_modify$data <- as.Date(as.character(f_modify$ts_ymd), format = '%Y%m%d')

write_parquet(f_modify, 'C:/port/foreign_block_clean.parquet')

#내국인 데이터도 동일하게 
내국인 <- read.csv("내국인(블록) 일자별시간대별.csv",
                 fileEncoding = "CP949",
                 sep = ",", quote="\"",
                 fill = TRUE, comment.char = "",
                 stringsAsFactors = FALSE,
                 check.names = FALSE)

write.csv(내국인, "내국인_utf8.csv", row.names = FALSE, fileEncoding = "UTF-8")
#결측치 확인 
summary(내국인)
local_modify <- 내국인 %>%
  rename(blck_cd      = `가맹점블록코드(BLCK_CD)`,
         sb_upjong_cd = `내국인업종코드(SB_UPJONG_CD)`,
         ts_ym        = `기준년월(TS_YM)`,
         ts_ymd       = `일별(TS_YMD)`,
         tm      = `시간대(TM)`,
         amt_corr     = `카드이용금액계(AMT_CORR)`,
         usect_corr   = `카드이용건수(USECT_CORR)`,
         daw = `요일(DAW)`)
str(f_modify)
f_modify$data <- as.Date(as.character(f_modify$ts_ymd), format = '%Y%m%d')
colnames(내국인)

local_modify <- local_modify%>%
  mutate(
    tm_cd = case_when(
      tm >= 0  & tm < 6  ~ "T1",
      tm >= 6  & tm < 11 ~ "T2",
      tm >= 11 & tm < 14 ~ "T3",
      tm >= 14 & tm < 17 ~ "T4",
      tm >= 17 & tm < 21 ~ "T5",
      tm >= 21 & tm < 24 ~ "T6",
      TRUE ~ NA_character_
    ),
    tm_range = case_when(
      tm_cd == "T1" ~ "00~06 미만",
      tm_cd == "T2" ~ "06~11 미만",
      tm_cd == "T3" ~ "11~14 미만",
      tm_cd == "T4" ~ "14~17 미만",
      tm_cd == "T5" ~ "17~21 미만",
      tm_cd == "T6" ~ "21~24 미만",
      TRUE ~ NA_character_
    )
  )

local_modify$data <- as.Date(as.character(local_modify$ts_ymd), format = '%Y%m%d')
str(local_modify)
#python으로 내보낼 파일 
write_parquet(local_modify, 'C:/port/local_block_clean.parquet')



#내국인 업종 코드 
local_code <- read.csv("신한카드 내국인 63업종 코드.csv",
                fileEncoding = "CP949",
                sep = ",", quote="\"",
                fill = TRUE, comment.char = "",
                stringsAsFactors = FALSE,
                check.names = FALSE)

write.csv(local_code, "local_code_utf8.csv", row.names = FALSE, fileEncoding = "UTF-8")

local_code <- local_code %>%
  rename(sb_l_upjong_nm      = `대분류(SB_L_UPJONG_NM)`,
         sb_m_upjong_nm = `중분류(SB_M_UPJONG_NM)`,
         sb_upjong_nm        = `내국인업종분류(SB_UPJONG_NM)`,
         sb_upjong_cd       = `내국인업종코드(SB_UPJONG_CD)`
         )

write_parquet(local_code, 'C:/port/local_code_clean.parquet')

#외국인 업종 코드 
f_code <- read.csv("신한카드 외국인 56업종 코드.csv",
                       fileEncoding = "CP949",
                       sep = ",", quote="\"",
                       fill = TRUE, comment.char = "",
                       stringsAsFactors = FALSE,
                       check.names = FALSE)

write.csv(f_code, "f_code_utf8.csv", row.names = FALSE, fileEncoding = "UTF-8")

f_code <- f_code %>%
  rename(sf_l_upjong_cd      = `대분류코드(SF_L_UPJONG_CD)`,
         sf_l_upjong_nm = `대분류코드(SF_L_UPJONG_NM)`,
         sf_m_upjong_cd        = `중분류코드(SF_M_UPJONG_CD)`,
         sf_m_upjong_nm       = `중분류코드(SF_M_UPJONG_NM)`,
         sf_upjong_cd       = `외국인관광업종코드(SF_UPJONG_CD)`,
         sf_upjong_nm       = `외국인관광업종분류(SF_UPJONG_NM)`
  )

colnames(f_code)

write_parquet(f_code, 'C:/port/f_code_clean.parquet')


# 2. SQL 적재용 데이터 생성
###sql로 옮기기 
out_dir <- "C:/port_sql"
dir.create(out_dir, showWarnings = FALSE)

fwrite(as.data.table(f_modify),    file.path(out_dir, "foreign_block_clean.csv"))
fwrite(as.data.table(local_modify),file.path(out_dir, "local_block_clean.csv"))
fwrite(as.data.table(local_code),  file.path(out_dir, "local_code_clean.csv"))
fwrite(as.data.table(f_code),      file.path(out_dir, "foreign_code_clean.csv"))


# 3. Python 결과 데이터 로드
setwd("C:/port_r")

#######################===== 내국인 데이터 =====##################
centers        <- read.csv("centers.csv", stringsAsFactors = FALSE)
pre_c          <- read.csv("pre_c.csv", stringsAsFactors = FALSE)
post_c         <- read.csv("post_c.csv", stringsAsFactors = FALSE)

moved          <- read.csv("moved.csv", stringsAsFactors = FALSE)
trans_sector   <- read.csv("trans_sector.csv", row.names = 1)
avg_alter      <- read.csv("avg_alter.csv", row.names = 1)

chg_table      <- read.csv("chg_table.csv", stringsAsFactors = FALSE)
peak_flow      <- read.csv("peak_flow.csv", row.names = 1)
top5           <- read.csv("top5.csv", stringsAsFactors = FALSE)

###################### ===== 외국인 데이터 ===== #########################
foreign_centers      <- read.csv("foreign_centers.csv", stringsAsFactors = FALSE)
foreign_pre_c        <- read.csv("foreign_pre_c.csv", stringsAsFactors = FALSE)
foreign_post_c       <- read.csv("foreign_post_c.csv", stringsAsFactors = FALSE)

foreign_moved        <- read.csv("foreign_moved.csv", stringsAsFactors = FALSE)
f_trans_sector       <- read.csv("f_trans_sector.csv", row.names = 1)
foreign_avg_alter    <- read.csv("foreign_avg_alter.csv", row.names = 1)

foreign_chg_table    <- read.csv("foreign_chg_table.csv", stringsAsFactors = FALSE)
foreign_peak_flow    <- read.csv("foreign_peak_flow.csv", row.names = 1)
foreign_top5         <- read.csv("foreign_top5.csv", stringsAsFactors = FALSE)


# 4. 시각화 및 군집 분석 결과 해석
###########################군집중심 비교######
centers_long <- centers %>%
  pivot_longer(cols = starts_with('s_'), names_to = 'time', values_to = 'value')

ggplot(centers_long, aes(x = time, y = value, group = cluster, color = factor(cluster)))+
  geom_line(linewidth = 1.2)+
  geom_point()+
  labs(title = '내국인 소비 패턴의 군집별 시간대 구조',
       color = 'Cluster')+
  scale_x_discrete(
    labels = c(
      s_t1="심야", s_t2="오전", s_t3="점심",
      s_t4="오후", s_t5="퇴근", s_t6="야간",
      s_wknd="주말"
    ))+
  theme_minimal()


######군집이동 전이행렬#####
trans_melt <- melt(as.matrix(trans_sector))


ggplot(trans_melt, aes(x = Var2, y = Var1, fill = value))+
  geom_tile(color = 'white')+
  geom_text(aes(label = ifelse(value == 0, '', value)), size = 4)+
  scale_fill_gradient(low = 'white', high = 'steelblue')+
  labs(title = '내국인 소비 패턴 군집 간 이동 구조',
       x = 'Post cluster', y = 'Pre cluster')+
  scale_x_discrete(labels = function(x) sub("\\..*", "", x))  +
  scale_y_discrete(labels = function(x) sub("\\(.*", "", x))  +
  theme_minimal()+
  theme(
    legend.position = "none",
    axis.text.x = element_text(size = 13),
    axis.text.y = element_text(size = 13)
  )


######군집별 변화량#########
avg_alter_long <- avg_alter%>%
  rownames_to_column('cluster_name')%>%
  mutate(cluster_id = paste0('C', row_number()-1))%>%
  pivot_longer(cols = -c(cluster_name, cluster_id), names_to = 'feature', values_to = 'delta')

ggplot(avg_alter_long, aes(x = feature, y = delta, fill = cluster_id))+
  geom_col(position = 'dodge')+
  scale_x_discrete(labels = c(
    s_t1="심야", s_t2="오전", s_t3="점심",
    s_t4="오후", s_t5="퇴근", s_t6="야간",
    s_wknd="주말"
  )) +
  geom_hline(yintercept = 0, linewidth = 0.5) +
  labs(title = '내국인 소비 피크 시간대 이동 흐름', x = '시간대', y = '평균 변화',
       fill = 'Cluster')+
  theme_minimal()

##########피크 시간 이동 흐름##############
peak_melt <- melt(as.matrix(peak_flow))

ggplot(peak_melt, aes(x = Var2, y = Var1, fill = value))+
  geom_tile() +
  geom_text(aes(label = value))+
  scale_fill_gradient(low = 'white', high = 'darkred') +
  scale_x_discrete(labels = c(
    s_t1="심야", s_t2="오전", s_t3="점심",
    s_t4="오후", s_t5="퇴근", s_t6="야간",
    s_wknd="주말"
  )) +
  scale_y_discrete(labels = c(
    s_t1="심야", s_t2="오전", s_t3="점심",
    s_t4="오후", s_t5="퇴근", s_t6="야간",
    s_wknd="주말"
  )) +
  labs(title = '내국인 소비 피크 시간대 이동 흐름', x = '사후(post)피크 시간대',
       y = '사전(pre) 피크 시간대', fill = '업종 수')+
  theme_minimal()


######변화량 Top5 업종#####
ggplot(top5, aes(x = reorder(sb_m_upjong_nm, diff_score), y = diff_score))+
  geom_col(fill = 'tomato')+
  coord_flip()+
  scale_y_continuous(expand = expansion(mult = c(0, 0.1))) +
  geom_text(aes(label = sprintf("%.2f", diff_score)), hjust = -0.1, size = 3) +
  labs(title = '소비 패턴 변화가 큰 내국인 업종 상위 5개', x = '업종', 
       y = '변화 점수')+
  theme_minimal()


fviz_cluster(centers_long, data = centers,
             geom = 'point', pallette = 'Set2',
             ellipse.type = 'convex', main = 'K-means군집 경계 시각화')
#####################################################
#############계층적 군집분석###################
#내국인 
hier_pre <- read.csv('scales_pre.csv', stringsAsFactors = FALSE)
hier_post <- read.csv('scales_post.csv', stringsAsFactors = FALSE)
##거리 구할 행렬 구하기 (2017~2019)
rownames(hier_pre) <- hier_pre$sb_m_upjong_nm
hier_pre_mat <- as.matrix(hier_pre[,!(names(hier_pre) %in% 'sb_m_upjong_nm')])
###거리,계층적 군집 
d <- dist(hier_pre_mat, method = 'euclidean')
hc <- hclust(d, method = 'ward.D2')

plot(hc, cex = 0.9, main = '내국인 업종별 소비 패턴 덴드로그램(2017~2019)', xlab = '', sub = '')
rect.hclust(hc, k = 4, border = 2:7)
#실제 군집 구성 
pre_k4 <- cutree(hc, h = 4)
split(names(pre_k4), pre_k4)
table(pre_k4)

#2020~2021
rownames(hier_post) <- hier_post$sb_m_upjong_nm
hier_post_mat <- as.matrix(hier_post[,!(names(hier_post) %in% 'sb_m_upjong_nm')])
###거리,계층적 군집 
d1 <- dist(hier_post_mat, method = 'euclidean')
hc1 <- hclust(d1, method = 'ward.D2')

plot(hc1, cex = 0.9, main = '내국인 업종별 소비 패턴 덴드로그램(2020~2021)', xlab = '', sub = '')
abline(h = 15, col = 'red', lty = 2)
rect.hclust(hc1, k = 4, border = 2:7)
#실제 군집구성 
post_k4 <- cutree(hc1, h = 7)
split(names(post_k4), post_k4)
table(post_k4)


###########################군집중심 비교#########
##############외국인#############
foreign_centers_long <- foreign_centers %>%
  pivot_longer(cols = starts_with('s_'), names_to = 'time', values_to = 'value')

ggplot(foreign_centers_long, aes(x = time, y = value, group = cluster, color = factor(cluster)))+
  geom_line(linewidth = 1.2)+
  geom_point()+
  labs(title = '외국인 소비 패턴의 군집별 시간대 구조',
       color = 'Cluster')+
  scale_x_discrete(
    labels = c(
      s_t1="심야", s_t2="오전", s_t3="점심",
      s_t4="오후", s_t5="퇴근", s_t6="야간",
      s_wknd="주말"
    ))+
  theme_minimal()


######군집이동 전이행렬#####
f_trans_melt <- melt(as.matrix(f_trans_sector))


ggplot(f_trans_melt, aes(x = Var2, y = Var1, fill = value))+
  geom_tile(color = 'white')+
  geom_text(aes(label = value), size = 4)+
  scale_fill_gradient(low = 'white', high = 'steelblue')+
  labs(title = '외국인 소비 패턴 군집 간 이동 구조',
       x = 'Post cluster', y = 'Pre cluster')+
  scale_x_discrete(labels = function(x) sub("\\..*", "", x))  +
  scale_y_discrete(labels = function(x) sub("\\(.*", "", x))  +
  theme_minimal()


######군집별 변화량#########
foreign_avg_alter_long <- foreign_avg_alter%>%
  rownames_to_column('cluster_name')%>%
  mutate(cluster_id = paste0('C', row_number()-1))%>%
  pivot_longer(cols = -c(cluster_name, cluster_id), names_to = 'feature', values_to = 'delta')

ggplot(foreign_avg_alter_long, aes(x = feature, y = delta, fill = cluster_id))+
  geom_col(position = 'dodge')+
  scale_x_discrete(labels = c(
    s_t1="심야", s_t2="오전", s_t3="점심",
    s_t4="오후", s_t5="퇴근", s_t6="야간",
    s_wknd="주말"
  )) +
  geom_hline(yintercept = 0, linewidth = 0.5) +
  labs(title = '외국인 소비 피크 시간대 이동 흐름', x = '시간대', y = '평균 변화',
       fill = 'Cluster')+
  theme_minimal()

##########피크 시간 이동 흐름##############
foreign_peak_melt <- melt(as.matrix(foreign_peak_flow))

ggplot(foreign_peak_melt, aes(x = Var2, y = Var1, fill = value))+
  geom_tile() +
  geom_text(aes(label = value))+
  scale_fill_gradient(low = 'white', high = 'darkred') +
  scale_x_discrete(labels = c(
    s_t1="심야", s_t2="오전", s_t3="점심",
    s_t4="오후", s_t5="퇴근", s_t6="야간",
    s_wknd="주말"
  )) +
  scale_y_discrete(labels = c(
    s_t1="심야", s_t2="오전", s_t3="점심",
    s_t4="오후", s_t5="퇴근", s_t6="야간",
    s_wknd="주말"
  )) +
  labs(title = '외국인 소비 피크 시간대 이동 흐름', x = '사후(post)피크 시간대',
       y = '사전(pre) 피크 시간대', fill = '업종 수')+
  theme_minimal()


######변화량 Top5 업종#####
ggplot(foreign_top5, aes(x = reorder(sf_m_upjong_nm, diff_score), y = diff_score))+
  geom_col(fill = 'tomato')+
  coord_flip()+
  scale_y_continuous(expand = expansion(mult = c(0, 0.1))) +
  geom_text(aes(label = sprintf("%.2f", diff_score)), hjust = -0.1, size = 3) +
  labs(title = '소비 패턴 변화가 큰 외국인 업종 상위 5개', x = '업종', 
       y = '변화 점수')+
  theme_minimal()

#####################################################
#############계층적 군집분석###################
#외국인 
foreign_hier_pre <- read.csv('scales_foreign_pre.csv', stringsAsFactors = FALSE)
foreign_hier_post <- read.csv('scales_foreign_post.csv', stringsAsFactors = FALSE)
##거리 구할 행렬 구하기 (2017~2019)
rownames(foreign_hier_pre) <- foreign_hier_pre$sf_m_upjong_nm
foreign_hier_pre_mat <- as.matrix(foreign_hier_pre[,!(names(foreign_hier_pre) %in% 'sf_m_upjong_nm')])
###거리,계층적 군집 
fd <- dist(foreign_hier_pre_mat, method = 'euclidean')
fhc <- hclust(fd, method = 'ward.D2')

plot(fhc, cex = 0.9, main = '외국인 업종별 소비 패턴 덴드로그램(2017~2019)', xlab = '', sub = '')
rect.hclust(fhc, k = 6, border = 2:7)
#실제 군집 구성 
foreign_pre_k4 <- cutree(fhc, h = 4)
split(names(foreign_pre_k4), foreign_pre_k4)
table(foreign_pre_k4)

#2020~2021
rownames(foreign_hier_post) <- foreign_hier_post$sf_m_upjong_nm
foreign_hier_post_mat <- as.matrix(foreign_hier_post[,!(names(foreign_hier_post) %in% 'sf_m_upjong_nm')])
###거리,계층적 군집 
fd1 <- dist(foreign_hier_post_mat, method = 'euclidean')
fhc1 <- hclust(fd1, method = 'ward.D2')

plot(fhc1, cex = 0.9, main = '외국인 업종별 소비 패턴 덴드로그램(2020~2021)', xlab = '', sub = '')
abline(h = 15, col = 'red', lty = 2)
rect.hclust(fhc1, k = 4, border = 2:7)
#실제 군집구성 
foreign_post_k4 <- cutree(fhc1, h = 6)
split(names(foreign_post_k4), foreign_post_k4)
table(foreign_post_k4)
