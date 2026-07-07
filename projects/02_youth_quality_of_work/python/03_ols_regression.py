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

