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
# 데이터 로딩
# ======================
ensure_dirs()
check_file(input_main)

df = pd.read_csv(input_main, encoding="utf-8")
df.info()
df.describe(include="all").transpose().head(20)

missing_counts = df.isna().sum().rename("null_count")
year_age_counts = df.groupby(["year", "age_group"]).size().rename("n").reset_index()

overview = pd.DataFrame({
    "metric": ["n_rows", "n_cols"],
    "value": [df.shape[0], df.shape[1]]
})
overview.to_csv(os.path.join(table_dir, "data_overview.csv"), index=False, encoding="utf-8-sig")
missing_counts.to_csv(os.path.join(table_dir, "data_missing_counts.csv"), encoding="utf-8-sig")
year_age_counts.to_csv(os.path.join(table_dir, "data_year_age_group_counts.csv"), index=False, encoding="utf-8-sig")

# ======================
# 군집분석
# ======================
youth = df[df["age_group"] == "youth"].copy()
youth_cluster_base = youth.dropna(subset=cluster_vars).copy()
youth_cluster_base = youth_cluster_base[youth_cluster_base["work_hours"].between(0, 112)].copy()
X = youth_cluster_base[cluster_vars].values
scaler = StandardScaler()
x_scaled = scaler.fit_transform(X)

sil_rows = []
for k in range(2, 7):
    km = KMeans(n_clusters=k, random_state=random_state, n_init=20)
    labels = km.fit_predict(x_scaled)
    sil = silhouette_score(x_scaled, labels)
    sil_rows.append({"k": k, "inertia": km.inertia_, "silhouette": sil})

sil_df = pd.DataFrame(sil_rows)
# quality_of_work는 군집 해석용 지표로만 사용
best_k_all = int(sil_df.loc[sil_df["silhouette"].idxmax(), "k"])
best_score_all = float(sil_df.loc[sil_df["silhouette"].idxmax(), "silhouette"])
candidate_df = sil_df[sil_df["k"].between(3, 5)].copy()
best_k_3_5 = int(candidate_df.loc[candidate_df["silhouette"].idxmax(), "k"])
best_score_3_5 = float(candidate_df.loc[candidate_df["silhouette"].idxmax(), "silhouette"])
# 최종 k=5 고정
final_k = 5
sil_df["is_best_all"] = (sil_df["k"] == best_k_all).astype(int)
sil_df["is_selected_final"] = (sil_df["k"] == final_k).astype(int)
sil_df.to_csv(os.path.join(table_dir, "silhouette_results.csv"), index=False, encoding="utf-8-sig")

k_selection_reason = pd.DataFrame([{
    "selected_k": final_k,
    "reason": "silhouette, elbow, cluster size balance, 해석 가능성, 공모전 스토리라인을 종합하여 k=5로 최종 고정",
    "best_k_all": best_k_all,
    "best_score_all": round(best_score_all, 4),
    "best_k_3_5": best_k_3_5,
    "best_score_3_5": round(best_score_3_5, 4),
}])
k_selection_reason.to_csv(os.path.join(table_dir, "k_selection_reason.csv"), index=False, encoding="utf-8-sig")

plt.figure(figsize=(7, 5))
plt.plot(sil_df["k"], sil_df["inertia"], marker="o")
plt.title("KMeans Elbow Plot")
plt.xlabel("군집 수(k)")
plt.ylabel("군집 내 제곱합(Inertia)")
save_fig(os.path.join(fig_dir, "fig_kmeans_elbow.png"))

plt.figure(figsize=(7, 5))
plt.plot(sil_df["k"], sil_df["silhouette"], marker="o")
plt.title("KMeans Silhouette Score")
plt.xlabel("군집 수(k)")
plt.ylabel("실루엣 점수")
save_fig(os.path.join(fig_dir, "fig_kmeans_silhouette.png"))

