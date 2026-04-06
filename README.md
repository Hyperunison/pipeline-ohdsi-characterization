# OHDSI Characterization Pipeline

Federated cohort characterization using the [OHDSI Characterization](https://github.com/OHDSI/Characterization) R package. Accepts a cohort from the Unison UCDM format, loads it into a local OMOP CDM database, and runs baseline feature extraction (demographics, conditions, drugs, procedures, measurements, observations, visits).

## Prerequisites

### 1. OMOP CDM database (PostgreSQL)

The target database must have:

| Schema | Contents |
|--------|----------|
| `cdm_schema` (e.g. `dev_rosetta`) | OMOP CDM clinical tables/views: `person`, `condition_occurrence`, `drug_exposure`, `procedure_occurrence`, `measurement`, `observation`, `visit_occurrence`, and vocabulary views (`concept`, `concept_ancestor`, `concept_relationship`, etc.) |
| `work_schema` (e.g. `temp`) | Writable schema for temporary cohort table; the DB user must have `CREATE`/`INSERT`/`DROP` rights here |

The pipeline **does not** require era tables (`condition_era`, `drug_era`) or `device_exposure`.

Vocabulary tables (`concept`, `concept_ancestor`, `concept_relationship`, `vocabulary`, `domain`, `concept_class`, `relationship`) can live in a separate schema as long as they are accessible from `cdm_schema` — the simplest approach is to expose them as views:

```sql
CREATE OR REPLACE VIEW dev_rosetta.concept          AS SELECT * FROM vocabulary.concept;
CREATE OR REPLACE VIEW dev_rosetta.concept_ancestor  AS SELECT * FROM vocabulary.concept_ancestor;
-- … etc.
```

### 2. Database user

A dedicated read-only user with write access to `work_schema`:

```sql
CREATE USER unison_runner WITH PASSWORD '…';
GRANT CONNECT ON DATABASE omop TO unison_runner;
GRANT USAGE  ON SCHEMA dev_rosetta TO unison_runner;
GRANT SELECT ON ALL TABLES IN SCHEMA dev_rosetta TO unison_runner;
GRANT USAGE, CREATE ON SCHEMA temp TO unison_runner;
GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES
      ON ALL TABLES IN SCHEMA temp TO unison_runner;
```

### 3. Docker image

Build the `characterization:latest` image from the repo root (requires internet access):

```bash
docker build --network=host \
  -t characterization:latest \
  -f vendor/pipelines/characterization/v0.1/Dockerfile .
```

The image is based on `entsupml/unison-runner-dqd-omop-5.4` and adds:
`ParallelLogger`, `duckdb`, `Andromeda`, `FeatureExtraction`, `Characterization`, and the PostgreSQL JDBC driver at `/jdbc`.

## Parameters

Defined in `params.yaml` (defaults) and `nextflow_schema.json` (UI schema).

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `dsn` | yes | — | SQLAlchemy DSN, e.g. `postgresql+psycopg2://user:pass@host:5432/db` |
| `cdm_schema` | yes | `public` | Schema containing OMOP CDM tables |
| `work_schema` | no | `cdm_schema` | Writable schema for the temporary cohort table |
| `target_ids` | no | `1` | Comma-separated cohort_definition_id values to characterize |
| `outcome_ids` | no | `` | Comma-separated outcome cohort IDs (enables time-to-event, dechallenge-rechallenge, risk factors, case series). Leave blank for baseline only. |
| `database_id` | no | `local` | Site identifier stamped on all result rows |
| `min_cell_count` | no | `0` | Suppress cells with fewer than N patients (0 = no suppression) |
| `threads` | no | `1` | Parallel threads for the R analysis |

### Example `var/params_characterization.yaml`

```yaml
dsn: "postgresql+psycopg2://unison_runner:password@db-host:5432/omop"
cdm_schema: "dev_rosetta"
work_schema: "temp"
target_ids: "1"
outcome_ids: ""
database_id: "my_site"
min_cell_count: 5
threads: 2
```

## Input data (UCDM)

The pipeline receives cohort members via the Unison UCDM format. Each row must include:

| Field | Description |
|-------|-------------|
| `participant_id` | Maps to `subject_id` in the cohort table |
| `cohort_definition_id` | Cohort ID (default: `1`) |
| `cohort_start_date` | ISO date `YYYY-MM-DD` |
| `cohort_end_date` | ISO date `YYYY-MM-DD` |

`main.py` converts the UCDM list into `cohort.csv` and uploads it to the database before the analysis runs.

### Example `var/ucdm_characterization.yaml`

```yaml
- participant_id: "12345"
  cohort_definition_id: "1"
  cohort_start_date: "2010-03-15"
  cohort_end_date: "2012-03-15"
- participant_id: "67890"
  cohort_definition_id: "1"
  cohort_start_date: "2011-07-01"
  cohort_end_date: "2013-07-01"
```

## Running locally

Use `pipeline.py` from the Runner root:

```bash
cd /home/ents/characterization/Runner

docker exec -ti unison-runner python pipeline.py \
  --pipeline vendor/pipelines/characterization/v0.1 \
  --ucdm     var/ucdm_characterization.yaml \
  --params   var/params_characterization.yaml \
  --run-name char-test-01
```

Nextflow execution logs appear in `.nextflow.log`; a full HTML execution report is written to `report.html` in the run working directory.

## Output

Results are written to `output/` and contain standard Characterization SQLite/CSV files:

| File | Contents |
|------|----------|
| `Results_*.zip` / `output/*.csv` | Characterization result tables |
| `covariateValue.csv` | Per-covariate prevalence/mean for each target cohort |
| `covariates.csv` | Covariate definitions (concept IDs, names, analysis IDs) |
| `cohortDetails.csv` | Cohort sizes and metadata |
| `timeToEvent*.csv` | Time-to-event distributions (only when `outcome_ids` set) |
| `dechallengeRechallenge*.csv` | Dechallenge/rechallenge analysis (only when `outcome_ids` set) |
| `riskFactor*.csv` | Risk factor analysis (only when `outcome_ids` set) |
| `caseSeries*.csv` | Case series analysis (only when `outcome_ids` set) |

All result files include a `database_id` column matching the `database_id` parameter, enabling multi-site result merging.

## Covered covariates

The pipeline extracts the following feature domains:

- **Demographics**: gender, age, age group, race, ethnicity, index year/month, prior/post observation time, time in cohort
- **Conditions**: any-time prior, long-term (365 d), short-term (30 d)
- **Drug exposures**: any-time prior, long-term, short-term
- **Procedures**: any-time prior, long-term, short-term
- **Measurements**: any-time prior, long-term, short-term
- **Observations**: any-time prior, long-term, short-term
- **Visit counts**: long-term, short-term

Era tables (`condition_era`, `drug_era`) and `device_exposure` are intentionally excluded because they are not required in minimal OMOP CDM deployments.

## Pipeline internals

```
UCDM list
   │
   ▼ main.py: _build_cohort_csv()
cohort.csv ──────────────────────────────────────────────────────┐
                                                                  │
   │ main.py: _build_r_script()                                   │
run_analysis.R                                                    │
   │                                                              │
   ▼ Nextflow: runCharacterization process (characterization:latest)
   1. Load cohort.csv → temp.char_input_cohort (via JDBC)
   2. Characterization::runCharacterizationAnalyses()
   3. DROP temp.char_input_cohort
   │
   ▼
output/   +   report.html
```
