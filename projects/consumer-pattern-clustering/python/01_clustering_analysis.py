##############################################################################
# 내국인 데이터
##############################################################################

import os
import pandas as pd
import numpy as np

from sklearn.preprocessing import StandardScaler
from sklearn.cluster import KMeans
from sklearn.metrics import silhouette_score

# NOTE: GitHub 사용자는 아래 로컬 경로를 자신의 환경에 맞게 수정해야 합니다.
os.chdir(r'C:\port_sql')

######## 자료 불러오기 ########
pre = pd.read_csv('pre_feat.csv', encoding='utf-8-sig')
post = pd.read_csv('post_feat.csv', encoding='utf-8-sig')

id_col = 'sb_m_upjong_nm'
feat_cols = ['s_t1', 's_t2', 's_t3', 's_t4', 's_t5', 's_t6', 's_wknd']

###### 공통 업종 맞추기 ######
common = sorted(set(pre[id_col]).intersection(set(post[id_col])))
pre = pre[pre[id_col].isin(common)].sort_values(id_col).reset_index(drop=True)
post = post[post[id_col].isin(common)].sort_values(id_col).reset_index(drop=True)

##### 표쥰화 ########
scale_pre = pre[feat_cols].to_numpy()
scale_post = post[feat_cols].to_numpy()

scaler = StandardScaler()
scales_pre = scaler.fit_transform(scale_pre)
scales_post = scaler.transform(scale_post)

######## 실루엣으로 최적의 클러스터 갯수 찾기 #######
n = scale_pre.shape[0]
k_min, k_max = 2, min(10, n - 1)

best_k, best_sil = None, -1
rows = []

for k in range(k_min, k_max + 1):
    km_tmp = KMeans(n_clusters=k, n_init='auto', random_state=42)
    lap_tmp = km_tmp.fit_predict(scales_pre)
    sil = silhouette_score(scales_pre, lap_tmp)
    rows.append((k, sil))
    if sil > best_sil:
        best_k, best_sil = k, sil

k_scores = pd.DataFrame(rows, columns=['k', 'silhouette'])

# print(k_scores)
# 실루엣기법으로는 9개가 최적이지만 9개로 쪼갤시 군집의 각 갯수가 3개 정도로 적어져
# 해석이 잘게 쪼개질가능성이 있어서 보류. 여기서 객단가를 빼고 다시 시도했더니 k=4도 적절함.

##### k = 4로 고정하고 군집분석 실행
k = 4
km = KMeans(n_clusters=k, n_init='auto', random_state=42)
pre_lab = km.fit_predict(scales_pre)
post_lab = km.predict(scales_post)

pre_c = pre.copy()
post_c = post.copy()

pre_c['cluster'] = pre_lab
post_c['cluster'] = post_lab

centers_raw = scaler.inverse_transform(km.cluster_centers_)
centers = pd.DataFrame(centers_raw, columns=feat_cols)
centers.insert(0, 'cluster', range(k))

print(pre_c['cluster'].value_counts().sort_index())

#### 군집별 업종 리스트 ######
cluster_list = pre_c[[id_col, 'cluster']].sort_values(['cluster', id_col])

for i in sorted(pre_c['cluster'].unique()):
    names = cluster_list.loc[cluster_list['cluster'] == i, id_col].tolist()
    print(f'\n[cluster{i}] 업종 수 = {len(names)}')
    print(','.join(names))

cluster_list_post = post_c[[id_col, 'cluster']].sort_values(['cluster', id_col])

for i in sorted(post_c['cluster'].unique()):
    names = cluster_list_post.loc[cluster_list['cluster'] == i, id_col].tolist()
    print(f'\n[cluster{i}] 업종 수 = {len(names)}')
    print(','.join(names))

###### 군집 라벨링 하기(시간대, 주말) ######
time_cols = [f's_t{i}' for i in range(1, 7)]
centers['peak_col'] = centers[time_cols].idxmax(axis=1)
peak_map = {
    's_t1': '심야형(0~6시)',
    's_t2': '오전형(6~11시)',
    's_t3': '점심형(11~14시)',
    's_t4': '오후형(14~17시)',
    's_t5': '퇴근형(17~21시)',
    's_t6': '야간형(21~24시)'
}
centers['time_label'] = centers['peak_col'].map(peak_map)
centers['wknd_label'] = np.where(centers['s_wknd'] >= 0.50, '주말강함', '주말약함')

