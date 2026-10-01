# SAS to CSV

[![tests](https://github.com/vincal848/SAS_to_CSV/actions/workflows/tests.yml/badge.svg)](https://github.com/vincal848/SAS_to_CSV/actions/workflows/tests.yml)

This project came out of needing to turn whitespace SAS text exports (CRSP, USAR,
USRR dumps where a row can come in short or long depending on what SAS decided to
print that cycle) into CSVs without a per-file manual check of column counts. The
first version called `read.table(fill = TRUE)` and `parLapply` on a cluster opened
once at the top of the script, and never got past being a one-off: it referenced
`a_files`/`b_files`/`c_files`, which it never defined.

I have since rebuilt it. **The undefined variables were the easy bug to find; the
one that mattered was that `fill = TRUE` pads every row up to the widest row in the
file before you ever see it, so a short row and a correct row both come out looking
the same width.** The rebuild counts fields per line itself and reports how many
rows it had to pad or truncate, instead of fixing them silently. Parallelism also
turned out to scale worse than I expected on one machine, which is in
[Results](#results) below.

## At a glance

| | |
|---|---|
| **Methods** | Per-line field counting, padded/truncated to a declared column schema; optional `.sas7bdat` input via `haven::read_sas`; chunked `data.table::fwrite` output; PSOCK cluster for `cores > 1` |
| **Inputs** | Whitespace-delimited SAS text exports (a directory + filename regex) or `.sas7bdat` files, plus a column-name vector |
| **Outputs** | One CSV, written incrementally per file; a summary of files/rows read and rows padded/truncated |
| **Validation** | 34 tests: pad/truncate counts, column naming, multi-file order with a source-file column, serial vs. 2-core parallel equality, CSV round-trip, clear error on no matches, `.sas7bdat` column coercion |
| **Headline result** | Parallel speedup plateaus fast: 1.53x at 2 workers, 2.58x at 19, on 800k rows across 40 files |
| **Stack** | R, data.table, parallel, haven, testthat |

## Results

Numbers below are from [`bench.R`](bench.R) run on one machine (Windows, 20 logical
cores reported by `detectCores()`), generating 40 synthetic CRSP-like files of
20,000 rows each (800,000 rows total) and timing `convert_files()` end to end,
output CSV included:

| Cores | Time | Speedup vs. serial |
|---|---|---|
| 1 | 5.57 s | 1.00x |
| 2 | 3.65 s | 1.53x |
| 19 | 2.16 s | 2.58x |

Going from 2 workers to 19 only buys another ~1.7x. Reading and field-splitting a
text file is not CPU-heavy, so most of the wall-clock time is per-worker process
startup and the serialized round-trip of each file's data.frame back to the main
process; adding workers past a handful mostly adds that overhead back. These are
single-run, single-machine timings, not an average over repeated runs.

## What was wrong

**The core defect was silent column fixing, not missing variables.** `fill = TRUE`
in `read.table()` pads every row in a file up to that file's own widest row before
`process_file_set()` ever compares it to the expected column count, so a file with
one 5-field row and one 2-field row reports 5 columns for every row, and nothing
downstream can tell which row was actually short. `read_irregular()` counts fields
per line before padding anything, and returns the pad/truncate counts as attributes
(`test-read_irregular.R`, "short rows are padded with NA and the pad count is
reported" / "long rows are truncated...").

**The script could not run as written.** It defines `crsp_files`, `usar_files`,
`usrr_files`, then calls `process_file_parallel()` on `a_files`/`b_files`/`c_files`,
which do not exist anywhere in the file.

**The cluster was opened once at the top level and never guaranteed to close.**
`cl <- makeCluster(num_cores)` runs before any work happens and `stopCluster(cl)` is
the last line of the script, so an error partway through any of the three
`process_file_parallel()` calls leaves the cluster running. `convert_files()` opens
its cluster inside the call and closes it with `on.exit()`.

**`detectCores() - 1` can be zero**, and `makeCluster(0)` errors, on a single-core
CI runner or VM. `convert_files()` uses `cores = max(1, cores)` and only opens a
cluster when `cores > 1`; `test-convert_files.R`'s "cores = 2 produces the same
result as cores = 1" exercises both paths against the same input.

**One `do.call(rbind, data_list)` built the entire combined table in memory before
the single `write.csv()` call.** `convert_files()` writes each file's chunk via
`data.table::fwrite(..., append = TRUE)` as it is produced, checked by "the written
CSV round-trips to the same data."

**The `library(parallel)` comment says `install.packages(parallel)` if needed** —
`parallel` ships with base R and has never been on CRAN.

## How it works

`read_irregular()` reads one file, splits each line on whitespace (or a given
separator), pads/truncates every row to the declared column count, and attaches
`n_padded`/`n_truncated` attributes. `convert_files()` lists files in a directory by
regex, applies `read_irregular()` to each (serially, or across a PSOCK cluster when
`cores > 1`), tags each chunk with a `source_file` column, writes each chunk to the
output CSV as it is produced, and returns a summary (plus the combined data.frame if
`return_data = TRUE`). `convert_cli.R` is a thin `commandArgs()` wrapper around
`convert_files()`.

## Decisions

- Field counts are computed from the raw lines with `strsplit()`, not inferred from
  `read.table()`'s own column count, because `read.table(fill = TRUE)` already
  erases the information this repository exists to report.
- The parallel worker function (`.read_one_file()`) takes every setting as an
  explicit argument and is defined at the top level of `R/convert.R`, rather than as
  a closure nested inside `convert_files()`. A nested closure's enclosing frame also
  holds the cluster object itself, and shipping that frame to workers by relying on
  R's lexical scoping across processes failed intermittently under PSOCK
  serialization during testing; passing arguments explicitly through `parLapply(...)`
  removed the problem entirely.
- Output is written one file's chunk at a time via `data.table::fwrite(append =
  TRUE)` instead of one `rbind()` plus one `write.csv()`, so memory use does not
  scale with the whole file set.
- `.sas7bdat` support is read-only and goes through `haven::read_sas()`, kept in
  `Suggests` so the text-file path has no dependency on it; sas7bdat tests
  `skip_if_not_installed("haven")`.
- No `optparse` dependency for `convert_cli.R`: five flags do not need an argument
  parsing library.

## Quick start

```bash
# Install dependencies (adjust repos= if you use a different CRAN mirror)
Rscript -e 'install.packages(c("data.table", "haven", "testthat", "withr"), repos="https://cloud.r-project.org")'

# Convert a directory of files
Rscript convert_cli.R --dir data/crsp --pattern "^crsp_.*\.txt$" \
  --cols permno,date,ret,prc,vol --out crsp.csv --cores 2

# Run the tests
Rscript -e 'testthat::test_dir("tests/testthat")'

# Run the benchmark
Rscript bench.R 40 20000
```

## Repository guide

| Path | Contents |
|---|---|
| `R/convert.R` | `read_irregular()`, `convert_files()`, `.read_one_file()` |
| `convert_cli.R` | Command-line wrapper around `convert_files()` |
| `bench.R` | Generates synthetic CRSP-like files and times serial vs. parallel `convert_files()` |
| `tests/testthat/` | 34 tests: padding, truncation, column naming, file ordering, serial/parallel equality, CSV round-trip, errors, `.sas7bdat` |
| `legacy/simple_conversion.R` | Original script, annotated with the defects above and the tests that pin each fix |
| `DESCRIPTION` | Dependency declarations for CI (`r-lib/actions/setup-r-dependencies`) |

## Future interests

- Column-type hints (right now every column round-trips through
  `utils::type.convert`'s guesses) for files where that guess is wrong.
- Streaming line-by-line parsing for files too large to fit as a character vector
  in memory, rather than reading each whole file with `readLines()`.
- A real R package layout (`NAMESPACE`, roxygen docs) if this grows past a couple of
  functions.

## Notes

- All timings are single-machine, single-run, and specific to one Windows box; they
  are not a general claim about how `parallel` scales on other hardware.
- `read_irregular()` assumes one record per line; it does not handle multi-line
  records or embedded separators inside quoted fields.
- `.sas7bdat` support is read-only; there is no writer.
