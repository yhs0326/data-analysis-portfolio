import os
import shutil
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
base_dir = r"C:/kossda 공모전"
input_main = os.path.join(base_dir, "kwcs_model_data.csv")

# output 경로 설정
output_dir = os.path.join(base_dir, "output")
table_dir = os.path.join(output_dir, "tables")
fig_dir = os.path.join(output_dir, "figures")
model_dir = os.path.join(output_dir, "models")

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
# EDA
# ======================
summary_by_year_group = (
    df.groupby(["year", "age_group"], as_index=False)
      .agg(sample_n=("quality_of_work", "size"), mean_quality_of_work=("quality_of_work", "mean"))
)
summary_by_year_group["mean_quality_of_work"] = summary_by_year_group["mean_quality_of_work"].round(4)
summary_by_year_group.to_csv(os.path.join(table_dir, "summary_by_year_group_python.csv"), index=False, encoding="utf-8-sig")

indicator_summary = (
    df.groupby(["year", "age_group"], as_index=False)[quality_indicator_vars]
      .mean()
      .round(4)
)
indicator_summary.to_csv(os.path.join(table_dir, "indicator_summary_by_year_group_python.csv"), index=False, encoding="utf-8-sig")

youth_vs_middle = df.groupby("age_group")["quality_of_work"].mean().round(4)

youth_2017_2023 = (
    df[df["age_group"] == "youth"]
    .groupby("year")["quality_of_work"]
    .mean()
    .round(4)
)

summary_by_year_group_plot = summary_by_year_group.copy()
summary_by_year_group_plot["age_group_label"] = label_series(summary_by_year_group_plot["age_group"], age_group_label_map)
plt.figure(figsize=(8, 5))
sns.barplot(data=summary_by_year_group_plot, x="year", y="mean_quality_of_work", hue="age_group_label")
plt.title("연도·연령집단별 노동의 질 평균")
plt.xlabel("연도")
plt.ylabel("노동의 질 평균")
plt.legend(title="연령집단")
save_fig(os.path.join(fig_dir, "fig_quality_by_year_group.png"))

youth_indicator = (
    df[df["age_group"] == "youth"].groupby("year")[quality_indicator_vars].mean().reset_index()
)
youth_indicator_long = youth_indicator.melt(id_vars="year", var_name="indicator", value_name="mean_value")
youth_indicator_long_plot = youth_indicator_long.copy()
youth_indicator_long_plot["indicator_label"] = label_series(youth_indicator_long_plot["indicator"], presentation_label_map)
plt.figure(figsize=(12, 6))
sns.barplot(data=youth_indicator_long_plot, x="indicator_label", y="mean_value", hue="year")
plt.title("청년층(2017 vs 2023) 하위 지표 평균 비교")
plt.xlabel("하위 지표")
plt.ylabel("평균")
plt.legend(title="조사연도")
plt.xticks(rotation=30, ha="right")
save_fig(os.path.join(fig_dir, "fig_youth_indicator_change.png"))

df_plot = df.copy()
df_plot["age_group_label"] = label_series(df_plot["age_group"], age_group_label_map)
plt.figure(figsize=(7, 5))
sns.boxplot(data=df_plot, x="age_group_label", y="quality_of_work")
plt.title("연령집단별 노동의 질 분포")
plt.xlabel("연령집단")
plt.ylabel("노동의 질")
save_fig(os.path.join(fig_dir, "fig_quality_boxplot_age_group.png"))

trend = df.groupby(["year", "age_group"], as_index=False)["quality_of_work"].mean()
trend_plot = trend.copy()
trend_plot["age_group_label"] = label_series(trend_plot["age_group"], age_group_label_map)
plt.figure(figsize=(8, 5))
sns.lineplot(data=trend_plot, x="year", y="quality_of_work", hue="age_group_label", marker="o")
plt.title("연도별 청년·중장년 노동의 질 추이")
plt.xlabel("연도")
plt.ylabel("노동의 질 평균")
plt.legend(title="연령집단")
save_fig(os.path.join(fig_dir, "fig_quality_trend_gap.png"))

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

# ======================
# 회귀분석
# ======================