centers['label'] = centers['time_label'] + '+' + centers['wknd_label']

cluster_name = dict(zip(centers['cluster'], centers['label']))
pre_c['cluster_name'] = pre_c['cluster'].map(cluster_name)
post_c['cluster_name'] = post_c['cluster'].map(cluster_name)

centers_view = centers[['cluster', 'time_label', 'wknd_label', 'label', 's_wknd']]
centers_view

##### 업종별 군집 이동 ex. 점심형 → 퇴근형 ######
move = pre_c[[id_col, 'cluster_name']].merge(
    post_c[[id_col, 'cluster_name']],
    on=id_col,
    suffixes=('_pre', '_post')
)

## 변한 업종 만
moved = move[move['cluster_name_pre'] != move['cluster_name_post']]
moved

### 전이행렬
# (점심형, 점심형) = 8 → 점심형으로 유지된 업종 8개
# (점심형, 퇴근형) = 2 → 점심형에서 퇴근형으로 이동한 업종 2개
trans_sector = pd.crosstab(move['cluster_name_pre'], move['cluster_name_post'])
trans_sector

###### 군집별 평균 변화
# 군집별 점심은 약해졌고, 퇴근은 강해졌지만, 아직 s_t3가 1등이라 라벨은 점심형 그대로
pre_g = pre_c.groupby('cluster_name')[feat_cols].mean()
post_g = post_c.groupby('cluster_name')[feat_cols].mean()
avg_alter = (post_g - pre_g).round(3)
avg_alter

#### 업종별 pre, post 붙이기
chg = pre_c[[id_col] + feat_cols].merge(
    post_c[[id_col] + feat_cols],
    on=id_col,
    suffixes=('_pre', '_post')
)

#### 전후차이 변화량 탐색
for d in feat_cols:
    chg[d + '_diff'] = chg[d + '_post'] - chg[d + '_pre']

## 피크시간대 이동
chg['peak_pre'] = chg[[d + '_pre' for d in time_cols]].idxmax(axis=1)
chg['peak_post'] = chg[[d + '_post' for d in time_cols]].idxmax(axis=1)

### 이동 확인 테이블
chg_table = chg[[id_col, 'peak_pre', 'peak_post'] + [d + '_diff' for d in feat_cols]]
chg_table

##### 피크 이동 방향 #######
pre_base = chg_table['peak_pre'].str.replace('_pre', '', regex=False)
post_base = chg_table['peak_post'].str.replace('_post', '', regex=False)
peak_flow = pd.crosstab(pre_base, post_base)

#### 변화량 큰 업종 5개 뽑기 (점수만들기)
diff_cols = [f's_t{i}_diff' for i in range(1, 7)]
chg_table['diff_score'] = chg_table[diff_cols].abs().sum(axis=1)

top5 = chg_table.sort_values('diff_score', ascending=False)[[id_col, 'diff_score'] + diff_cols].head(5)


##############################################################################
# 외국인 데이터
##############################################################################

# 데이터 불러오기
foreign_pre = pd.read_csv('f_pre_feat.csv', encoding='utf-8-sig')
foreign_post = pd.read_csv('f_post_feat.csv', encoding='utf-8-sig')

###### 공통 업종 맞추기 ######
id_col = 'sf_m_upjong_nm'
feat_cols = ['s_t1', 's_t2', 's_t3', 's_t4', 's_t5', 's_t6', 's_wknd']

common = sorted(set(foreign_pre[id_col]).intersection(set(foreign_post[id_col])))
foreign_pre = foreign_pre[foreign_pre[id_col].isin(common)].sort_values(id_col).reset_index(drop=True)
foreign_post = foreign_post[foreign_post[id_col].isin(common)].sort_values(id_col).reset_index(drop=True)

##### 표쥰화 ########
scale_foreign_pre = foreign_pre[feat_cols].to_numpy()
scale_foreign_post = foreign_post[feat_cols].to_numpy()

