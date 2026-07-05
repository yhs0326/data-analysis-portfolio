# ============================================================
# 0. 라이브러리 불러오기
# ============================================================
import pandas as pd
import numpy as np
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parents[2]

DATA_RAW_DIR = PROJECT_DIR / "data" / "raw"
DATA_PROCESSED_DIR = PROJECT_DIR / "data" / "processed"
DATA_EXTERNAL_DIR = PROJECT_DIR / "data" / "external"

FIGURE_DIR = PROJECT_DIR / "outputs" / "figures"
TABLE_DIR = PROJECT_DIR / "outputs" / "tables"

FIGURE_DIR.mkdir(parents=True, exist_ok=True)
TABLE_DIR.mkdir(parents=True, exist_ok=True)

from sklearn.linear_model import LogisticRegression
from sklearn.metrics import (
    roc_auc_score, average_precision_score,
    precision_recall_curve, classification_report,
    confusion_matrix
)


# ============================================================
# 1. 학습 데이터 불러오기 및 기본 전처리
# ============================================================
####데이터 가져오기
path = DATA_PROCESSED_DIR / "train_pk_shift.csv"
data = pd.read_csv(path, encoding="utf-8")

#######type fix하기#####
data['pk_shift'] = data['pk_shift'].astype(int)
ts_cols = ["ts_0_6","ts_6_11","ts_11_14","ts_14_17","ts_17_21","ts_21_24"]
X_cols = ts_cols + ["share_wkend"]

#####export로 인해 결측값이 생겼을 수도 있어 안전장치 마련#######
assert data[X_cols].isna().sum().sum() == 0, "Feature NA exists"
assert data['pk_shift'].isna().sum() == 0, "Target NA exists"


# ============================================================
# 2. Walk-forward 평가 (운영 시뮬레이션)
# ============================================================
###### Walk-forward 평가 (운영 시뮬레이션) #######SS
data["yq"] = data["yq"].astype(int)

# yq 순서
yqs = sorted(data["yq"].unique())

MIN_TRAIN_QUARTERS = 4     # 최소 학습 분기 수
TARGET_RECALL = 0.70       # 임계값은 train에서 recall 기준으로 선택

def pick_thr_by_recall(y_true, proba, target_recall=0.70):
    prec, rec, thr = precision_recall_curve(y_true, proba)
    rec2 = rec[:-1]   # thr 길이에 맞춤
    thr2 = thr
    mask = rec2 >= target_recall
    if mask.any():
        return float(thr2[mask].max())
    return float(thr2[np.argmax(rec2)])

wf_rows = []

for i in range(MIN_TRAIN_QUARTERS, len(yqs)):
    test_yq = yqs[i]
    train_yqs = yqs[:i]

    train = data[data["yq"].isin(train_yqs)].copy()
    test  = data[data["yq"] == test_yq].copy()

    X_train, y_train = train[X_cols], train["pk_shift"].astype(int).values
    X_test,  y_test  = test[X_cols],  test["pk_shift"].astype(int).values

    clf = LogisticRegression(max_iter=2000, class_weight="balanced", n_jobs=-1)
    clf.fit(X_train, y_train)

    proba_train = clf.predict_proba(X_train)[:, 1]
    proba_test  = clf.predict_proba(X_test)[:, 1]

    roc = roc_auc_score(y_test, proba_test)
    pr  = average_precision_score(y_test, proba_test)

    thr = pick_thr_by_recall(y_train, proba_train, TARGET_RECALL)
    pred = (proba_test >= thr).astype(int)

    # fold 결과 저장
    wf_rows.append({
        "test_yq": int(test_yq),
        "n_test": int(len(test)),
        "roc_auc": float(roc),
        "pr_auc": float(pr),
        "thr(train_recall>=%.2f)" % TARGET_RECALL: float(thr),
        "pred_pos_rate": float(pred.mean()),
        "true_pos_rate": float(y_test.mean())
    })

