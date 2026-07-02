"""
Consumer Pattern Transition Analysis
Step 3. Risk Analysis
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



