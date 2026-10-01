# Tests that .sas7bdat files are read via haven and still forced to the
# expected column count. Skipped if haven is not installed.

ROOT <- testthat::test_path("..", "..")
source(file.path(ROOT, "R", "convert.R"))

test_that("a .sas7bdat file is read with haven and keeps its column names", {
  testthat::skip_if_not_installed("haven")

  dir <- withr::local_tempdir()
  path <- file.path(dir, "crsp.sas7bdat")
  suppressWarnings(haven::write_sas(data.frame(permno = c(1, 2), ret = c(0.01, -0.02)), path))

  data <- read_irregular(path, col_names = c("permno", "ret"))

  expect_equal(nrow(data), 2)
  expect_equal(names(data), c("permno", "ret"))
  expect_equal(attr(data, "n_padded"), 0L)
  expect_equal(attr(data, "n_truncated"), 0L)
})

test_that("a .sas7bdat file with fewer columns than expected is padded", {
  testthat::skip_if_not_installed("haven")

  dir <- withr::local_tempdir()
  path <- file.path(dir, "crsp_short.sas7bdat")
  suppressWarnings(haven::write_sas(data.frame(permno = c(1, 2)), path))

  data <- read_irregular(path, col_names = c("permno", "ret"))

  expect_equal(names(data), c("permno", "ret"))
  expect_true(all(is.na(data$ret)))
  expect_equal(attr(data, "n_padded"), 2L)
})