# 회귀분석 보조 함수 정의
def get_reference_info(data, variables):
    rows = []
    refs = {}
    for var in variables:
        categories = sorted(data[var].dropna().unique().tolist())
        if var == "year" and 2017 in categories:
            ref = 2017
        elif var == "age_group" and "middle_old" in categories:
            ref = "middle_old"
        else:
            ref = categories[0] if categories else np.nan
        refs[var] = ref
        rows.append({
            "variable": var,
            "categories_observed": ", ".join(map(str, categories)),
            "reference_category": ref,
        })
    return refs, pd.DataFrame(rows)


def c_term(var, refs):
    return f"C({var}, Treatment(reference={repr(refs[var])}))"


def model_fit_row(name, model):
    return {
        "model_name": name,
        "nobs": model.nobs,
        "df_model": model.df_model,
        "df_resid": model.df_resid,
        "AIC": model.aic,
        "BIC": model.bic,
        "R_squared": getattr(model, "rsquared", np.nan),
        "Adj_R_squared": getattr(model, "rsquared_adj", np.nan),
        "F_statistic": getattr(model, "fvalue", np.nan),
        "F_p_value": getattr(model, "f_pvalue", np.nan),
    }


def save_overall_f_test(model, model_name, filename):
    p_value = float(model.f_pvalue) if pd.notna(model.f_pvalue) else np.nan
    conclusion = "모형 전체가 통계적으로 유의함" if pd.notna(p_value) and p_value < 0.05 else "모형 전체가 통계적으로 유의하다고 보기 어려움"
    pd.DataFrame([{
        "model_name": model_name,
        "f_statistic": model.fvalue,
        "p_value": p_value,
        "df_model": model.df_model,
        "df_resid": model.df_resid,
        "conclusion_5pct": conclusion,
    }]).to_csv(os.path.join(table_dir, filename), index=False, encoding="utf-8-sig")


def save_nested_comparison(models, filename):
    try:
        sm.stats.anova_lm(*models).to_csv(os.path.join(table_dir, filename), encoding="utf-8-sig")
    except Exception as e:
        print(f"[경고] nested model 비교 실패: {e}")
        pd.DataFrame().to_csv(os.path.join(table_dir, filename), index=False, encoding="utf-8-sig")


def save_sst_table(model, filename):
    y = np.asarray(model.model.endog)
    fitted = np.asarray(model.fittedvalues)
    resid = np.asarray(model.resid)
    sst = float(np.sum((y - y.mean()) ** 2))
    ssr = float(np.sum((fitted - y.mean()) ** 2))
    sse = float(np.sum(resid ** 2))
    pd.DataFrame([{
        "SST": sst,
        "SSR": ssr,
        "SSE": sse,
        "R_squared_manual": ssr / sst if sst != 0 else np.nan,
        "SST_minus_SSR_minus_SSE": sst - ssr - sse,
    }]).to_csv(os.path.join(table_dir, filename), index=False, encoding="utf-8-sig")


def regression_coef_table(model, statistic_name="t_value"):
    names = getattr(model.model, "exog_names", None) or list(model.params.index)
    params = pd.Series(np.asarray(model.params), index=names)
    bse = pd.Series(np.asarray(model.bse), index=names)
    stat = pd.Series(np.asarray(getattr(model, "tvalues", np.nan)), index=names)
    pvalues = pd.Series(np.asarray(model.pvalues), index=names)
    conf = pd.DataFrame(np.asarray(model.conf_int()), index=names, columns=["conf_low", "conf_high"])
    return pd.DataFrame({
        "term": names,
        "coef": params.values,
        "std_err": bse.values,
        statistic_name: stat.values,
        "p_value": pvalues.values,
        "conf_low": conf["conf_low"].values,
        "conf_high": conf["conf_high"].values,
    })


def save_vif(model, filename):
    rows = []
    names = model.model.exog_names
    exog = model.model.exog
    for i, name in enumerate(names):
        if name.lower() in ["intercept", "const"]:
            continue
        try:
            vif = variance_inflation_factor(exog, i)
        except Exception:
            vif = np.nan
        rows.append({"variable": name, "VIF": vif})
    pd.DataFrame(rows).to_csv(os.path.join(table_dir, filename), index=False, encoding="utf-8-sig")


