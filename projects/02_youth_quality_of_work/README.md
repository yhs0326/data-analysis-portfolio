# Youth Quality of Work Analysis

KWCS 2017·2023 데이터를 활용해 청년 노동의 질 지수를 구성하고, 청년 노동의 질 변화와 취약 노동유형을 분석한 프로젝트입니다.

> 핵심 결론: **2017년 대비 2023년에 청년 노동의 질은 3.23에서 3.13로 하락했으며, 청년 취업자 중 33.17%가 취약 노동유형에 속했습니다.**  
> 청년 고용 문제는 단순히 취업 여부가 아니라, 취업 이후 어떤 노동 경험을 하는가의 문제로 볼 필요가 있습니다.

---

## 1. Project Overview

- **분석 주제**: 청년 고용 문제는 취업 여부가 아니라 노동의 질 문제인가?
- **분석 데이터**: KWCS 2017·2023 한국근로환경조사
- **분석 대상**: 취업자 표본, 청년·중장년 비교
- **분석 단위**: 개인 단위 근로환경 응답 자료
- **핵심 지표**: 노동의 질 지수(`quality_of_work`)
- **주요 분석 방법**: KMeans 군집분석, OLS 회귀분석, 로지스틱 회귀분석, 비모수 검정

이 프로젝트는 청년 고용 문제를 취업률이나 실업률만으로 보지 않고, **취업 이후의 노동 경험**을 데이터로 측정하고자 했습니다.  
이를 위해 7개 하위지표를 평균하여 노동의 질 지수를 만들고, 청년 취업자를 5개 노동유형으로 군집화한 뒤, 취약 노동유형과 관련된 조건을 분석했습니다.

---

## 2. Key Findings

| 구분 | 결과 | 해석 |
|---|---:|---|
| 2017년 청년 노동의 질 | 3.23 | 기준 시점 청년 노동의 질 평균 |
| 2023년 청년 노동의 질 | 3.13 | 2017년 대비 하락 |
| 청년 노동의 질 변화율 | -3.0% | 2023년에 청년 노동의 질 저하 관찰 |
| 중장년 노동의 질 변화 | 3.1817 → 3.1827 | 거의 변화 없음 |
| 취약 노동유형 비중 | 33.17% | 청년 취업자 중 약 1/3 |
| 도출된 노동유형 | 5개 | 청년 내부 노동 경험의 이질성 확인 |

청년 노동의 질 하락은 모든 하위지표에서 동일하게 나타난 것이 아니라, 특히 **고용안정성**과 **재취업 가능성**에서 두드러졌습니다.

| 하위지표 | 변화 | 해석 |
|---|---:|---|
| 고용안정성 | -14.7% | 실직 위험 관련 안정성 약화 |
| 재취업 가능성 | -4.5% | 미래 노동시장 이동 가능성 약화 |
| 만족도 | +1.6% | 전반 만족도는 소폭 상승 |
| 스트레스 낮음 | -1.2% | 스트레스 측면은 소폭 악화 |

따라서 2023년 청년 노동의 질 하락은 단순한 만족도 문제가 아니라, **미래 안정성 축의 약화**와 관련이 있다고 해석했습니다.

---

## 3. Methodology

### 3.1 Quality of Work Index

노동의 질 지수는 7개 하위지표의 평균으로 구성했습니다. 모든 지표는 값이 높을수록 긍정적인 노동 경험을 의미하도록 정리했습니다.

| 하위지표 | 의미 |
|---|---|
| 일·생활 균형 | 업무와 개인생활의 균형 정도 |
| 성취감 | 업무 수행에서의 성취 경험 |
| 일의 의미 | 업무가 가치 있고 의미 있다는 인식 |
| 스트레스 낮음 | 값이 높을수록 스트레스가 낮음 |
| 만족도 | 현재 일에 대한 전반적 만족 |
| 고용안정성 | 값이 높을수록 실직 위험이 낮음 |
| 재취업 가능성 | 실직 시 재취업 가능성 |

```text
노동의 질 지수 = 7개 하위지표 평균
```

### 3.2 KMeans Clustering

청년 취업자 표본을 대상으로 근로시간과 노동의 질 하위지표를 활용해 KMeans 군집분석을 수행했습니다.

| 노동유형 | 비중 | 해석 |
|---|---:|---|
| 저성취·저의미형 | 20.95% | 성취감과 일의 의미가 낮은 유형 |
| 의미추구·불안정형 | 18.94% | 일의 의미는 높지만 안정성과 재취업 가능성이 낮은 유형 |
| 장시간·불균형형 | 13.84% | 근로시간이 길고 일·생활 균형이 낮은 유형 |
| 고품질·안정형 | 32.97% | 대부분의 노동의 질 지표가 높은 유형 |
| 저만족·저품질형 | 13.30% | 만족도와 전반적 노동의 질이 낮은 유형 |

