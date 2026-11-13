# Replication Package

**Paper:** *Declaration Is Not Enough: Feature Toggle Expiration in Practice*  
**Author:** Xhevahire Tërnava (Télécom Paris)  

---

We study whether declaring when a feature toggle should expire keeps toggles from staying in the code past that point. We mined 2,659 toggles from four open-source systems, and then followed their deadlines over time. Declaring a deadline is not enough: in two systems, many toggles are overdue.

## quick start

```bash
pip install -r requirements.txt
(cd study/longitudinal && ./02-extract-snapshots.sh)  # once, about 5 minutes
cd study/notebooks
jupyter notebook 01-ft-all-analysis.ipynb      # run all cells, first snapshot (T0)
jupyter notebook 02-staleness-over-time.ipynb  # run all cells, over time up to T1
```

The first notebook reproduces the figures and Table 2 of Sections 4.1 and 4.2 at the first snapshot (T0) from the data in `study/data/`. It does not need the codebases. The second notebook reproduces the figure of the overdue share over time and Table 3 (Section 4.2). Its input comes from `study/longitudinal/02-extract-snapshots.sh`, which runs the same extraction scripts as at T0 on every downloaded point in time.

## what's inside

```
study/
├── data/          5 CSV files with all extracted toggle data at T0
├── scripts/       Shell scripts that produced those CSVs from source
├── notebooks/     Analysis notebooks, at T0 and over time (figures + tables)
├── longitudinal/  Scripts and downloaded files for the history up to T1
└── assets/        Generated figures used in the paper (PDF + PNG)
```

## subject systems

| System | Commit | Release | Toggles |
|--------|--------|---------|---------|
| [Chromium](https://chromium.googlesource.com/chromium/src/+/54e2a848c65e498cd112607e9133e9797d1e7fa8) | `54e2a84` | M145 | 1,896 |
| [GitLab](https://gitlab.com/gitlab-org/gitlab/-/commit/f3114f736b1e28230f1f8079a03e3c65896cb5b4) | `f3114f7` | v18.10 | 407 |
| [Kubernetes](https://github.com/kubernetes/kubernetes/commit/c180d6762d7ac5059d9b50457cafb0d7f4cf74a9) | `c180d67` | v1.36 | 211 |
| [Vespa](https://github.com/vespa-engine/vespa/commit/f2f0d37afd1d889e33a12f82fbf58809dbdef391) | `f2f0d37` | v8.620.35 | 145 |

## re-extracting from source (optional)

If you want to re-run the extraction step yourself, clone each system at the commit above into a `codebases/` directory, then:

```bash
cd study/scripts
./01-extract-feature-flags-chromium.sh
./01-extract-feature-flags-gitlab.sh
./01-extract-feature-flags-vespa.sh
./01-extract-feature-gates-kubernetes.sh
```

Requirements: `bash`, `jq`, `awk`. The codebases are large (~60 GB combined), so this step is optional as the CSVs are already provided.

## data files

| File | Contents |
|------|----------|
| `01-chromium-feature-flags.csv` | Flag name, expiry milestone, permanent status, owners |
| `01-gitlab-feature-flags.csv` | Flag name, introduction milestone, type (via directory path) |
| `01-kubernetes-feature-gates.csv` | Gate name, lifecycle stage, removal version, deprecation info |
| `01-vespa-feature-flags.csv` | Flag name, creation/expiry dates, owners, permanent status |
| `00-count-loc-all.csv` | Lines of code per language per project (from `cloc`) |

The last script may take a lot of time to compute the LoC for Chromium. 


<!-- ## corrections

While extending the scripts to the history, we found and fixed two errors. All numbers in the paper use the corrected data.

- Kubernetes: in comments such as "GA in 1.30, remove in 1.32", the extraction script took the first version (1.30) as the removal version. It now takes the version that follows "remove". This changes 11 gates, and the overdue gates at T0 drop from 10 to 1 of 50.
- GitLab: the notebook read the `milestone` field as a number, so 18.10 became 18.1 and 8 flags introduced in 18.10 were counted as overdue. It now reads the field as text. The overdue flags at T0 drop from 120 to 112 of 198.
-->

## license

Datasets and scripts are provided for research replication.  
Subject systems retain their original licenses.
