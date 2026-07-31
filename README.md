# Replication Package

**Paper:** *Declaration Is Not Enough: Feature Toggle Expiration in Practice*  
**Author:** Xhevahire Tërnava (Télécom Paris)  
**Venue:** ACM Transactions on Software Engineering and Methodology (TOSEM)

---

We study whether declaring expiration metadata on feature toggles actually prevents them from becoming stale. We mined 2,659 toggles from four open-source systems and found that declaration alone is insufficient, only automated enforcement achieves zero staleness.

## quick start

```bash
pip install -r requirements.txt
cd study/notebooks
jupyter notebook 01-ft-all-analysis.ipynb   # run all cells
```

This reproduces every figure and statistic in the paper from the pre-extracted data in `study/data/`.

## what's inside

```
study/
├── data/          5 CSV files with all extracted toggle data
├── scripts/       Shell scripts that produced those CSVs from source
├── notebooks/     Analysis notebook (figures + statistics)
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

## license

Datasets and scripts are provided for research replication.  
Subject systems retain their original licenses.