이 중 **의미추구·불안정형**과 **저만족·저품질형**을 취약 노동유형으로 정의했습니다.  
이 정의는 외부 정답 라벨이 아니라, 군집 프로파일 해석을 바탕으로 만든 **조작적 정의**입니다.

### 3.3 OLS Regression

청년 표본을 대상으로 노동의 질과 관련된 요인을 OLS 회귀분석으로 확인했습니다. 이분산 가능성을 고려해 HC3 robust 표준오차를 사용했습니다.

| 변수 | 계수 | 해석 |
|---|---:|---|
| 2023년 | -0.1025 | 2017년 대비 청년 노동의 질이 낮게 나타남 |
| 임시직 | -0.0971 | 상용직 대비 노동의 질이 낮게 나타남 |
| 일용직 | -0.1041 | 상용직 대비 노동의 질이 낮게 나타남 |
| 근로시간 | -0.0051 | 근로시간이 길수록 노동의 질이 낮게 나타남 |

### 3.4 Logistic Regression

취약 노동유형 여부를 종속변수로 두고, 취약 유형에 속할 가능성과 관련된 조건을 로지스틱 회귀분석으로 확인했습니다.

| 변수 | Odds Ratio | 해석 |
|---|---:|---|
| 2023년 | 1.814 | 2017년 대비 취약 노동유형과 양의 관련 |
| 임시직 | 1.631 | 상용직 대비 취약 노동유형과 양의 관련 |
| 일용직 | 1.718 | 상용직 대비 취약 노동유형과 양의 관련 |

분석 결과는 인과효과가 아니라, 취약 노동유형과 관련된 조건을 설명하는 목적으로 해석했습니다.

### 3.5 Nonparametric Tests

근로환경조사 변수는 순서형 척도 성격이 강하므로, 평균 비교를 보조하기 위해 비모수 검정을 함께 수행했습니다.

| 검정 | 목적 |
|---|---|
| Mann-Whitney U test | 2017년과 2023년 청년 노동의 질 차이 검정 |
| Mann-Whitney U test | 청년층과 중장년층 노동의 질 차이 검정 |
| Kruskal-Wallis test | 청년 노동유형별 노동의 질 차이 검정 |

---

## 4. Repository Structure

```text
02_youth_quality_of_work/
├── README.md
├── data/
│   └── README.md
├── outputs/
│   └── figures/
├── python/
│   ├── 00_full_analysis_pipeline.py
│   ├── 01_setup_and_eda.py
│   ├── 02_clustering_analysis.py
│   ├── 03_ols_regression.py
│   ├── 04_logistic_vulnerable_group.py
│   └── 05_nonparametric_tests.py
├── r/
│   ├── 00_full_preprocessing_pipeline.R
│   ├── 01_macro_indicators_eda.R
│   ├── 02_load_and_select_kwcs_variables.R
│   ├── 03_clean_2023_kwcs.R
│   └── 04_clean_2017_kwcs.R
└── sql/
    ├── 00_full_data_mart_pipeline.sql
    ├── 01_create_clean_tables.sql
    ├── 02_merge_and_create_model_data.sql
    ├── 03_summary_queries.sql
    └── 04_validation_checks.sql
```

> `00_full_*` 파일은 실제 분석 과정에서 사용한 전체 파이프라인을 보존한 파일입니다.
>
> 번호가 붙은 파일들은 포트폴리오 가독성을 위해 분석 단계별로 분리한 파일입니다. 일부 단계별 파일은 이전 단계에서 생성된 중간 객체나 테이블을 전제로 합니다.
>
> 원본 데이터는 제공처 이용 조건상 저장소에 포함하지 않았습니다. 데이터 접근이 가능한 환경에서는 `data/` 폴더에 동일한 파일명으로 데이터를 배치한 뒤 코드를 실행할 수 있습니다.

---

## 5. Main Files

| 파일 | 역할 |
|---|---|
| `r/00_full_preprocessing_pipeline.R` | R 전처리 전체 흐름 보존 |
| `r/01_macro_indicators_eda.R` | 청년 고용 관련 보조지표 EDA |
| `r/02_load_and_select_kwcs_variables.R` | KWCS 2017·2023 원자료 로딩, 변수 선택, 변수명 정리 |
| `r/03_clean_2023_kwcs.R` | 2023년 KWCS 결측 처리, 역코딩, 노동의 질 지표 생성 |
| `r/04_clean_2017_kwcs.R` | 2017년 KWCS 결측 처리, 역코딩, 노동의 질 지표 생성 |
| `sql/00_full_data_mart_pipeline.sql` | SQL 데이터마트 구축 전체 흐름 보존 |
| `sql/01_create_clean_tables.sql` | 2017·2023 clean table 생성 |
| `sql/02_merge_and_create_model_data.sql` | 2017·2023 데이터 결합 및 Python 분석용 테이블 생성 |
| `sql/03_summary_queries.sql` | 연도·연령집단별 표본 수, 노동의 질 평균, 하위지표 요약 |
| `sql/04_validation_checks.sql` | 연도, 연령집단, 점수 범위, 결측, 이상치 등 검증 쿼리 |
| `python/00_full_analysis_pipeline.py` | Python 분석 전체 파이프라인 보존 |
| `python/01_setup_and_eda.py` | 경로 설정, 변수 정의, 라벨 맵, 데이터 로딩, EDA |
| `python/02_clustering_analysis.py` | KMeans 군집분석, 실루엣, 군집 프로파일, z-score heatmap, PCA, 안정성 검토 |
| `python/03_ols_regression.py` | 전체·청년 OLS 회귀, HC3 robust 표준오차, VIF, 잔차 진단 |
| `python/04_logistic_vulnerable_group.py` | 취약 노동유형 정의, 로지스틱 회귀, 오즈비, ROC, 적합도 검토 |
| `python/05_nonparametric_tests.py` | Mann-Whitney U 검정, Kruskal-Wallis 검정 |
| `data/README.md` | 원자료 비공개 사유 및 데이터 배치 안내 |

