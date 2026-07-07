import os
import shutil
from pathlib import Path
import warnings
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns

from sklearn.preprocessing import StandardScaler
from sklearn.cluster import KMeans
from sklearn.metrics import silhouette_score, roc_auc_score, accuracy_score, confusion_matrix, roc_curve
from sklearn.decomposition import PCA
from sklearn.linear_model import LogisticRegression

from scipy.stats import mannwhitneyu, kruskal, chi2

import statsmodels.api as sm
import statsmodels.formula.api as smf
from patsy.contrasts import Treatment
from statsmodels.stats.diagnostic import het_breuschpagan, linear_reset
from statsmodels.stats.outliers_influence import variance_inflation_factor
from statsmodels.stats.stattools import durbin_watson, jarque_bera

warnings.filterwarnings("ignore")

# ======================
# 설정
# ======================
PROJECT_DIR = Path(__file__).resolve().parents[1]
base_dir = PROJECT_DIR
input_main = base_dir / "data" / "kwcs_model_data.csv"

# output 경로 설정
output_dir = base_dir / "outputs"
table_dir = output_dir / "tables"
fig_dir = output_dir / "figures"
model_dir = output_dir / "models"

default_k = 5
final_k = 5
random_state = 42

cluster_vars = [
    "work_hours", "work_life_balance", "achievement", "work_meaning", "stress",
    "satisfaction", "job_loss_risk", "reemployment_possibility"
]
heat_vars = [
    "work_life_balance", "achievement", "work_meaning", "stress",
    "satisfaction", "job_loss_risk", "reemployment_possibility"
]
quality_indicator_vars = [
    "work_life_balance", "achievement", "work_meaning", "stress",
    "satisfaction", "job_loss_risk", "reemployment_possibility"
]
# cluster_vars:
#   실제 KMeans 군집 생성용 변수 (work_hours 포함)
# quality_indicator_vars:
#   노동의 질 하위 지표 비교/해석용 변수 (work_hours 제외)


presentation_label_map = {
    "quality_of_work": "노동의 질",
    "mean_quality_of_work": "노동의 질 평균",
    "work_life_balance": "일·생활 균형",
    "achievement": "성취감",
    "work_meaning": "일의 의미",
    "stress": "스트레스 낮음",
    "satisfaction": "만족도",
    "job_loss_risk": "고용안정성",
    "reemployment_possibility": "재취업 가능성",
    "work_hours": "근로시간",
    "preferred_hours": "희망근로시간",
    "emp_type": "고용형태",
    "full_part": "근무형태",
    "income": "소득",
    "year": "조사연도",
    "age_group": "연령집단",
    "gender": "성별",
    "cluster": "군집",
    "cluster_label": "노동유형",
    "sample_n": "표본 수",
    "sample_ratio": "비율",
    "vulnerable": "취약 노동유형",
    "odds_ratio": "오즈비",
    "coef": "계수",
    "conf_low": "신뢰구간 하한",
    "conf_high": "신뢰구간 상한",
}
age_group_label_map = {
    "youth": "청년",
    "middle_old": "중장년",
}
emp_type_label_map = {
    1: "상용직", 1.0: "상용직", "1": "상용직", "1.0": "상용직",
    2: "임시직", 2.0: "임시직", "2": "임시직", "2.0": "임시직",
    3: "일용직", 3.0: "일용직", "3": "일용직", "3.0": "일용직",
}
full_part_label_map = {
    1: "전일제", 1.0: "전일제", "1": "전일제", "1.0": "전일제",
    2: "시간제", 2.0: "시간제", "2": "시간제", "2.0": "시간제",
}
cluster_label_map = {
    0: "저성취·저의미형",
    1: "의미추구·불안정형",
    2: "장시간·불균형형",
    3: "고품질·안정형",
    4: "저만족·저품질형",
}

sns.set_theme(style="whitegrid")
# 한글 폰트 설정 (Windows: 맑은 고딕), 마이너스 깨짐 방지
plt.rcParams["font.family"] = "Malgun Gothic"
plt.rcParams["axes.unicode_minus"] = False
plt.rcParams["font.size"] = 11



def label_value(value, mapping):
    return mapping.get(value, mapping.get(str(value), value))


def label_series(series, mapping):
    return series.map(lambda x: label_value(x, mapping))


def label_columns(columns, mapping):
    return [mapping.get(c, c) for c in columns]


