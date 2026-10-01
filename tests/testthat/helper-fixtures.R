# Shared fixture builders for the convert_files/read_irregular tests.

ROOT <- testthat::test_path("..", "..")
source(file.path(ROOT, "R", "convert.R"))

# Writes a whitespace-delimited text file with the given raw lines (each a
# single string, fields already separated by spaces) and returns its path.
write_fixture <- function(dir, name, lines) {
  path <- file.path(dir, name)
  writeLines(lines, path)
  path
}
