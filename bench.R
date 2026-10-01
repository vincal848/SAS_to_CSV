# Generates synthetic CRSP-like whitespace text files and times
# convert_files() serially against a few worker counts. Numbers in the
# README come from running this script on one machine; they are not a
# general claim about parallel speedup.
#
# Usage: Rscript bench.R [n_files] [rows_per_file]

source(file.path("R", "convert.R"))

args <- commandArgs(trailingOnly = TRUE)
n_files <- if (length(args) >= 1) as.integer(args[[1]]) else 40
rows_per_file <- if (length(args) >= 2) as.integer(args[[2]]) else 20000

col_names <- c("permno", "date", "ret", "prc", "vol")

make_fixture_dir <- function(n_files, rows_per_file) {
  dir <- tempfile("crsp_bench_")
  dir.create(dir)
  for (i in seq_len(n_files)) {
    permno <- sample(10000:99999, rows_per_file, replace = TRUE)
    date <- sample(19800101:20231231, rows_per_file, replace = TRUE)
    ret <- round(rnorm(rows_per_file, 0, 0.02), 6)
    prc <- round(runif(rows_per_file, 1, 500), 2)
    vol <- sample(100:1e6, rows_per_file, replace = TRUE)
    lines <- sprintf("%d %d %f %f %d", permno, date, ret, prc, vol)
    writeLines(lines, file.path(dir, sprintf("crsp_%03d.txt", i)))
  }
  dir
}

cat(sprintf(
  "Generating %d files x %d rows (%s total rows)...\n",
  n_files, rows_per_file, format(n_files * rows_per_file, big.mark = ",")
))
dir <- make_fixture_dir(n_files, rows_per_file)
out <- tempfile(fileext = ".csv")

run_once <- function(cores) {
  t0 <- Sys.time()
  convert_files(
    dir = dir, pattern = "^crsp_.*\\.txt$", col_names = col_names,
    out = out, cores = cores
  )
  as.numeric(Sys.time() - t0, units = "secs")
}

max_cores <- parallel::detectCores()
core_counts <- unique(c(1, 2, max(1, max_cores - 1)))

cat(sprintf("detectCores() = %d\n\n", max_cores))
for (cores in core_counts) {
  elapsed <- run_once(cores)
  cat(sprintf("cores = %d: %.2f s\n", cores, elapsed))
}

unlink(dir, recursive = TRUE)
unlink(out)
