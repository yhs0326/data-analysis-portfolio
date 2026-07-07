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