def save_ols_diagnostics(model, data, filename):
    rows = []
    try:
        jb_stat, jb_p, _, _ = jarque_bera(model.resid)
        rows.append({"test_name": "Jarque-Bera normality test", "statistic": jb_stat, "p_value": jb_p, "interpretation": "p<0.05이면 정규성 가정에 주의"})
    except Exception as e:
        print(f"[경고] Jarque-Bera 검정 실패: {e}")
    try:
        bp_stat, bp_p, _, _ = het_breuschpagan(model.resid, model.model.exog)
        rows.append({"test_name": "Breusch-Pagan heteroscedasticity test", "statistic": bp_stat, "p_value": bp_p, "interpretation": "p<0.05이면 이분산 가능성"})
    except Exception as e:
        print(f"[경고] Breusch-Pagan 검정 실패: {e}")
    try:
        dw_stat = durbin_watson(model.resid)
        rows.append({"test_name": "Durbin-Watson statistic", "statistic": dw_stat, "p_value": np.nan, "interpretation": "2에 가까울수록 자기상관이 약함"})
    except Exception as e:
        print(f"[경고] Durbin-Watson 계산 실패: {e}")
    try:
        reset = linear_reset(model, power=2, use_f=True)
        rows.append({"test_name": "Ramsey RESET test", "statistic": float(reset.fvalue), "p_value": float(reset.pvalue), "interpretation": "p<0.05이면 모형 설정 점검 필요"})
    except Exception as e:
        print(f"[경고] Ramsey RESET 검정 실패: {e}")
    pd.DataFrame(rows).to_csv(os.path.join(table_dir, filename), index=False, encoding="utf-8-sig")


def save_residual_plots(model, prefix):
    fitted = np.asarray(model.fittedvalues)
    resid = np.asarray(model.resid)
    try:
        plt.figure(figsize=(7, 5))
        sns.scatterplot(x=fitted, y=resid, s=25)
        plt.axhline(0, color="red", linestyle="--", linewidth=1)
        plt.title("잔차-적합값 진단 그림")
        plt.xlabel("적합값")
        plt.ylabel("잔차")
        save_fig(os.path.join(fig_dir, f"fig_ols_{prefix}_residuals_vs_fitted.png"))
    except Exception as e:
        print(f"[경고] residuals vs fitted 그림 저장 실패: {e}")
    try:
        sm.qqplot(resid, line="45", fit=True)
        plt.title("Q-Q 진단 그림")
        plt.xlabel("이론 분위수")
        plt.ylabel("표본 분위수")
        save_fig(os.path.join(fig_dir, f"fig_ols_{prefix}_qqplot.png"))
    except Exception as e:
        print(f"[경고] QQ plot 저장 실패: {e}")
    try:
        standardized_resid = model.get_influence().resid_studentized_internal
        plt.figure(figsize=(7, 5))
        sns.scatterplot(x=fitted, y=np.sqrt(np.abs(standardized_resid)), s=25)
        plt.title("Scale-Location 진단 그림")
        plt.xlabel("적합값")
        plt.ylabel("sqrt(|표준화 잔차|)")
        save_fig(os.path.join(fig_dir, f"fig_ols_{prefix}_scale_location.png"))
    except Exception as e:
        print(f"[경고] scale-location 그림 저장 실패: {e}")
    try:
        cooks = model.get_influence().cooks_distance[0]
        plt.figure(figsize=(8, 5))
        plt.stem(np.arange(len(cooks)), cooks, markerfmt=",", basefmt=" ")
        plt.title("Cook's Distance 진단 그림")
        plt.xlabel("관측치")
        plt.ylabel("Cook's Distance")
        save_fig(os.path.join(fig_dir, f"fig_ols_{prefix}_cooks_distance.png"))
    except Exception as e:
        print(f"[경고] Cook's distance 그림 저장 실패: {e}")


