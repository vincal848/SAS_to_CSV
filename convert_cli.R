# Command-line entry point.
#
#   Rscript convert_cli.R --dir data/crsp --pattern "^crsp.*\\.txt$" \
#     --cols permno,date,ret,prc --out crsp.csv --cores 2
#
# Base commandArgs() parsing only -- the flag set is small and fixed, so
# optparse would be a dependency for five lines of logic.

parse_args <- function(args) {
  opts <- list()
  i <- 1
  while (i <= length(args)) {
    key <- args[[i]]
    if (!startsWith(key, "--")) {
      stop(sprintf("Unexpected argument '%s'; expected --flag value.", key))
    }
    if (i == length(args)) {
      stop(sprintf("Missing value for '%s'.", key))
    }
    opts[[sub("^--", "", key)]] <- args[[i + 1]]
    i <- i + 2
  }
  opts
}

main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  opts <- parse_args(args)

  required <- c("dir", "pattern", "cols", "out")
  missing <- setdiff(required, names(opts))
  if (length(missing) > 0) {
    stop(sprintf(
      "Missing required argument(s): %s",
      paste0("--", missing, collapse = ", ")
    ))
  }

  this_file <- sub("^--file=", "", grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
  script_dir <- if (length(this_file) > 0) dirname(normalizePath(this_file)) else "."
  source(file.path(script_dir, "R", "convert.R"))

  cores <- if (is.null(opts$cores)) 1L else as.integer(opts$cores)

  result <- convert_files(
    dir = opts$dir,
    pattern = opts$pattern,
    col_names = strsplit(opts$cols, ",")[[1]],
    out = opts$out,
    cores = cores
  )

  cat(sprintf(
    "Wrote %d row(s) from %d file(s) to %s (%d padded, %d truncated).\n",
    result$n_rows, result$n_files, result$out, result$n_padded, result$n_truncated
  ))
}

main()
