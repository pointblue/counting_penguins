# --------------------------------------------------------------------
# export_database_sql.R
# Writes the tables used by the penguin counting pipeline from the
# SQLite database data/UAVSurveys.db to a plain-text SQL file, so that
# the database can be published and recreated.
#
# Each table is written with its original CREATE TABLE statement (column
# types and primary keys preserved) and any indexes, followed by one
# INSERT statement per row. Rows in ModelPredictions and CalibratedCounts
# can be limited to one model, and rows in Locations to selected
# locations. After writing, the script rebuilds a
# database from the SQL file in a temporary location, checks that every
# exported table is identical to the original, and runs SQLite's foreign
# key check on the rebuilt database.
#
# To recreate the database from the SQL file, with the sqlite3 command-line
# tool:
#   sqlite3 data/UAVSurveys.db < data/UAVSurveys.sql
# or in R, with the rebuild_from_sql() function defined below:
#   rebuild_from_sql("data/UAVSurveys.sql", "data/UAVSurveys.db")
#
# Output: data/UAVSurveys.sql (from data/UAVSurveys_archive.db)
# Run from the project root.
#
# Developed with assistance from Claude (Anthropic); reviewed and tested by the authors.
# --------------------------------------------------------------------

library(DBI)
library(RSQLite)

# --------------------------------------------------------------------
# Configuration
# --------------------------------------------------------------------
# Source database: the archive copy made by create_archive_database.R,
# which already contains only the tables, colonies, and model to publish
db_name  <- "data/UAVSurveys_archive.db"
sql_file <- "data/UAVSurveys.sql"

# Tables to export (NULL exports every table)
tables <- NULL

# Optional further limits, for use with a database that has not been
# filtered (NULL applies no limit). model_name limits ModelPredictions and
# CalibratedCounts to one model; locations_keep limits Locations to the
# listed LocationId values (every exported survey must be at one of them).
model_name     <- NULL
locations_keep <- NULL

# --------------------------------------------------------------------
# Functions
# --------------------------------------------------------------------
# Rows to export for one table
table_rows <- function(con, table, model_name, locations_keep = NULL) {
  if (!is.null(locations_keep) && table == "Locations") {
    dbGetQuery(con, sprintf("SELECT * FROM Locations WHERE LocationId IN (%s)",
                            paste(rep("?", length(locations_keep)), collapse = ", ")),
               params = as.list(locations_keep))
  } else if (!is.null(model_name) && table == "ModelPredictions") {
    dbGetQuery(con, "SELECT * FROM ModelPredictions WHERE ModelName = ?",
               params = list(model_name))
  } else if (!is.null(model_name) && table == "CalibratedCounts") {
    dbGetQuery(con, "
      SELECT cc.* FROM CalibratedCounts cc
      WHERE cc.PredictId IN
        (SELECT PredictId FROM ModelPredictions WHERE ModelName = ?)",
      params = list(model_name))
  } else {
    dbGetQuery(con, sprintf('SELECT * FROM "%s"', table))
  }
}

# SQL literal for each value of a column. Doubles are written in the
# shortest form (up to 17 significant digits) that reads back exactly.
sql_values <- function(con, x) {
  if (is.double(x)) {
    out <- rep("NULL", length(x))
    ok <- !is.na(x)
    for (d in 15:17) {
      f <- formatC(x[ok], digits = d, format = "g")
      done <- as.numeric(f) == x[ok]
      out[which(ok)[done]] <- f[done]
      ok[which(ok)[done]] <- FALSE
      if (!any(ok)) break
    }
    trimws(out)
  } else {
    # Line breaks inside text are written as char() so that each INSERT
    # statement stays on one line
    q <- as.character(dbQuoteLiteral(con, x))
    q <- gsub("\r", "' || char(13) || '", q, fixed = TRUE)
    gsub("\n", "' || char(10) || '", q, fixed = TRUE)
  }
}

