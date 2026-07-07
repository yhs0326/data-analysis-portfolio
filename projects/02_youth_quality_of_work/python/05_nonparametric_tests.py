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