def save_influence_top20(model, data, filename):
    try:
        influence = model.get_influence()
        cooks = influence.cooks_distance[0]
        out = pd.DataFrame({
            "original_index": data.index,
            "cooks_distance": cooks,
            "standardized_residual": influence.resid_studentized_internal,
            "leverage": influence.hat_matrix_diag,
        }).sort_values("cooks_distance", ascending=False).head(20)
        out.to_csv(os.path.join(table_dir, filename), index=False, encoding="utf-8-sig")
    except Exception as e:
        print(f"[경고] 영향점 저장 실패: {e}")
        pd.DataFrame().to_csv(os.path.join(table_dir, filename), index=False, encoding="utf-8-sig")


def save_ols_bundle(data, formulas, names, prefix, result_filename, robust_filename, coef_fig, coef_title, top_n):
    # OLS 모형 적합
    null_model = smf.ols(formulas[0], data=data).fit()
    model_1 = smf.ols(formulas[1], data=data).fit()
    full_model = smf.ols(formulas[2], data=data).fit()

    with open(os.path.join(model_dir, f"regression_{'quality' if prefix == 'full' else 'youth_quality'}_summary.txt"), "w", encoding="utf-8") as f:
        f.write(full_model.summary().as_text())

    # 모형 적합도 비교표 저장
    fit_comparison = pd.DataFrame([
        model_fit_row(names[0], null_model),
        model_fit_row(names[1], model_1),
        model_fit_row(names[2], full_model),
    ])
    fit_comparison.to_csv(os.path.join(table_dir, f"ols_model_fit_comparison_{prefix}.csv"), index=False, encoding="utf-8-sig")

    # 전체 F검정 결과 저장
    save_overall_f_test(full_model, names[2], f"ols_overall_f_test_{prefix}.csv")

    # 부분 F검정 저장
    save_nested_comparison([null_model, model_1, full_model], f"ols_nested_model_comparison_{prefix}.csv")

    # SST, SSR, SSE 계산
    save_sst_table(full_model, f"ols_sst_ssr_sse_{prefix}.csv")

    # 계수표 저장
    coef = regression_coef_table(full_model, statistic_name="t_value")
    coef.to_csv(os.path.join(table_dir, result_filename), index=False, encoding="utf-8-sig")

    # HC3 결과 우선 사용
    robust_coef = coef.copy()
    try:
        robust_model = full_model.get_robustcov_results(cov_type="HC3")
        robust_coef = regression_coef_table(robust_model, statistic_name="t_value")
        robust_coef.to_csv(os.path.join(table_dir, robust_filename), index=False, encoding="utf-8-sig")
    except Exception as e:
        print(f"[경고] HC3 robust 표준오차 저장 실패: {e}")
        robust_coef.to_csv(os.path.join(table_dir, robust_filename), index=False, encoding="utf-8-sig")
    plot_coef(robust_coef, coef_title, os.path.join(fig_dir, coef_fig), top_n=top_n)

    # VIF 계산
    save_vif(full_model, f"vif_{prefix}_model.csv")

    # 잔차 진단검정 저장
    save_ols_diagnostics(full_model, data, f"ols_diagnostic_tests_{prefix}.csv")

    # 잔차 진단 그림 저장
    save_residual_plots(full_model, prefix)

    # 영향점 저장
    save_influence_top20(full_model, data, f"ols_influence_top20_{prefix}.csv")
    return full_model, coef, robust_coef


def logit_result_table(model):
    names = getattr(model.model, "exog_names", None) or list(model.params.index)
    params = pd.Series(np.asarray(model.params), index=names)
    bse = pd.Series(np.asarray(model.bse), index=names)
    zvalues = pd.Series(np.asarray(getattr(model, "tvalues", np.nan)), index=names)
    pvalues = pd.Series(np.asarray(model.pvalues), index=names)
    conf = pd.DataFrame(np.asarray(model.conf_int()), index=names, columns=["conf_low_logit", "conf_high_logit"])
    out = pd.DataFrame({
        "term": names,
        "coef": params.values,
        "std_err": bse.values,
        "z_value": zvalues.values,
        "p_value": pvalues.values,
        "conf_low_logit": conf["conf_low_logit"].values,
        "conf_high_logit": conf["conf_high_logit"].values,
    })
    out["odds_ratio"] = np.exp(out["coef"])
    out["odds_conf_low"] = np.exp(out["conf_low_logit"])
    out["odds_conf_high"] = np.exp(out["conf_high_logit"])
    return out


