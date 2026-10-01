# Tests that read_irregular pads/truncates rows and reports how many it touched.

ROOT <- testthat::test_path("..", "..")
source(file.path(ROOT, "R", "convert.R"))

test_that("short rows are padded with NA and the pad count is reported", {
  dir <- withr::local_tempdir()
  path <- write_fixture(dir, "short.txt", c(
    "1 2 3",
    "4 5",      # one field short
    "6 7 8"
  ))

  data <- read_irregular(path, col_names = c("a", "b", "c"))

  expect_equal(nrow(data), 3)
  expect_equal(data$a, c(1, 4, 6))
  expect_equal(data$b, c(2, 5, 7))
  expect_equal(data$c, c(3, NA, 8))
  expect_equal(attr(data, "n_padded"), 1L)
  expect_equal(attr(data, "n_truncated"), 0L)
})

test_that("long rows are truncated and the truncation count is reported", {
  dir <- withr::local_tempdir()
  path <- write_fixture(dir, "long.txt", c(
    "1 2 3",
    "4 5 6 7 8", # two fields too many
    "9 10 11"
  ))

  data <- read_irregular(path, col_names = c("a", "b", "c"))

  expect_equal(nrow(data), 3)
  expect_equal(data$a, c(1, 4, 9))
  expect_equal(data$b, c(2, 5, 10))
  expect_equal(data$c, c(3, 6, 11))
  expect_equal(attr(data, "n_padded"), 0L)
  expect_equal(attr(data, "n_truncated"), 1L)
})

test_that("column names are applied in order", {
  dir <- withr::local_tempdir()
  path <- write_fixture(dir, "named.txt", c("1 2 3"))

  data <- read_irregular(path, col_names = c("permno", "date", "ret"))

  expect_equal(names(data), c("permno", "date", "ret"))
})

test_that("rows that are neither short nor long are left alone", {
  dir <- withr::local_tempdir()
  path <- write_fixture(dir, "exact.txt", c("1 2", "3 4"))

  data <- read_irregular(path, col_names = c("a", "b"))

  expect_equal(attr(data, "n_padded"), 0L)
  expect_equal(attr(data, "n_truncated"), 0L)
})