export_sql <- function(db_name, sql_file, tables, model_name, locations_keep = NULL) {
  con <- dbConnect(SQLite(), db_name)
  on.exit(dbDisconnect(con))
  if (is.null(tables)) {
    tables <- dbGetQuery(con, "SELECT name FROM sqlite_master WHERE type = 'table'
                               AND name NOT LIKE 'sqlite_%' ORDER BY rowid")$name
  }
  missing <- setdiff(tables, dbListTables(con))
  if (length(missing) > 0) stop("Tables not found: ", paste(missing, collapse = ", "))

  # Selected locations must exist, and every exported survey must be at one
  if (!is.null(locations_keep) && "Locations" %in% tables) {
    ids <- dbGetQuery(con, "SELECT LocationId FROM Locations")$LocationId
    unknown <- setdiff(locations_keep, ids)
    if (length(unknown) > 0) {
      stop("LocationId values not found: ", paste(unknown, collapse = ", "),
           ". Available: ", paste(ids, collapse = ", "))
    }
    if ("Surveys" %in% tables) {
      other <- dbGetQuery(con, sprintf(
        "SELECT SurveyId, LocationId FROM Surveys WHERE LocationId NOT IN (%s)",
        paste(rep("?", length(locations_keep)), collapse = ", ")),
        params = as.list(locations_keep))
      if (nrow(other) > 0) {
        stop(nrow(other), " surveys are at locations not in locations_keep, e.g.: ",
             paste(head(sprintf("%s (%s)", other$SurveyId, other$LocationId), 5),
                   collapse = ", "))
      }
    }
  }

  out <- file(sql_file, open = "w", encoding = "UTF-8")
  on.exit(close(out), add = TRUE)
  writeLines(c(sprintf("-- Tables exported from %s on %s", basename(db_name),
                       format(Sys.Date())),
               if (!is.null(model_name))
                 sprintf("-- ModelPredictions and CalibratedCounts limited to model %s",
                         model_name),
               if (!is.null(locations_keep))
                 sprintf("-- Locations limited to %s", paste(locations_keep, collapse = ", ")),
               "PRAGMA foreign_keys = OFF;", "BEGIN TRANSACTION;"), out)

  for (t in tables) {
    def <- dbGetQuery(con, "SELECT sql FROM sqlite_master
                            WHERE type = 'table' AND name = ?", params = list(t))$sql
    idx <- dbGetQuery(con, "SELECT sql FROM sqlite_master
                            WHERE type = 'index' AND tbl_name = ? AND sql IS NOT NULL",
                      params = list(t))$sql
    rows <- table_rows(con, t, model_name, locations_keep)
    writeLines(c("", sprintf("-- %s: %d rows", t, nrow(rows)),
                 sprintf('DROP TABLE IF EXISTS "%s";', t), paste0(def, ";")), out)
    if (nrow(rows) > 0) {
      vals <- do.call(paste, c(lapply(rows, function(col) sql_values(con, col)),
                               sep = ", "))
      cols <- paste(sprintf('"%s"', names(rows)), collapse = ", ")
      writeLines(sprintf('INSERT INTO "%s" (%s) VALUES (%s);', t, cols, vals), out)
    }
    if (length(idx) > 0) writeLines(paste0(idx, ";"), out)
    message(sprintf("%-22s %6d rows", t, nrow(rows)))
  }
  writeLines(c("", "COMMIT;"), out)
  invisible(sql_file)
}

# Build a SQLite database from a SQL file (statements end with ";" at the
# end of a line, as written by export_sql)
rebuild_from_sql <- function(sql_file, db_path) {
  txt <- readLines(sql_file, encoding = "UTF-8")
  txt <- txt[!grepl("^--", txt) & nzchar(txt)]
  stmts <- split(txt, cumsum(c(0, head(grepl(";$", txt), -1))))
  con <- dbConnect(SQLite(), db_path)
  on.exit(dbDisconnect(con))
  for (s in stmts) dbExecute(con, paste(s, collapse = "\n"))
  invisible(db_path)
}

# --------------------------------------------------------------------
# Export, then confirm the SQL file reproduces the exported tables
# --------------------------------------------------------------------
export_sql(db_name, sql_file, tables, model_name, locations_keep)
if (is.null(tables)) {
  con <- dbConnect(SQLite(), db_name)
  tables <- dbGetQuery(con, "SELECT name FROM sqlite_master WHERE type = 'table'
                             AND name NOT LIKE 'sqlite_%' ORDER BY rowid")$name
  dbDisconnect(con)
}

check_db <- tempfile(fileext = ".db")
rebuild_from_sql(sql_file, check_db)
orig <- dbConnect(SQLite(), db_name); copy <- dbConnect(SQLite(), check_db)
for (t in tables) {
  a <- table_rows(orig, t, model_name, locations_keep)
  b <- dbReadTable(copy, t)
  same <- isTRUE(all.equal(a, b, check.attributes = FALSE)) &&
    identical(dbGetQuery(orig, sprintf("PRAGMA table_info('%s')", t)),
              dbGetQuery(copy, sprintf("PRAGMA table_info('%s')", t)))
  message(sprintf("%-22s rebuilt from SQL: %s", t, if (same) "identical" else "DIFFERS"))
}
fk_problems <- dbGetQuery(copy, "PRAGMA foreign_key_check")
dbDisconnect(orig); dbDisconnect(copy); unlink(check_db)
if (nrow(fk_problems) > 0) {
  print(fk_problems)
  stop("The database rebuilt from the SQL file has foreign key violations (listed above).")
}
message("Foreign key check on rebuilt database: no violations")
message("Written: ", sql_file)