def find_term(table, include_tokens, value_col="coef"):
    mask = pd.Series(True, index=table.index)
    for token in include_tokens:
        mask &= table["term"].astype(str).str.contains(token, regex=False)
    matched = table[mask]
    if matched.empty:
        return np.nan, np.nan, "해당 term 없음"
    row = matched.iloc[0]
    return row.get(value_col, np.nan), row.get("p_value", np.nan), row["term"]


# 데이터 필터링
reg_vars = ["quality_of_work", "year", "age_group", "gender", "emp_type", "full_part", "income", "work_hours", "preferred_hours"]
reg_df = df[reg_vars].dropna().copy()
reg_df = reg_df[(reg_df["work_hours"] <= 112) & (reg_df["preferred_hours"] <= 112)]
reg_df = reg_df[(reg_df["income"] >= 0) & (reg_df["income"] <= 10000)]

reg_y = df[df["age_group"] == "youth"][["quality_of_work", "year", "gender", "emp_type", "full_part", "income", "work_hours", "preferred_hours"]].dropna().copy()
reg_y = reg_y[(reg_y["work_hours"] <= 112) & (reg_y["preferred_hours"] <= 112)]
reg_y = reg_y[(reg_y["income"] >= 0) & (reg_y["income"] <= 10000)]

# 기준범주 설정 및 기록
# age_group 기준범주 설정
full_refs, full_ref_table = get_reference_info(reg_df, ["year", "age_group", "gender", "emp_type", "full_part"])
youth_refs, youth_ref_table = get_reference_info(reg_y, ["year", "gender", "emp_type", "full_part"])
full_ref_table.to_csv(os.path.join(table_dir, "categorical_reference_full.csv"), index=False, encoding="utf-8-sig")
youth_ref_table.to_csv(os.path.join(table_dir, "categorical_reference_youth.csv"), index=False, encoding="utf-8-sig")

full_year = c_term("year", full_refs)
full_age_group = c_term("age_group", full_refs)
full_gender = c_term("gender", full_refs)
full_emp = c_term("emp_type", full_refs)
full_part = c_term("full_part", full_refs)
youth_year = c_term("year", youth_refs)
youth_gender = c_term("gender", youth_refs)
youth_emp = c_term("emp_type", youth_refs)
youth_part = c_term("full_part", youth_refs)

full_formulas = [
    "quality_of_work ~ 1",
    f"quality_of_work ~ {full_year} + {full_age_group} + {full_gender}",
    f"quality_of_work ~ {full_year} + {full_age_group} + {full_gender} + {full_emp} + {full_part} + income + work_hours + preferred_hours",
]
youth_formulas = [
    "quality_of_work ~ 1",
    f"quality_of_work ~ {youth_year} + {youth_gender}",
    f"quality_of_work ~ {youth_year} + {youth_gender} + {youth_emp} + {youth_part} + income + work_hours + preferred_hours",
]

# 전체 OLS 모형 적합
model_a, coef_a, robust_coef_a = save_ols_bundle(
    reg_df,
    full_formulas,
    ["Null model", "Model 1", "Full model"],
    "full",
    "regression_quality_results.csv",
    "regression_quality_results_robust_HC3.csv",
    "fig_regression_quality_coefficients.png",
    "회귀분석 A: 노동의 질 영향요인(전체)",
    25,
)

# 청년 OLS 모형 적합
model_b, coef_b, robust_coef_b = save_ols_bundle(
    reg_y,
    youth_formulas,
    ["Null model", "Model 1", "Full model"],
    "youth",
    "regression_youth_quality_results.csv",
    "regression_youth_quality_results_robust_HC3.csv",
    "fig_regression_youth_coefficients.png",
    "회귀분석 B: 노동의 질 영향요인(청년)",
    20,
)

# 취약군 [1, 4] 고정
requested_vuln_clusters = [1, 4]
existing_clusters = set(cluster_profile["cluster"].tolist())
missing_clusters = [c for c in requested_vuln_clusters if c not in existing_clusters]
if missing_clusters:
    raise ValueError("최종 취약군 [1, 4]가 현재 군집 결과에 존재하지 않습니다. final_k와 cluster_profile을 확인하세요.")
