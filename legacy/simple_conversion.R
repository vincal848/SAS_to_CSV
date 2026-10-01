# SUPERSEDED. Kept for reference only -- this file is not part of the
# package and is known to be incorrect. Do not source it.
#
# Known defects, each with a named regression test:
#
# 1. Defines crsp_files, usar_files, usrr_files, but calls
#    process_file_parallel() on a_files/b_files/c_files, which are never
#    defined anywhere. Running this script as written stops with
#    "object 'a_files' not found." No test exercises this file directly for
#    that reason; R/convert.R's convert_files() takes dir + pattern as
#    arguments instead of baking three hardcoded file-set globals into the
#    script, so there is nothing analogous left to get out of sync.
# 2. fill = TRUE in read.table() pads every row up to the widest row in that
#    one file, silently, before process_file_set() ever runs -- so a file
#    with one 2-field row and one 5-field row reports 5 columns for both,
#    and there is no way to tell afterwards which row was actually short.
#    test-read_irregular.R's "short rows are padded with NA and the pad
#    count is reported" and "...truncated..." tests pin the replacement,
#    read_irregular(), which counts fields per line itself and returns
#    n_padded/n_truncated as attributes instead of hiding the count.
# 3. cl <- makeCluster(num_cores) is opened once at the top level and reused
#    by every call to process_file_parallel(); if any one call errors the
#    cluster is left open with stopCluster(cl) never reached. R/convert.R's
#    convert_files() opens its own cluster per call and closes it with
#    on.exit(), tested implicitly by every convert_files() test running
#    without a leaked cluster or stale global state between tests.
# 4. num_cores <- detectCores() - 1 can evaluate to 0 on a single-core
#    runner, and makeCluster(0) errors. convert_files() uses
#    cores = max(1, cores) and only opens a cluster at all when cores > 1;
#    "cores = 2 produces the same result as cores = 1" in
#    test-convert_files.R checks the cores > 1 path still agrees with the
#    serial one.
# 5. The library(parallel) comment says "install.packages(parallel) if
#    needed," but parallel ships with base R and is never on CRAN.
# 6. process_file_parallel() calls do.call(rbind, data_list) to build one
#    combined data.frame in memory before a single write.csv() call, so
#    memory use is proportional to the whole file set rather than one file
#    at a time. convert_files() instead writes each file's chunk with
#    data.table::fwrite(..., append = TRUE) as it is produced; "the written
#    CSV round-trips to the same data" in test-convert_files.R checks the
#    chunked output still matches the in-memory result.
#
# The working implementation is R/convert.R (read_irregular(),
# convert_files()) and the CLI wrapper convert_cli.R.

library(parallel) # install.packages(parallel) if needed

data_directory <- "your/directory/here"


crsp_files <- list.files(path = data_directory, pattern = "^(patterned text here).*\\.txt$", full.names = TRUE)
usar_files <- list.files(path = data_directory, pattern = "^(patterned text here).*\\.txt$", full.names = TRUE)
usrr_files <- list.files(path = data_directory, pattern = "^(patterned text here).*\\.txt$", full.names = TRUE)


a_colnames <- c("several", "columns", "names", "here")

b_colnames <- c("several", "columns", "names", "here")

c_colnames <- c("several", "columns", "names", "here")


process_file_set <- function(file, colnames) {
  data <- read.table(
    file = file,
    sep = "",
    header = FALSE,
    stringsAsFactors = FALSE,
    fill = TRUE,
    strip.white = TRUE
  )

  actual_columns <- ncol(data)
  expected_columns <- length(colnames)


  if (actual_columns < expected_columns) {

    data <- cbind(data, matrix(NA, nrow = nrow(data), ncol = expected_columns - actual_columns))
    # Above adds additional columns if new columns begin to appear mid set.
  } else if (actual_columns > expected_columns) {

    data <- data[, 1:expected_columns]
  }
  colnames(data) <- colnames
  return(data)
}


num_cores <- detectCores() - 1  # Leave one core free


cl <- makeCluster(num_cores) # Opens cluster for processing

# Parallel function
process_file_parallel <- function(files, colnames, output_file) {

  data_list <- parLapply(cl, files, process_file_set, colnames = colnames)


  combined_data <- do.call(rbind, data_list)


  write.csv(combined_data, output_file, row.names = FALSE)
}

process_file_parallel(a_files, a_colnames, "path directory/yourcsvanamehere.csv")


process_file_parallel(b_files, b_colnames, "path directory/yourcsvbnamehere.csv")


process_file_parallel(c_files, c_colnames, "path directory/yourcsvcnamehere.csv")


stopCluster(cl)