wf = pd.DataFrame(wf_rows).sort_values("test_yq")
print("\n[Walk-forward 결과(분기별)]")
print(wf.to_string(index=False))

print("\n[Walk-forward 평균]")
print(wf[["roc_auc","pr_auc"]].mean().to_string())

print("\n[Walk-forward 표준편차(안정성)]")
print(wf[["roc_auc","pr_auc"]].std().to_string())

#  이후 군집분석/코호트 단계에서 train/test를 쓰고 있었으니,
#    아래에서 사용할 수 있게 'cut'을 하나 정해 두자(예: 마지막 평가분기 직전까지 train)
cut_yq = yqs[-2]  # 마지막 분기는 next가 없어 레이블/유지율이 끊길 수 있어서 -2 
train = data[data["yq"] <= cut_yq].copy()
test  = data[data["yq"] >  cut_yq].copy()

print("\n[Split for downstream steps]")
print("cut_yq:", cut_yq, "| train max yq:", train["yq"].max(), "| test min yq:", test["yq"].min())




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

# ==========================
# Tableau용 PCA K-means scatter CSV 생성
# ==========================

from sklearn.decomposition import PCA
from sklearn.preprocessing import StandardScaler
import os

# 저장 경로
out_dir = TABLE_DIR
os.makedirs(out_dir, exist_ok=True)

# 시간대 매출 비중 변수
ts_cols_pca = ["ts_0_6", "ts_6_11", "ts_11_14", "ts_14_17", "ts_17_21", "ts_21_24"]

# 필요한 컬럼 체크
need_pca_cols = [
    "상권_코드",
    "서비스_업종_코드",
    "yq",
    "cl_cluster_name"
] + ts_cols_pca

missing_pca_cols = [c for c in need_pca_cols if c not in detail.columns]
if missing_pca_cols:
    raise ValueError(f"PCA CSV 생성에 필요한 컬럼이 없습니다: {missing_pca_cols}")

# 필요한 데이터만 사용
pca_df = detail.dropna(subset=ts_cols_pca + ["cl_cluster_name"]).copy()

# Tableau에서 너무 무거우면 샘플링
if len(pca_df) > 20000:
    pca_df = pca_df.sample(20000, random_state=42)

# PCA 실행
X = pca_df[ts_cols_pca].values
X_scaled = StandardScaler().fit_transform(X)

pca = PCA(n_components=2)
pca_result = pca.fit_transform(X_scaled)

pca_df["PC1"] = pca_result[:, 0]
pca_df["PC2"] = pca_result[:, 1]

# 설명력
pca_df["PC1_explained_pct"] = round(pca.explained_variance_ratio_[0] * 100, 1)
pca_df["PC2_explained_pct"] = round(pca.explained_variance_ratio_[1] * 100, 1)

# Tableau용 컬럼만 저장
tableau_pca = pca_df[
    [
        "상권_코드",
        "서비스_업종_코드",
        "yq",
        "cl_cluster_name",
        "PC1",
        "PC2",
        "PC1_explained_pct",
        "PC2_explained_pct"
    ]
].copy()

out_path = os.path.join(out_dir, "pca_kmeans_tableau.csv")

tableau_pca.to_csv(
    out_path,
    index=False,
    encoding="utf-8-sig"
)

print("Tableau용 PCA K-means CSV 저장 완료:", out_path)
print("PC1 설명력:", round(pca.explained_variance_ratio_[0] * 100, 1), "%")
print("PC2 설명력:", round(pca.explained_variance_ratio_[1] * 100, 1), "%")
print("저장 행 수:", len(tableau_pca))

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


# ============================================================
# 4. Cohort export (train2 + test2 전체 시계열)
# ============================================================
# ==========================
# Cohort export  (train2 + test2 전체 시계열)
# ==========================
path_out = TABLE_DIR / "cohort_q.csv"