vuln_clusters = requested_vuln_clusters
vuln_rank = cluster_profile[["cluster", "cluster_label", "quality_of_work"]].copy()
vuln_rank["is_vulnerable_cluster"] = vuln_rank["cluster"].isin(vuln_clusters).astype(int)
# 취약군 이유 저장
vulnerable_reason_map = {
    1: "높은 성취감에도 불구하고 스트레스·고용불안·재취업 어려움",
    4: "낮은 만족도·낮은 노동의 질·저품질 노동 경험",
}
vuln_rank["vulnerable_reason"] = vuln_rank["cluster"].map(vulnerable_reason_map).fillna("비취약군")
vuln_rank.to_csv(os.path.join(table_dir, "vulnerable_cluster_definition.csv"), index=False, encoding="utf-8-sig")

logit_df = youth_cluster_base.copy()
logit_df["vulnerable"] = logit_df["cluster"].isin(vuln_clusters).astype(int)
logit_vars = ["vulnerable", "year", "gender", "emp_type", "full_part", "income", "work_hours", "preferred_hours"]
logit_df = logit_df[logit_vars].dropna().copy()
logit_df = logit_df[(logit_df["work_hours"] <= 112) & (logit_df["preferred_hours"] <= 112)]
logit_df = logit_df[(logit_df["income"] >= 0) & (logit_df["income"] <= 10000)]

vulnerable_distribution = logit_df["vulnerable"].value_counts(dropna=False).rename_axis("vulnerable").reset_index(name="n")
vulnerable_distribution["ratio"] = (vulnerable_distribution["n"] / vulnerable_distribution["n"].sum()).round(4)
vulnerable_distribution.to_csv(os.path.join(table_dir, "logit_vulnerable_distribution.csv"), index=False, encoding="utf-8-sig")

logit_refs, _ = get_reference_info(logit_df, ["year", "gender", "emp_type", "full_part"])
logit_year = c_term("year", logit_refs)
logit_gender = c_term("gender", logit_refs)
logit_emp = c_term("emp_type", logit_refs)
logit_part = c_term("full_part", logit_refs)
logit_formula = f"vulnerable ~ {logit_year} + {logit_gender} + {logit_emp} + {logit_part} + income + work_hours + preferred_hours"