kmeans_final = KMeans(n_clusters=final_k, random_state=random_state, n_init=20)
youth_cluster_base["cluster"] = kmeans_final.fit_predict(x_scaled)
if set(youth_cluster_base["cluster"].unique()) != set(range(5)):
    raise ValueError("최종 k=5 군집 번호 0~4가 모두 생성되지 않았습니다. final_k와 cluster_profile을 확인하세요.")
youth_cluster_base.to_csv(os.path.join(table_dir, "youth_clustered_data.csv"), index=False, encoding="utf-8-sig")

profile_extra_vars = ["income", "preferred_hours", "gender"]
cluster_profile = youth_cluster_base.groupby("cluster").agg(
    sample_n=("quality_of_work", "size"),
    quality_of_work=("quality_of_work", "mean"),
    **{v: (v, "mean") for v in cluster_vars},
    **{v: (v, "mean") for v in profile_extra_vars}
).reset_index().round(4)
cluster_profile["sample_ratio"] = (cluster_profile["sample_n"] / cluster_profile["sample_n"].sum()).round(4)
cluster_profile.to_csv(os.path.join(table_dir, "cluster_profile.csv"), index=False, encoding="utf-8-sig")

cluster_profile_long = cluster_profile.melt(id_vars=["cluster", "sample_n"], var_name="variable", value_name="value")
cluster_profile_long.to_csv(os.path.join(table_dir, "cluster_profile_long.csv"), index=False, encoding="utf-8-sig")

comp_frames = []
for var in ["emp_type", "full_part", "year"]:
    tmp = pd.crosstab(youth_cluster_base["cluster"], youth_cluster_base[var], normalize="index")
    tmp = tmp.reset_index().melt(id_vars="cluster", var_name="category", value_name="ratio")
    tmp["variable"] = var
    comp_frames.append(tmp)
cluster_comp = pd.concat(comp_frames, axis=0, ignore_index=True)
cluster_comp.to_csv(os.path.join(table_dir, "cluster_composition.csv"), index=False, encoding="utf-8-sig")

heat_df = cluster_profile.set_index("cluster")[heat_vars]
heat_df_plot = heat_df.rename(columns=presentation_label_map)
heat_df_plot.index = heat_df_plot.index.map(cluster_label_map)
plt.figure(figsize=(10, 5))
sns.heatmap(heat_df_plot, annot=True, fmt=".2f", cmap="YlGnBu")
plt.title("군집별 노동의 질 하위지표 평균")
plt.xlabel("하위 지표")
plt.ylabel("노동유형")
save_fig(os.path.join(fig_dir, "fig_cluster_profile_heatmap.png"))

heat_z = (heat_df - heat_df.mean()) / heat_df.std()
heat_z.to_csv(os.path.join(table_dir, "cluster_profile_heatmap_zscore.csv"), encoding="utf-8-sig")
heat_z_plot = heat_z.rename(columns=presentation_label_map)
heat_z_plot.index = heat_z_plot.index.map(cluster_label_map)
plt.figure(figsize=(10, 5))
sns.heatmap(heat_z_plot, annot=True, fmt=".2f", cmap="RdBu_r", center=0)
plt.title("청년 노동유형별 상대적 특징(z-score)")
plt.xlabel("하위 지표")
plt.ylabel("노동유형")
save_fig(os.path.join(fig_dir, "fig_cluster_profile_heatmap_zscore.png"))

cluster_profile_plot = cluster_profile.copy()
cluster_profile_plot["cluster_label"] = label_series(cluster_profile_plot["cluster"], cluster_label_map)
plt.figure(figsize=(7, 5))
sns.barplot(data=cluster_profile_plot, x="cluster_label", y="quality_of_work")
plt.title("청년 노동유형별 노동의 질 평균")
plt.xlabel("노동유형")
plt.ylabel("노동의 질 평균")
plt.xticks(rotation=20, ha="right")
save_fig(os.path.join(fig_dir, "fig_cluster_quality_mean.png"))