def regression_term_to_korean(term):
    term = str(term)

    if term == "Intercept":
        return "절편"

    if "C(year" in term and "2023" in term:
        return "2023년"

    if "C(age_group" in term and "youth" in term:
        return "청년"

    if "C(emp_type" in term:
        if "T.2" in term:
            return "임시직"
        if "T.3" in term:
            return "일용직"
        return "고용형태"

    if "C(full_part" in term:
        if "T.2" in term:
            return "시간제"
        return "근무형태"

    if "C(gender" in term:
        if "T.1" in term:
            return "성별 1"
        if "T.2" in term:
            return "성별 2"
        return "성별"

    replacements = {
        "quality_of_work": "노동의 질",
        "work_life_balance": "일·생활 균형",
        "achievement": "성취감",
        "work_meaning": "일의 의미",
        "stress": "스트레스 낮음",
        "satisfaction": "만족도",
        "job_loss_risk": "고용안정성",
        "reemployment_possibility": "재취업 가능성",
        "work_hours": "근로시간",
        "preferred_hours": "희망근로시간",
        "income": "소득",
        "year": "조사연도",
        "age_group": "연령집단",
        "gender": "성별",
        "emp_type": "고용형태",
        "full_part": "근무형태",
    }

    for old, new in replacements.items():
        term = term.replace(old, new)

    return term


def save_fig(path):
    plt.savefig(path, dpi=300, bbox_inches="tight")
    plt.close()


def ensure_dirs():
    for d in [output_dir, table_dir, fig_dir, model_dir]:
        os.makedirs(d, exist_ok=True)
    backup_dir = os.path.join(fig_dir, "figures_backup_before_korean_labels")
    os.makedirs(backup_dir, exist_ok=True)
    for file_name in os.listdir(fig_dir):
        if file_name.lower().endswith(".png"):
            src = os.path.join(fig_dir, file_name)
            dst = os.path.join(backup_dir, file_name)
            if os.path.isfile(src) and not os.path.exists(dst):
                shutil.copy2(src, dst)


def check_file(path):
    if not os.path.exists(path):
        raise FileNotFoundError(f"[오류] 파일을 찾을 수 없습니다: {path}")


def coef_table(model):
    ci = model.conf_int()
    out = pd.DataFrame({
        "term": model.params.index,
        "coef": model.params.values,
        "p_value": model.pvalues.values,
        "conf_low": ci[0].values,
        "conf_high": ci[1].values,
    })
    return out


def plot_coef(df, title, path, top_n=None):
    temp = df[df["term"] != "Intercept"].copy()
    if top_n is not None and len(temp) > top_n:
        temp = temp.reindex(temp["coef"].abs().sort_values(ascending=False).head(top_n).index)
    temp = temp.sort_values("coef")
    temp["term_label"] = temp["term"].map(regression_term_to_korean)
    plt.figure(figsize=(10, max(5, len(temp) * 0.25)))
    plt.errorbar(
        x=temp["coef"],
        y=temp["term_label"],
        xerr=[temp["coef"] - temp["conf_low"], temp["conf_high"] - temp["coef"]],
        fmt="o",
        capsize=3,
    )
    plt.axvline(0, color="red", linestyle="--", linewidth=1)
    plt.title(title)
    plt.xlabel("계수")
    plt.ylabel("변수")
    save_fig(path)


# ======================
# 비모수 검정
# ======================
results = []

youth_q = df[df["age_group"] == "youth"]
q17 = youth_q[youth_q["year"] == 2017]["quality_of_work"].dropna()
q23 = youth_q[youth_q["year"] == 2023]["quality_of_work"].dropna()
if len(q17) > 0 and len(q23) > 0:
    stat, p = mannwhitneyu(q17, q23, alternative="two-sided")
    results.append(["MWU_youth_2017_vs_2023_quality", stat, p])

m_y = df[df["age_group"] == "youth"]["quality_of_work"].dropna()
m_m = df[df["age_group"] == "middle_old"]["quality_of_work"].dropna()
if len(m_y) > 0 and len(m_m) > 0:
    stat, p = mannwhitneyu(m_y, m_m, alternative="two-sided")
    results.append(["MWU_youth_vs_middle_old_quality", stat, p])

groups_q = [g["quality_of_work"].dropna().values for _, g in youth_cluster_base.groupby("cluster")]
if len(groups_q) >= 2:
    stat, p = kruskal(*groups_q)
    results.append(["Kruskal_youth_cluster_quality", stat, p])

for v in cluster_vars:
    gv = [g[v].dropna().values for _, g in youth_cluster_base.groupby("cluster")]
    if len(gv) >= 2:
        stat, p = kruskal(*gv)
        results.append([f"Kruskal_youth_cluster_{v}", stat, p])

np_df = pd.DataFrame(results, columns=["test_name", "statistic", "p_value"])
np_df.to_csv(os.path.join(table_dir, "nonparametric_tests.csv"), index=False, encoding="utf-8-sig")