# 로지스틱 회귀모형 적합
try:
    logit_null = smf.logit("vulnerable ~ 1", data=logit_df).fit(disp=False)
    logit_model = smf.logit(logit_formula, data=logit_df).fit(disp=False)
    with open(os.path.join(model_dir, "logit_vulnerable_summary.txt"), "w", encoding="utf-8") as f:
        f.write(logit_model.summary().as_text())

    # LR 검정 저장
    lr_stat = 2 * (logit_model.llf - logit_null.llf)
    df_diff = logit_model.df_model - logit_null.df_model
    lr_p = chi2.sf(lr_stat, df_diff)
    pd.DataFrame([{
        "ll_null": logit_null.llf,
        "ll_full": logit_model.llf,
        "lr_statistic": lr_stat,
        "df_diff": df_diff,
        "p_value": lr_p,
        "conclusion_5pct": "모형 전체가 통계적으로 유의함" if lr_p < 0.05 else "모형 전체가 통계적으로 유의하다고 보기 어려움",
    }]).to_csv(os.path.join(table_dir, "logit_likelihood_ratio_test.csv"), index=False, encoding="utf-8-sig")

    # 오즈비 결과 저장
    logit_res = logit_result_table(logit_model)
    logit_res.to_csv(os.path.join(table_dir, "logit_vulnerable_results.csv"), index=False, encoding="utf-8-sig")

    # robust 표준오차 저장
    try:
        logit_robust = smf.logit(logit_formula, data=logit_df).fit(disp=False, cov_type="HC1")
        logit_robust_res = logit_result_table(logit_robust)
        logit_robust_res.to_csv(os.path.join(table_dir, "logit_vulnerable_results_robust.csv"), index=False, encoding="utf-8-sig")
    except Exception as e:
        print(f"[경고] Logit robust 표준오차 저장 실패: {e}")

    # 평균한계효과 저장
    try:
        margeff = logit_model.get_margeff(at="overall")
        margeff.summary_frame().reset_index().rename(columns={"index": "term"}).to_csv(os.path.join(table_dir, "logit_marginal_effects.csv"), index=False, encoding="utf-8-sig")
    except Exception as e:
        print(f"[경고] 평균한계효과 저장 실패: {e}")

    # 로지스틱 성능지표 저장
    pred_prob = logit_model.predict(logit_df)
    pred_label = (pred_prob >= 0.5).astype(int)
    tn, fp, fn, tp = confusion_matrix(logit_df["vulnerable"], pred_label, labels=[0, 1]).ravel()
    auc = roc_auc_score(logit_df["vulnerable"], pred_prob) if logit_df["vulnerable"].nunique() == 2 else np.nan
    accuracy = accuracy_score(logit_df["vulnerable"], pred_label)
    pd.DataFrame([{
        "AUC": auc,
        "accuracy_threshold_0_5": accuracy,
        "TN": tn,
        "FP": fp,
        "FN": fn,
        "TP": tp,
    }]).to_csv(os.path.join(table_dir, "logit_model_performance.csv"), index=False, encoding="utf-8-sig")

    # ROC 곡선 저장
    if logit_df["vulnerable"].nunique() == 2:
        fpr, tpr, _ = roc_curve(logit_df["vulnerable"], pred_prob)
        plt.figure(figsize=(7, 5))
        plt.plot(fpr, tpr, label=f"AUC={auc:.3f}")
        plt.plot([0, 1], [0, 1], color="gray", linestyle="--")
        plt.title("취약 노동유형 로지스틱 회귀 ROC 곡선")
        plt.xlabel("거짓 양성 비율")
        plt.ylabel("참 양성 비율")
        plt.legend()
        save_fig(os.path.join(fig_dir, "fig_logit_vulnerable_roc_curve.png"))

    # Hosmer-Lemeshow 검정 저장
    try:
        hl_df = pd.DataFrame({"observed": logit_df["vulnerable"].values, "expected_prob": pred_prob})
        hl_df["decile"] = pd.qcut(hl_df["expected_prob"], q=10, duplicates="drop")
        cal = hl_df.groupby("decile", observed=False).agg(
            n=("observed", "size"),
            observed_events=("observed", "sum"),
            expected_events=("expected_prob", "sum"),
        ).reset_index()
        cal["observed_nonevents"] = cal["n"] - cal["observed_events"]
        cal["expected_nonevents"] = cal["n"] - cal["expected_events"]
        cal.to_csv(os.path.join(table_dir, "logit_calibration_deciles.csv"), index=False, encoding="utf-8-sig")
        hl_stat = np.sum(
            ((cal["observed_events"] - cal["expected_events"]) ** 2 / cal["expected_events"].replace(0, np.nan)) +
            ((cal["observed_nonevents"] - cal["expected_nonevents"]) ** 2 / cal["expected_nonevents"].replace(0, np.nan))
        )
        hl_groups = len(cal)
        hl_dfree = max(hl_groups - 2, 1)
        hl_p = chi2.sf(hl_stat, hl_dfree)
        pd.DataFrame([{
            "groups": hl_groups,
            "hl_statistic": hl_stat,
            "df": hl_dfree,
            "p_value": hl_p,
            "interpretation": "p<0.05이면 적합도 점검 필요",
        }]).to_csv(os.path.join(table_dir, "logit_hosmer_lemeshow_test.csv"), index=False, encoding="utf-8-sig")
    except Exception as e:
        print(f"[경고] Hosmer-Lemeshow 검정 실패: {e}")