plt.figure(figsize=(7, 5))
sns.barplot(data=cluster_profile_plot, x="cluster_label", y="work_hours")
plt.title("청년 노동유형별 평균 근로시간")
plt.xlabel("노동유형")
plt.ylabel("평균 근로시간")
plt.xticks(rotation=20, ha="right")
save_fig(os.path.join(fig_dir, "fig_cluster_work_hours_mean.png"))

pca = PCA(n_components=2, random_state=random_state)
x_pca = pca.fit_transform(x_scaled)
pca_df = pd.DataFrame({"PC1": x_pca[:, 0], "PC2": x_pca[:, 1], "cluster": youth_cluster_base["cluster"].values})
pca_df["cluster_label"] = label_series(pca_df["cluster"], cluster_label_map)
# PCA 시각화는 군집 간 대략적인 분포 확인용이며, 사회조사 데이터 특성상 군집 간 중첩이 발생할 수 있다.
plt.figure(figsize=(8, 6))
sns.scatterplot(data=pca_df, x="PC1", y="PC2", hue="cluster_label", palette="tab10", s=35)
plt.title("청년 노동유형 PCA 보조 시각화")
plt.xlabel("주성분 1")
plt.ylabel("주성분 2")
plt.legend(title="노동유형")
plt.savefig(os.path.join(fig_dir, "fig_cluster_pca.png"), dpi=300, bbox_inches="tight")
plt.savefig(os.path.join(fig_dir, "fig_cluster_pca_appendix.png"), dpi=300, bbox_inches="tight")
plt.close()

year_comp = pd.crosstab(youth_cluster_base["cluster"], youth_cluster_base["year"], normalize="index")
year_comp.index = year_comp.index.map(cluster_label_map)
year_comp.plot(kind="bar", stacked=True, figsize=(8, 5), colormap="Set2")
plt.title("청년 노동유형별 조사연도 구성비")
plt.xlabel("노동유형")
plt.ylabel("비율")
plt.legend(title="조사연도")
plt.xticks(rotation=20, ha="right")
save_fig(os.path.join(fig_dir, "fig_cluster_year_composition.png"))

fp_comp = pd.crosstab(youth_cluster_base["cluster"], youth_cluster_base["full_part"], normalize="index")
fp_comp.index = fp_comp.index.map(cluster_label_map)
fp_comp = fp_comp.rename(columns=full_part_label_map)
fp_comp.plot(kind="bar", stacked=True, figsize=(8, 5), colormap="Set3")
plt.title("청년 노동유형별 전일제·시간제 구성비")
plt.xlabel("노동유형")
plt.ylabel("비율")
plt.legend(title="근무형태")
plt.xticks(rotation=20, ha="right")
save_fig(os.path.join(fig_dir, "fig_cluster_full_part_composition.png"))

# 군집명 수정
label_map = cluster_label_map

label_df = pd.DataFrame(sorted(label_map.items()), columns=["cluster", "temp_label"])
label_df.to_csv(os.path.join(table_dir, "cluster_label_map.csv"), index=False, encoding="utf-8-sig")
cluster_profile["cluster_label"] = cluster_profile["cluster"].map(label_map)
cluster_profile.to_csv(os.path.join(table_dir, "cluster_profile.csv"), index=False, encoding="utf-8-sig")
cluster_profile.to_csv(os.path.join(table_dir, "cluster_profile_labeled.csv"), index=False, encoding="utf-8-sig")
cluster_profile_long = cluster_profile.melt(id_vars=["cluster", "cluster_label", "sample_n", "sample_ratio"], var_name="variable", value_name="value")
cluster_profile_long.to_csv(os.path.join(table_dir, "cluster_profile_long.csv"), index=False, encoding="utf-8-sig")
youth_cluster_base["cluster_label"] = youth_cluster_base["cluster"].map(label_map)
youth_cluster_base.to_csv(os.path.join(table_dir, "youth_clustered_labeled_data.csv"), index=False, encoding="utf-8-sig")

