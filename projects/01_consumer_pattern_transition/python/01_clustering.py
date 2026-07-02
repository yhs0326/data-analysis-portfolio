# -*- coding: utf-8 -*-
"""
Created on Fri Feb  6 20:21:51 2026

@author: LG


- 원본 코드의 내용과 실행 순서는 변경하지 않았습니다.
- 가독성을 위해 섹션 주석만 추가했습니다.
- 현재 경로는 프로젝트 폴더 기준 상대경로로 정리했습니다.
- GitHub 업로드 시에는 README에서 실행 환경과 파일 위치를 함께 설명하는 방식을 권장합니다.
"""

# ============================================================
# 0. 라이브러리 불러오기
# ============================================================
from pathlib import Path

import pandas as pd
import numpy as np

from sklearn.linear_model import LogisticRegression
from sklearn.metrics import (
    roc_auc_score, average_precision_score,
    precision_recall_curve, classification_report,
    confusion_matrix
)
# ============================================================
# 0-1. 프로젝트 기준 경로 설정
# ============================================================
PROJECT_DIR = Path(__file__).resolve().parents[1]

DATA_RAW_DIR = PROJECT_DIR / "data" / "raw"
DATA_PROCESSED_DIR = PROJECT_DIR / "data" / "processed"
DATA_EXTERNAL_DIR = PROJECT_DIR / "data" / "external"

FIGURE_DIR = PROJECT_DIR / "outputs" / "figures"
TABLE_DIR = PROJECT_DIR / "outputs" / "tables"

FIGURE_DIR.mkdir(parents=True, exist_ok=True)
TABLE_DIR.mkdir(parents=True, exist_ok=True)


# ============================================================
# 3. 군집분석용 데이터 로드 및 군집 생성
# ============================================================
######군집분석##########
from sklearn.preprocessing import StandardScaler
from sklearn.cluster import MiniBatchKMeans
from sklearn.metrics import silhouette_score

# ==========================
# 0) 파일 업로드 
# ==========================
path_struct = DATA_PROCESSED_DIR / "card_ts_q_struct.csv"
detail = pd.read_csv(path_struct, encoding="utf-8")

ts_cols = ["ts_0_6","ts_6_11","ts_11_14","ts_14_17","ts_17_21","ts_21_24"]
X_cols = ts_cols + ["share_wkend"]

join_keys = ["상권_코드", "서비스_업종_코드", "yq"]

# 컬럼 존재 체크
need_cols = join_keys + X_cols
missing_detail = [c for c in need_cols if c not in detail.columns]
if missing_detail:
    raise ValueError(f"card_ts_q_struct.csv missing columns: {missing_detail}")

# 파생변수명 충돌 방지
derived_cols = ["cl_cluster_id","cl_cluster_shift","cl_proba_lr","cl_proba_lr2"]
conflict = [c for c in derived_cols if c in train.columns or c in test.columns]
if conflict:
    raise ValueError(f"Derived column name conflict: {conflict}")

detail = detail.dropna(subset=X_cols + ["yq"]).copy()

#######1) 군집생성############
scaler_cl = StandardScaler()
X_detail = scaler_cl.fit_transform(detail[X_cols])

rng = np.random.default_rng(42)

sample_idx = rng.choice(len(detail), size=min(30000, len(detail)), replace=False)
X_s = X_detail[sample_idx]

k_grid = range(3, 9)
sil_scores = {}

for k in k_grid:
    km = MiniBatchKMeans(n_clusters=k, random_state=42, batch_size=4096, n_init=20)
    km.fit(X_s)  
    sil_scores[k] = silhouette_score(X_s, km.predict(X_s))
best_k = max(sil_scores, key=sil_scores.get)
print("silhouette scores:", sil_scores, "best_k:", best_k)


kmeans_cl = MiniBatchKMeans(
    n_clusters=best_k,
    random_state=42,
    batch_size=4096,
    n_init=30
)
detail["cl_cluster_id"] = kmeans_cl.fit_predict(X_detail).astype(int)

# ==========================
# 2) 군집 전이 변수
# ==========================
detail["year"] = detail["yq"] // 10
detail["quarter"] = detail["yq"] % 10
detail["q_index"] = detail["year"]*4 + (detail["quarter"]-1)