need_cols = ["상권_코드", "서비스_업종_코드", "yq",
             "pk_shift", "cl_cluster_shift", "cl_cluster_name"]

# train2 + test2 합치기
cohort_all = pd.concat([train2, test2], ignore_index=True)

missing = [c for c in need_cols if c not in cohort_all.columns]
if missing:
    raise ValueError(f"cohort_all missing columns: {missing}")

cohort_q = cohort_all[need_cols].copy()

# 타입 안전
cohort_q["yq"] = cohort_q["yq"].astype(int)
cohort_q["pk_shift"] = cohort_q["pk_shift"].astype(int)
cohort_q["cl_cluster_shift"] = cohort_q["cl_cluster_shift"].astype(int)
cohort_q["cl_cluster_name"] = cohort_q["cl_cluster_name"].astype(str)

cohort_q.to_csv(path_out, index=False, encoding="utf-8")

print("cohort_q yq range:", cohort_q["yq"].min(), "~", cohort_q["yq"].max())
print(cohort_q.shape)
print(cohort_q.isna().mean())
print(cohort_q.head())


dup = cohort_q.duplicated(subset=["상권_코드","서비스_업종_코드","yq"]).mean()
print("dup key rate:", dup)





# ============================================================
# 5. 운영/해석용 추가 결과 출력
# ============================================================
# ==========================
# 5개(운영/해석용) 결과 뽑는 코드
# - wf DataFrame(=walk-forward 결과) 가 이미 생성되어 있다는 전제
# ==========================
# --------------------------
# 0) 준비: wf에 test_yq가 있으니 원본 data에서 분기별 test셋을 다시 꺼내 평가
#    (walk-forward 루프를 다시 돌리지 않고, wf의 test_yq만 재사용)
# --------------------------

TARGET_RECALL = 0.70  

def pick_thr_by_recall(y_true, proba, target_recall=0.70):
    prec, rec, thr = precision_recall_curve(y_true, proba)
    rec2 = rec[:-1]  # thr 길이에 맞춤
    thr2 = thr
    mask = rec2 >= target_recall
    if mask.any():
        return float(thr2[mask].max())
    return float(thr2[np.argmax(rec2)])

def precision_recall_at_thr(y_true, proba, thr):
    pred = (proba >= thr).astype(int)
    tp = ((pred == 1) & (y_true == 1)).sum()
    fp = ((pred == 1) & (y_true == 0)).sum()
    fn = ((pred == 0) & (y_true == 1)).sum()
    precision = tp / (tp + fp) if (tp + fp) > 0 else np.nan
    recall    = tp / (tp + fn) if (tp + fn) > 0 else np.nan
    return float(precision), float(recall), float(pred.mean())

# --------------------------
# 1) Walk-forward: test recall / test precision
#    + pred_pos_rate - true_pos_rate
# --------------------------

thr_col = [c for c in wf.columns if c.startswith("thr(train_recall")]
if not thr_col:
    raise ValueError("wf에 threshold 컬럼이 없습니다. (thr(train_recall...) 컬럼 확인)")
thr_col = thr_col[0]

# fold별 precision/recall 재계산 (train에서 잡은 thr을 그대로 test에 적용)
rows = []
for _, r in wf.iterrows():
    test_yq = int(r["test_yq"])
    thr = float(r[thr_col])

    test = data[data["yq"] == test_yq].copy()
    X_test = test[X_cols]
    y_test = test["pk_shift"].astype(int).values

    # train_yqs = yqs[:i] 동일 로직 재현
    # test_yq의 index를 찾아 그 이전까지 train으로 학습
    i = yqs.index(test_yq)
    train_yqs = yqs[:i]
    train = data[data["yq"].isin(train_yqs)].copy()

    X_train = train[X_cols]
    y_train = train["pk_shift"].astype(int).values

    clf = LogisticRegression(max_iter=2000, class_weight="balanced", n_jobs=-1)
    clf.fit(X_train, y_train)

    proba_test = clf.predict_proba(X_test)[:, 1]

    prec, rec, pred_pos_rate = precision_recall_at_thr(y_test, proba_test, thr)
    true_pos_rate = float(y_test.mean())

    rows.append({
        "test_yq": test_yq,
        "test_precision": prec,
        "test_recall": rec,
        "pred_pos_rate": pred_pos_rate,
        "true_pos_rate": true_pos_rate,
        "pred_minus_true": pred_pos_rate - true_pos_rate
    })