scaler = StandardScaler()
scales_foreign_pre = scaler.fit_transform(scale_foreign_pre)
scales_foreign_post = scaler.transform(scale_foreign_post)

######## 실루엣으로 최적의 클러스터 갯수 찾기 #######
n = scale_pre.shape[0]
k_min, k_max = 2, min(10, n - 1)

best_k, best_sil = None, -1
rows = []

for k in range(k_min, k_max + 1):
    km_tmp = KMeans(n_clusters=k, n_init='auto', random_state=42)
    lap_tmp = km_tmp.fit_predict(scales_foreign_pre)
    sil = silhouette_score(scales_foreign_pre, lap_tmp)
    rows.append((k, sil))
    if sil > best_sil:
        best_k, best_sil = k, sil

foreign_k_scores = pd.DataFrame(rows, columns=['k', 'silhouette'])

##### k = 5로 고정하고 군집분석 실행
k = 5
f_km = KMeans(n_clusters=k, n_init='auto', random_state=42)
foreign_pre_lab = f_km.fit_predict(scales_foreign_pre)
foreign_post_lab = f_km.predict(scales_foreign_post)

foreign_pre_c = foreign_pre.copy()
foreign_post_c = foreign_post.copy()

foreign_pre_c['cluster'] = foreign_pre_lab
foreign_post_c['cluster'] = foreign_post_lab

foreign_centers_raw = scaler.inverse_transform(f_km.cluster_centers_)
foreign_centers = pd.DataFrame(foreign_centers_raw, columns=feat_cols)
foreign_centers.insert(0, 'cluster', range(k))

print(foreign_pre_c['cluster'].value_counts().sort_index())

#### 군집별 업종 리스트 ######
foreign_cluster_list = foreign_pre_c[[id_col, 'cluster']].sort_values(['cluster', id_col])

for i in sorted(foreign_pre_c['cluster'].unique()):
    names = foreign_cluster_list.loc[foreign_cluster_list['cluster'] == i, id_col].tolist()
    print(f'\n[cluster{i}] 업종 수 = {len(names)}')
    print(','.join(names))

###### 군집 라벨링 하기(시간대, 주말) ######
time_cols = [f's_t{i}' for i in range(1, 7)]
foreign_centers['peak_col'] = foreign_centers[time_cols].idxmax(axis=1)
peak_map = {
    's_t1': '심야형(0~6시)',
    's_t2': '오전형(6~11시)',
    's_t3': '점심형(11~14시)',
    's_t4': '오후형(14~17시)',
    's_t5': '퇴근형(17~21시)',
    's_t6': '야간형(21~24시)'
}
foreign_centers['time_label'] = foreign_centers['peak_col'].map(peak_map)
foreign_centers['wknd_label'] = np.where(foreign_centers['s_wknd'] >= 0.50, '주말강함', '주말약함')

foreign_centers['label'] = foreign_centers['time_label'] + '+' + foreign_centers['wknd_label']

cluster_name = dict(zip(foreign_centers['cluster'], foreign_centers['label']))
foreign_pre_c['cluster_name'] = foreign_pre_c['cluster'].map(cluster_name)
foreign_post_c['cluster_name'] = foreign_post_c['cluster'].map(cluster_name)

foreign_centers_view = foreign_centers[['cluster', 'time_label', 'wknd_label', 'label', 's_wknd']]
foreign_centers_view

##### 업종별 군집 이동 ex. 점심형 → 퇴근형 ######
f_move = foreign_pre_c[[id_col, 'cluster_name']].merge(
    foreign_post_c[[id_col, 'cluster_name']],
    on=id_col,
    suffixes=('_pre', '_post')
)

## 변한 업종 만
foreign_moved = f_move[f_move['cluster_name_pre'] != f_move['cluster_name_post']]

### 전이행렬
# (점심형, 점심형) = 8 → 점심형으로 유지된 업종 8개
# (점심형, 퇴근형) = 2 → 점심형에서 퇴근형으로 이동한 업종 2개
f_trans_sector = pd.crosstab(f_move['cluster_name_pre'], f_move['cluster_name_post'])
f_trans_sector

