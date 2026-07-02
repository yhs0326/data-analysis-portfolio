"""
Consumer Pattern Transition Analysis
Step 4. Visualization
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
# 6. 전이행렬 히트맵 생성 및 저장
# ============================================================
####################################################
# -*- coding: utf-8 -*-
from pathlib import Path

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
tm_path = TABLE_DIR / "transition_matrix.csv"
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