wf_pr = pd.DataFrame(rows).sort_values("test_yq")

print("\n[1) Walk-forward: test precision/recall]")
print(wf_pr.to_string(index=False))

print("\n[1-요약] 평균/표준편차")
print("precision mean/std:", wf_pr["test_precision"].mean(), wf_pr["test_precision"].std())
print("recall    mean/std:", wf_pr["test_recall"].mean(), wf_pr["test_recall"].std())

print("\n[2) pred_pos_rate - true_pos_rate (과탐/과소탐 체크)]")
print(wf_pr[["test_yq","pred_pos_rate","true_pos_rate","pred_minus_true"]].to_string(index=False))
print("pred_minus_true mean/std:", wf_pr["pred_minus_true"].mean(), wf_pr["pred_minus_true"].std())

# --------------------------
# 3) cluster_shift lift (train2 / test2 기준)
# --------------------------
def lift_by_shift(df, y="pk_shift", g="cl_cluster_shift"):
    rate0 = df.loc[df[g] == 0, y].mean()
    rate1 = df.loc[df[g] == 1, y].mean()
    lift = (rate1 / rate0) if (rate0 and rate0 > 0) else np.nan
    return float(rate0), float(rate1), float(lift)

tr0, tr1, tr_lift = lift_by_shift(train2)
te0, te1, te_lift = lift_by_shift(test2)

print("\n[3) cluster_shift lift]")
print(f"TRAIN: shift=0 rate={tr0:.4f} | shift=1 rate={tr1:.4f} | lift={tr_lift:.4f}")
print(f"TEST : shift=0 rate={te0:.4f} | shift=1 rate={te1:.4f} | lift={te_lift:.4f}")

# --------------------------
# 4) 분기별 ROC/PR 추이 
# --------------------------
print("\n[4) 분기별 ROC/PR 추이 (wf)]")
print(wf[["test_yq","roc_auc","pr_auc"]].sort_values("test_yq").to_string(index=False))

print("\n[4-요약] 연도별 평균 (원하면 연도별 drift 보기 좋음)")
tmp = wf.copy()
tmp["year"] = tmp["test_yq"] // 10
print(tmp.groupby("year")[["roc_auc","pr_auc"]].mean().round(4))

# --------------------------
# 5) cohort_q 분기별 row 수 (급감/누락 체크)
# --------------------------
# cohort_q는 너가 만든 DataFrame (train2+test2 concat) 전제
if "cohort_q" not in globals():
    raise ValueError("cohort_q 변수가 없습니다. (export 직전 cohort_q DataFrame)")
print("\n[5) cohort_q 분기별 row 수]")
by_yq = cohort_q.groupby("yq").size().rename("n_rows").reset_index().sort_values("yq")
print(by_yq.to_string(index=False))

print("\n[5-추가] row 수 급감 여부(전분기 대비 변화율)")
by_yq["prev"] = by_yq["n_rows"].shift(1)
by_yq["pct_change"] = (by_yq["n_rows"] / by_yq["prev"] - 1.0)
print(by_yq[["yq","n_rows","pct_change"]].to_string(index=False))



# ============================================================
# 6. 전이행렬 히트맵 생성 및 저장
# ============================================================
####################################################
# -*- coding: utf-8 -*-
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt

# =========================
# 0) 한글 폰트(Windows) - 축 이름 깨짐 방지
# =========================
plt.rcParams["font.family"] = "Malgun Gothic"
plt.rcParams["axes.unicode_minus"] = False