###### 군집별 평균 변화
f_pre_g = foreign_pre_c.groupby('cluster_name')[feat_cols].mean()
f_post_g = foreign_post_c.groupby('cluster_name')[feat_cols].mean()
foreign_avg_alter = (f_post_g - f_pre_g).round(3)
foreign_avg_alter

#### 업종별 pre, post 붙이기
f_chg = foreign_pre_c[[id_col] + feat_cols].merge(
    foreign_post_c[[id_col] + feat_cols],
    on=id_col,
    suffixes=('_pre', '_post')
)

#### 전후차이 변화량 탐색
for d in feat_cols:
    f_chg[d + '_diff'] = f_chg[d + '_post'] - f_chg[d + '_pre']

## 피크시간대 이동
f_chg['peak_pre'] = f_chg[[d + '_pre' for d in time_cols]].idxmax(axis=1)
f_chg['peak_post'] = f_chg[[d + '_post' for d in time_cols]].idxmax(axis=1)

### 이동 확인 테이블
foreign_chg_table = f_chg[[id_col, 'peak_pre', 'peak_post'] + [d + '_diff' for d in feat_cols]]

##### 피크 이동 방향 #######
foreign_pre_base = foreign_chg_table['peak_pre'].str.replace('_pre', '', regex=False)
foreign_post_base = foreign_chg_table['peak_post'].str.replace('_post', '', regex=False)
foreign_peak_flow = pd.crosstab(foreign_pre_base, foreign_post_base)

#### 변화량 큰 업종 5개 뽑기 (점수만들기)
diff_cols = [f's_t{i}_diff' for i in range(1, 7)]
foreign_chg_table['diff_score'] = foreign_chg_table[diff_cols].abs().sum(axis=1)

foreign_top5 = foreign_chg_table.sort_values('diff_score', ascending=False)[[id_col, 'diff_score'] + diff_cols].head(5)

###### 군집분석 데이터 csv파일로 내보내기 r로 이동 (시각화를 위해)
out_dir = r'C:\port_r'
os.makedirs(r'C:\port_r', exist_ok=True)


def save_df(df, name, keep_index=False):
    df.to_csv(
        os.path.join(out_dir, f"{name}.csv"),
        index=keep_index,
        encoding='utf-8-sig'
    )


# ===== 내국인 =====
save_df(centers, 'centers')
save_df(pre_c, 'pre_c')
save_df(post_c, 'post_c')

save_df(moved, 'moved')
save_df(trans_sector, 'trans_sector', True)
save_df(avg_alter, 'avg_alter', True)

save_df(chg_table, 'chg_table')
save_df(peak_flow, 'peak_flow', True)
save_df(top5, 'top5')

# ===== 외국인 =====
save_df(foreign_centers, 'foreign_centers')
save_df(foreign_pre_c, 'foreign_pre_c')
save_df(foreign_post_c, 'foreign_post_c')

save_df(foreign_moved, 'foreign_moved')
save_df(f_trans_sector, 'f_trans_sector', True)
save_df(foreign_avg_alter, 'foreign_avg_alter', True)

save_df(foreign_chg_table, 'foreign_chg_table')
save_df(foreign_peak_flow, 'foreign_peak_flow', True)
save_df(foreign_top5, 'foreign_top5')

################ 계층적 분석 파일 ###############
id_col = 'sb_m_upjong_nm'
scales_pre_df = pd.DataFrame(scales_pre, columns=feat_cols)
scales_pre_df.insert(0, id_col, pre[id_col].values)
save_df(scales_pre_df, 'scales_pre')

scales_post_df = pd.DataFrame(scales_post, columns=feat_cols)
scales_post_df.insert(0, id_col, post[id_col].values)
save_df(scales_post_df, 'scales_post')

f_id_col = 'sf_m_upjong_nm'
scales_foreign_pre_df = pd.DataFrame(scales_foreign_pre, columns=feat_cols)
scales_foreign_pre_df.insert(0, f_id_col, foreign_pre[f_id_col].values)
save_df(scales_foreign_pre_df, 'scales_foreign_pre')

scales_foreign_post_df = pd.DataFrame(scales_foreign_post, columns=feat_cols)
scales_foreign_post_df.insert(0, f_id_col, foreign_post[f_id_col].values)
save_df(scales_foreign_post_df, 'scales_foreign_post')
