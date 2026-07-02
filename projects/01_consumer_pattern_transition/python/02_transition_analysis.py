"""
Consumer Pattern Transition Analysis
Step 2. Transition Analysis
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