# =========================
# 1) 데이터 로드
# =========================
tm_path = DATA_PROCESSED_DIR / "transition_matrix.csv"
tm = pd.read_csv(tm_path, encoding="utf-8")

# 어떤 비율로 그릴지 선택
# - 추천: 가중(매출) 비율
value_col = "rate_by_from_cluster_wavg"
# value_col = "rate_by_from_cluster"  # (건수 기준이면 이걸로)

# =========================
# 2) pivot 만들기 (from -> to)
# =========================
mat = tm.pivot_table(
    index="from_cluster",
    columns="to_cluster",
    values=value_col,
    aggfunc="sum",
    fill_value=0.0
)

# 혹시 누락된 클러스터가 있으면 정사각으로 맞추기
labels = sorted(set(mat.index) | set(mat.columns))
mat = mat.reindex(index=labels, columns=labels, fill_value=0.0)

# 퍼센트로 변환
mat_pct = mat * 100

# =========================
# 3) 그리기 함수
# =========================
def draw_heatmap(mat_pct, title, out_path, mode="include_stay"):
    """
    mode:
      - "include_stay": 대각선 포함 (0~100 스케일)
      - "transition_only": 대각선은 '-'로 표시 + 색은 off-diagonal max 기준으로 강하게
    """
    data = mat_pct.copy()

    if mode == "transition_only":
        # 대각선은 색 채우지 않도록 NaN 처리(흰색)
        np.fill_diagonal(data.values, np.nan)
        vmax = np.nanmax(data.values)  # off-diagonal max로 색 강하게
        if not np.isfinite(vmax) or vmax <= 0:
            vmax = 1.0
    else:
        vmax = 100.0

    fig, ax = plt.subplots(figsize=(9, 7))
    cmap = plt.cm.Reds.copy()
    cmap.set_bad(color="white")  # NaN(대각선) 흰색 처리

    im = ax.imshow(data.values, vmin=0, vmax=vmax, cmap=cmap)

    # 타이틀/축
    ax.set_title(title, fontsize=26, pad=18)
    ax.set_xticks(range(len(data.columns)))
    ax.set_yticks(range(len(data.index)))
    ax.set_xticklabels(data.columns, fontsize=18)
    ax.set_yticklabels(data.index, fontsize=20)

    # 그리드(셀 경계)
    ax.set_xticks(np.arange(-.5, len(data.columns), 1), minor=True)
    ax.set_yticks(np.arange(-.5, len(data.index), 1), minor=True)
    ax.grid(which="minor", color="white", linewidth=2)
    ax.tick_params(which="minor", bottom=False, left=False)

    # 값 표기
    for i in range(len(data.index)):
        for j in range(len(data.columns)):
            v = data.iat[i, j]
            if np.isnan(v):
                ax.text(j, i, "—", ha="center", va="center", fontsize=18)
            else:
                ax.text(j, i, f"{v:.1f}%", ha="center", va="center", fontsize=18)

    # 컬러바
    cbar = fig.colorbar(im, ax=ax, fraction=0.046, pad=0.04)
    cbar.ax.tick_params(labelsize=14)
    cbar.set_label("전이율(%)", fontsize=16)

    # 여백 최적화 + 저장
    plt.tight_layout()
    plt.savefig(out_path, dpi=300, bbox_inches="tight")
    plt.close(fig)
    print("Saved:", out_path)


# =========================
# 4) 저장 (2종)
# =========================
out1 = FIGURE_DIR / "transition_heatmap_including_stay.png"
out2 = FIGURE_DIR / "transition_heatmap_transition_only.png"

draw_heatmap(mat_pct, "군집 전이 히트맵 (유지 포함)", out1, mode="include_stay")
draw_heatmap(mat_pct, "군집 전이 히트맵 ", out2, mode="transition_only")