detail = detail.sort_values(["상권_코드","서비스_업종_코드","q_index"]).copy()
detail["_prev_cl"] = detail.groupby(
    ["상권_코드","서비스_업종_코드"]
)["cl_cluster_id"].shift(1)

detail["cl_cluster_shift"] = (
    (detail["_prev_cl"].notna()) &
    (detail["cl_cluster_id"] != detail["_prev_cl"])
).astype(int)

detail.drop(columns="_prev_cl", inplace=True)

# ==========================
# 3) train / test JOIN
# ==========================
detail["yq"] = detail["yq"].astype(int)
train["yq"] = train["yq"].astype(int)
test["yq"] = test["yq"].astype(int)

detail_small = detail[join_keys + ["cl_cluster_id","cl_cluster_shift"]]

train2 = train.merge(detail_small, on=join_keys, how="left", validate="m:1")
test2  = test.merge(detail_small,  on=join_keys, how="left", validate="m:1")


train2["cl_cluster_shift"] = train2["cl_cluster_shift"].fillna(0).astype(int)
test2["cl_cluster_shift"]  = test2["cl_cluster_shift"].fillna(0).astype(int)
train2["cl_cluster_id"]    = train2["cl_cluster_id"].fillna(-1).astype(int)
test2["cl_cluster_id"]     = test2["cl_cluster_id"].fillna(-1).astype(int)

print("train2 -1 rate:", train2["cl_cluster_id"].eq(-1).mean())
print("test2  -1 rate:", test2["cl_cluster_id"].eq(-1).mean())

# ==========================
# 4) 기존 로지스틱 확률 보존
# ==========================
#test2["cl_proba_lr"] = proba_test

# ==========================
# 5) cluster_shift 추가 로지스틱
# ==========================
X_cols2 = X_cols + ["cl_cluster_shift"]

clf2 = LogisticRegression(max_iter=2000, class_weight="balanced", n_jobs=-1)
clf2.fit(train2[X_cols2], train2["pk_shift"])

proba_test2 = clf2.predict_proba(test2[X_cols2])[:, 1]
test2["cl_proba_lr2"] = proba_test2

roc2 = roc_auc_score(y_test, proba_test2)
prauc2 = average_precision_score(y_test, proba_test2)

print(f"[LR + cluster_shift] ROC-AUC: {roc2:.4f}")
print(f"[LR + cluster_shift] PR-AUC : {prauc2:.4f}")





detail["cl_cluster_id"].value_counts().sort_index()


detail.groupby("cl_cluster_id")[X_cols].mean()

train2.groupby("cl_cluster_shift")["pk_shift"].mean()
test2.groupby("cl_cluster_shift")["pk_shift"].mean()

# 1) 군집별 업종(코드+명) 출현 빈도
#    (detail은 분기별 행이므로, 같은 업종이 여러 분기/여러 상권에서 반복 등장 가능)
need_name_cols = ["서비스_업종_코드", "서비스_업종_코드_명"]
missing_name_cols = [c for c in need_name_cols if c not in detail.columns]
if missing_name_cols:
    raise ValueError(f"card_ts_q_struct.csv missing industry name columns: {missing_name_cols}")

cluster_ind_cnt = (
    detail.groupby(["cl_cluster_id", "서비스_업종_코드", "서비스_업종_코드_명"])
          .size()
          .reset_index(name="n_rows")
)

# 2) 군집별 '서로 다른' 업종 개수(다양성)
cluster_ind_nunique = (
    detail.groupby("cl_cluster_id")["서비스_업종_코드"]
          .nunique()
          .reset_index(name="n_unique_industries")
)

# 3) 군집별 상위 업종명 TOP_N (빈도 기준)
TOP_N = 10
cluster_top_ind = (
    cluster_ind_cnt.sort_values(["cl_cluster_id", "n_rows"], ascending=[True, False])
                   .groupby("cl_cluster_id")
                   .head(TOP_N)
                   .reset_index(drop=True)
)


# 4) 최소 출력: 군집별 업종 다양성 + 군집별 TOP3 업종명
top3 = (
    cluster_ind_cnt.sort_values(["cl_cluster_id", "n_rows"], ascending=[True, False])
                   .groupby("cl_cluster_id")
                   .head(3)
                   .reset_index(drop=True)
)