age_cmp = df.groupby("age_group")[ ["quality_of_work"] + quality_indicator_vars ].mean().round(4).reset_index()
age_cmp.to_csv(os.path.join(table_dir, "age_group_indicator_comparison.csv"), index=False, encoding="utf-8-sig")

age_cmp_long = age_cmp.melt(id_vars="age_group", var_name="indicator", value_name="mean")
age_cmp_long_plot = age_cmp_long.copy()
age_cmp_long_plot["indicator_label"] = label_series(age_cmp_long_plot["indicator"], presentation_label_map)
age_cmp_long_plot["age_group_label"] = label_series(age_cmp_long_plot["age_group"], age_group_label_map)
plt.figure(figsize=(12, 6))
sns.barplot(data=age_cmp_long_plot, x="indicator_label", y="mean", hue="age_group_label")
plt.title("연령집단별 노동의 질 및 하위 지표 평균")
plt.xlabel("지표")
plt.ylabel("평균")
plt.legend(title="연령집단")
plt.xticks(rotation=30, ha="right")
save_fig(os.path.join(fig_dir, "fig_age_group_indicator_comparison.png"))

# exploratory
for g in ["youth", "middle_old"]:
    sub = df[df["age_group"] == g].dropna(subset=cluster_vars).copy()
    if len(sub) < final_k:
        continue
    xg = StandardScaler().fit_transform(sub[cluster_vars])
    kg = KMeans(n_clusters=final_k, random_state=random_state, n_init=20)
    sub["cluster"] = kg.fit_predict(xg)
    gp = sub.groupby("cluster")[["quality_of_work"] + cluster_vars].mean().round(4)
    gp.to_csv(os.path.join(table_dir, f"exploratory_cluster_profile_{g}.csv"), encoding="utf-8-sig")

# 군집 안정성 검토
stability_seeds = [11, 22, 33, 42, 52, 62, 72, 82, 92, 102]
stability_rows = []
for seed in stability_seeds:
    km = KMeans(n_clusters=final_k, random_state=seed, n_init=20)
    labels = km.fit_predict(x_scaled)
    silhouette = silhouette_score(x_scaled, labels)
    counts = pd.Series(labels).value_counts().sort_index()
    min_cluster_size = int(counts.min())
    max_cluster_size = int(counts.max())
    size_ratio_max_min = float(max_cluster_size / min_cluster_size)
    stability_rows.append({
        "seed": seed,
        "silhouette": round(float(silhouette), 4),
        "min_cluster_size": min_cluster_size,
        "max_cluster_size": max_cluster_size,
        "size_ratio_max_min": round(size_ratio_max_min, 4),
    })
cluster_stability_check = pd.DataFrame(stability_rows)
cluster_stability_check.to_csv(os.path.join(table_dir, "cluster_stability_check.csv"), index=False, encoding="utf-8-sig")

# work_hours 제외 민감도 분석
cluster_vars_no_hours = [
    "work_life_balance", "achievement", "work_meaning", "stress",
    "satisfaction", "job_loss_risk", "reemployment_possibility"
]
x_no_hours = youth_cluster_base[cluster_vars_no_hours].values
x_no_hours_scaled = StandardScaler().fit_transform(x_no_hours)
sensitivity_rows = []
for k in range(2, 7):
    km_no_hours = KMeans(n_clusters=k, random_state=random_state, n_init=20)
    labels_no_hours = km_no_hours.fit_predict(x_no_hours_scaled)
    sil_no_hours = silhouette_score(x_no_hours_scaled, labels_no_hours)
    sensitivity_rows.append({
        "k": k,
        "inertia": km_no_hours.inertia_,
        "silhouette": round(float(sil_no_hours), 4),
    })
sensitivity_kmeans_no_work_hours = pd.DataFrame(sensitivity_rows)
sensitivity_kmeans_no_work_hours.to_csv(os.path.join(table_dir, "sensitivity_kmeans_no_work_hours.csv"), index=False, encoding="utf-8-sig")
