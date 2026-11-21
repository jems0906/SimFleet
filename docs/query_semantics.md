# SQL Analysis Semantics

Every analytics endpoint includes an explicit UTC time window and the number of runs represented. Run counts are `runs.completed_at >= start AND completed_at < end`; late results that arrive after a dashboard request are not retroactively counted until included by a later windowed query.

- **Pass rate:** completed run verdicts grouped by driver version and scenario category.
- **Metric distribution:** percentile_cont over all metric values for a version, metric, and window.
- **Regression:** paired scenarios in baseline and candidate versions. A pass-rate drop is reported when it is positive and the two-proportion z-score is at least 1.96.
- **Flaky:** repeated rows for the same scenario and seed within a version. A seed disagrees when distinct verdict outcomes are observed.
- **Failure breakdown:** failed verdict categories grouped by version.
- **Batch health:** batch state, linked variation completion, missing work, and failed run count.

Queries are fixtures tested with hand-calculated data. Repeated-run disagreement is determined by verdict outcomes, not by metric noise.