print("\n[Cluster diversity] # of unique industries per cluster")
print(cluster_ind_nunique.sort_values("cl_cluster_id").to_string(index=False))

print("\n[Top industries per cluster] (Top3 by rows)")
print(top3.to_string(index=False))

cluster_mean = detail.groupby("cl_cluster_id")[X_cols].mean()
print(cluster_mean[ts_cols])
print(cluster_mean[["share_wkend"]])

############################################
# (확인) 군집 유형(패턴) 다시 요약해서 보기
# - 기존 로직/변수 건드리지 않음
# - 파생변수명 충돌 없음
############################################

# 0) 안전 체크
need_cols_chk = ["cl_cluster_id"] + X_cols
missing_chk = [c for c in need_cols_chk if c not in detail.columns]
if missing_chk:
    raise ValueError(f"detail missing columns for profiling: {missing_chk}")

# 1) 군집별 크기(분포)
cluster_size = (
    detail["cl_cluster_id"]
    .value_counts()
    .sort_index()
    .rename("n_rows")
    .to_frame()
)

# 2) 군집별 평균 패턴(너가 이미 봤던 핵심)
cluster_mean = detail.groupby("cl_cluster_id")[X_cols].mean()

# 3) 군집별 '주요 시간대' 확인: 평균이 가장 큰 시간대(0~6, 6~11, ...)
#    - ts_cols만 대상으로 max time band 뽑기
cluster_peak_ts = (
    cluster_mean[ts_cols]
    .idxmax(axis=1)
    .rename("dominant_ts")
    .to_frame()
)

# 4) 군집별 '주요 시간대 비중' (dominant_ts에 해당하는 값)
cluster_peak_share = (
    cluster_mean[ts_cols]
    .max(axis=1)
    .rename("dominant_ts_share")
    .to_frame()
)

# 5) 군집별 주말 성향(share_wkend 평균)
cluster_weekend = (
    cluster_mean[["share_wkend"]]
    .rename(columns={"share_wkend": "mean_share_wkend"})
)

# 6) 한 번에 합쳐서 최종 요약 테이블 만들기
cluster_profile_summary = (
    cluster_size
    .join(cluster_peak_ts)
    .join(cluster_peak_share)
    .join(cluster_weekend)
    .join(cluster_mean)  )

# (print는 꼭 필요한 것만)
print("\n[Cluster profile summary] size + dominant timeband + weekend tendency")
print(cluster_profile_summary[["n_rows", "dominant_ts", "dominant_ts_share", "mean_share_wkend"]].to_string())


# 1) 군집 이름 매핑 
cluster_name_map = {
    0: "오전 중심형",
    1: "주말·퇴근 집중형",
    2: "야간 중심형",
    -1: "미분류"
}

# 2) detail / train2 / test2에 이름 붙이기
#    (이미 cl_cluster_name이 있으면 충돌 방지)
for _df in [detail, train2, test2]:
    if "cl_cluster_name" in _df.columns:
        _df.drop(columns=["cl_cluster_name"], inplace=True)

detail["cl_cluster_name"] = detail["cl_cluster_id"].map(cluster_name_map)
train2["cl_cluster_name"] = train2["cl_cluster_id"].map(cluster_name_map)
test2["cl_cluster_name"]  = test2["cl_cluster_id"].map(cluster_name_map)

# 3) 확인용 요약 테이블 생성 
cluster_name_check = (
    detail[["cl_cluster_id", "cl_cluster_name"]]
    .drop_duplicates()
    .sort_values("cl_cluster_id")
)
print(cluster_name_check)

print("train2 -1 rate:", train2["cl_cluster_id"].eq(-1).mean())
print("test2  -1 rate:", test2["cl_cluster_id"].eq(-1).mean())
print("detail yq dtype:", detail["yq"].dtype, " | yq NA:", detail["yq"].isna().sum())


train2["cl_cluster_id"].eq(-1).mean(), test2["cl_cluster_id"].eq(-1).mean()

detail["yq"].dtype, detail["yq"].isna().sum()