except Exception as e:
    print(f"[경고] statsmodels Logit 수렴 문제: {e}")
    x_lr = pd.get_dummies(logit_df.drop(columns=["vulnerable"]), drop_first=True)
    y_lr = logit_df["vulnerable"]
    lr = LogisticRegression(random_state=random_state, max_iter=2000)
    lr.fit(x_lr, y_lr)
    coef = pd.Series(lr.coef_[0], index=x_lr.columns)
    logit_res = pd.DataFrame({
        "term": coef.index,
        "coef": coef.values,
        "std_err": np.nan,
        "z_value": np.nan,
        "p_value": np.nan,
        "conf_low_logit": np.nan,
        "conf_high_logit": np.nan,
        "odds_ratio": np.exp(coef.values),
        "odds_conf_low": np.nan,
        "odds_conf_high": np.nan,
    })
    with open(os.path.join(model_dir, "logit_vulnerable_summary.txt"), "w", encoding="utf-8") as f:
        f.write("statsmodels Logit failed; sklearn LogisticRegression fallback used.\n")
    logit_res.to_csv(os.path.join(table_dir, "logit_vulnerable_results.csv"), index=False, encoding="utf-8-sig")

# 오즈비 그림 저장
plot_or = logit_res[(logit_res["term"] != "Intercept") & logit_res["odds_ratio"].notna()].copy()
plot_or = plot_or.sort_values("odds_ratio")
plot_or["term_label"] = plot_or["term"].map(regression_term_to_korean)
plt.figure(figsize=(10, max(5, len(plot_or) * 0.25)))
plt.scatter(plot_or["odds_ratio"], plot_or["term_label"])
if plot_or["odds_conf_low"].notna().any():
    for _, r in plot_or.iterrows():
        if pd.notna(r["odds_conf_low"]) and pd.notna(r["odds_conf_high"]):
            plt.plot([r["odds_conf_low"], r["odds_conf_high"]], [r["term_label"], r["term_label"]], color="gray")
plt.axvline(1, color="red", linestyle="--", linewidth=1)
plt.title("취약 노동유형 관련 요인: 로지스틱 회귀 오즈비")
plt.xlabel("오즈비")
plt.ylabel("변수")
save_fig(os.path.join(fig_dir, "fig_logit_vulnerable_odds_ratio.png"))

# 핵심 결과 요약 저장
key_rows = []
for section, key_item, table, tokens, value_col, se_type, interpretation_text in [
    ("full_ols", "전체 OLS에서 청년 여부 효과", robust_coef_a, ["age_group", "youth"], "coef", "HC3", "중장년 기준 청년의 노동의 질 차이"),
    ("full_ols", "전체 OLS에서 C(year)의 2023 효과", robust_coef_a, ["year", "2023"], "coef", "HC3", "2023년 효과"),
    ("youth_ols", "청년 OLS에서 C(year)의 2023 효과", robust_coef_b, ["year", "2023"], "coef", "HC3", "청년 표본의 2023년 효과"),
    ("youth_ols", "청년 OLS에서 work_hours 효과", robust_coef_b, ["work_hours"], "coef", "HC3", "청년 표본의 근로시간 효과"),
    ("youth_ols", "청년 OLS에서 income 효과", robust_coef_b, ["income"], "coef", "HC3", "청년 표본의 소득 효과"),
    ("logit", "Logit에서 C(year)의 2023 오즈비", logit_res, ["year", "2023"], "odds_ratio", "MLE", "2023년 취약유형 오즈비"),
    ("logit", "Logit에서 work_hours 오즈비", logit_res, ["work_hours"], "odds_ratio", "MLE", "근로시간 취약유형 오즈비"),
    ("logit", "Logit에서 full_part 관련 주요 더미변수 오즈비", logit_res, ["full_part"], "odds_ratio", "MLE", "전일제/시간제 관련 오즈비"),
    ("logit", "Logit에서 emp_type 관련 주요 더미변수 오즈비", logit_res, ["emp_type"], "odds_ratio", "MLE", "고용형태 관련 오즈비"),
]:
    estimate, p_value, term = find_term(table, tokens, value_col=value_col)
    key_rows.append({
        "section": section,
        "key_item": key_item,
        "estimate": estimate,
        "p_value": p_value,
        "se_type": se_type,
        "interpretation": interpretation_text if term != "해당 term 없음" else "해당 term 없음",
    })
regression_key_findings_summary = pd.DataFrame(key_rows)
regression_key_findings_summary.to_csv(os.path.join(table_dir, "regression_key_findings_summary.csv"), index=False, encoding="utf-8-sig")

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