---

## 6. Execution Flow

이 프로젝트의 분석 흐름은 다음과 같습니다.

```text
R preprocessing → SQL data integration → Python analysis → PDF/report output
```

1. **R preprocessing**  
   KWCS 원자료에서 필요한 변수를 선택하고, 결측 처리와 역코딩을 수행한 뒤 노동의 질 지표를 생성했습니다.

2. **SQL data integration**  
   2017년과 2023년 데이터를 결합하고, Python 분석에 사용할 `kwcs_model_data` 형태의 분석용 테이블을 구성했습니다.

3. **Python analysis**  
   EDA, KMeans 군집분석, OLS 회귀분석, 로지스틱 회귀분석, 비모수 검정을 수행하고 결과 표와 그림을 저장했습니다.

---

## 7. Tech Stack

| 구분 | 사용 도구 |
|---|---|
| Data Preprocessing | R, tidyverse, haven |
| Data Mart / Query | PostgreSQL, SQL |
| Analysis / Modeling | Python, pandas, scikit-learn, statsmodels, scipy |
| Clustering | KMeans, silhouette score, PCA |
| Regression | OLS, HC3 robust standard errors, Logistic Regression |
| Statistical Test | Mann-Whitney U test, Kruskal-Wallis test |
| Visualization | matplotlib, seaborn |
| Portfolio Output | GitHub, PDF |

---

## 8. Limitations and Extensions

### Limitations

- KWCS 2017·2023의 두 시점 비교이므로 장기 시계열 추세로 일반화하기에는 한계가 있습니다.
- 노동의 질 지수는 7개 하위지표를 단순 평균한 조작적 지표입니다.
- KMeans 군집은 청년 노동 경험을 이해하기 위한 탐색적 유형화이며, 군집 자체가 객관적 정답 집단을 의미하지 않습니다.
- 취약 노동유형은 군집 프로파일 해석을 바탕으로 정의한 변수입니다.
- 회귀분석 결과는 인과관계가 아니라 노동의 질 및 취약 노동유형과 관련된 조건으로 해석해야 합니다.
- 원본 데이터는 제공처 이용 조건상 저장소에 포함하지 않았습니다.

### Extensions

- 직업군, 산업, 학력 등 추가 변수와 취약 노동유형의 관계 분석
- 청년 하위 연령대별 노동의 질 차이 비교
- 근로시간, 고용형태, 소득 구간별 세부 프로파일링
- 연도 추가 시 노동의 질 변화 추세 분석 확장
- Tableau 또는 BI 대시보드 기반 청년 노동의 질 모니터링 확장

---

## 9. Use Case

이 분석은 다음과 같은 방식으로 활용할 수 있습니다.

```text
청년 노동의 질 측정 → 취약 노동유형 식별 → 관련 요인 분석 → 유형별 대응 방향 설계
```

- 청년 고용 정책에서 취업률 외에 취업 이후 노동의 질 지표를 함께 모니터링
- 고용형태와 근로시간에 따른 노동 경험 차이 점검
- 청년 내부의 이질적 노동유형을 고려한 맞춤형 지원 방향 설계
- 조직 내 청년 구성원의 근로환경 진단 및 관리 지표 설계

---

## 10. Portfolio Positioning

이 프로젝트는 다음 역량을 보여주기 위한 포트폴리오입니다.

- 사회·고용 문제를 분석 가능한 지표로 정의하는 능력
- R을 활용한 원자료 전처리와 지표 생성
- SQL을 활용한 연도별 데이터 결합과 분석용 데이터마트 구축
- Python을 활용한 군집분석, 회귀분석, 비모수 검정 수행
- 결과를 정책적·실무적 인사이트로 연결하는 해석 능력

청년 노동의 질 분석은 특정 산업 데이터는 아니지만, **개인 단위 응답 데이터를 바탕으로 지표를 설계하고, 취약 집단을 식별한 뒤, 관련 요인을 분석했다는 점에서 HR Analytics, People Analytics, 공공데이터 분석, 리서치 데이터 분석 직무와 연결할 수 있습니다.**
