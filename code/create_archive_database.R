# --------------------------------------------------------------------
# create_archive_database.R
# Builds a publishable copy of the UAVSurveys SQLite database containing
# only what is needed to reproduce the published analysis: the tables
# used by the pipeline (and the lookup tables they reference), surveys of
# the three Ross Island colonies (Cape Crozier, Cape Bird, Cape Royds),
# and results for the deployed YOLOv8 model (ADPE_20250804_adult_sit).
# The working database is not modified.
#
# Run in two passes:
#   1. build_archive <- FALSE: report every table and column in the
#      working database (row counts, keys, foreign keys) and flag columns
#      that look unsuitable for publication (names containing "notes";
#      text values that look like file paths). The report is also written
#      to data/database_inventory.csv.
#   2. build_archive <- TRUE: copy the database file, then in the copy
#        - stop if the working database already has foreign key
#          violations (these must be fixed first, because the row
#          filtering below removes rows that reference missing rows),
#        - check that every table referenced by a kept table is kept,
#        - drop all other tables, and all views and triggers,
#        - drop the listed columns, columns matching drop_pattern, and any
#          indexes on them (other table definitions, including primary
#          and foreign keys, are unchanged),
#        - apply the row filters (colonies, model), then remove rows
#          whose foreign keys refer to removed rows, repeating until no
#          further rows are removed (e.g., surveys at other locations,
#          and their imagery, predictions, counts, and label sets),
#        - remove lookup-table rows that no kept row refers to,
#        - run SQLite's foreign key check (must report no violations),
#        - VACUUM, so that removed data are not left in unused pages of
#          the file,
#        - scan the remaining text values for file paths.
#
# The archive is then written to a SQL file with export_database_sql.R.
#
# Requires SQLite 3.35 or later (for ALTER TABLE ... DROP COLUMN), which
# is included with current versions of RSQLite. Run from the project root.
#
# Developed with assistance from Claude (Anthropic); reviewed and tested by the authors.
# --------------------------------------------------------------------

library(DBI)
library(RSQLite)

# --------------------------------------------------------------------
# Configuration
# --------------------------------------------------------------------
db_name    <- "data/UAVSurveys.db"
archive_db <- "data/UAVSurveys_archive.db"

build_archive <- FALSE

# Colonies and model included in the archive. Colony codes are matched
# without regard to case (LocationId values are upper case, e.g. "CROZ";
# GroundCounts.col values are lower case).
colonies   <- c("croz", "bird", "royd")
model_name <- "ADPE_20250804_adult_sit"

# Tables to keep: those used by the pipeline and analysis, and the lookup
# tables they reference
tables_keep <- c("Surveys", "SurveyImagery", "ModelPredictions",
                 "CalibratedCounts", "GroundCounts", "ManualCountsOccupied",
                 "HumanLabels", "Locations", "UAVs", "Models",
                 "LabelsClassSets", "LabelClasses")

# Columns to drop, by table
columns_drop <- list(
  HumanLabels = c("ValidationLabelsLoc")
)

# Columns whose names match this pattern (case-insensitive) are dropped
# from every kept table
drop_pattern <- "notes"

# Row filters (SQL conditions), applied in this order. Rows in other
# tables that refer to removed rows are then removed through the foreign
# keys.
in_list <- function(x) paste0("(", paste(sprintf("'%s'", x), collapse = ", "), ")")
row_filters <- list(
  Locations        = paste("UPPER(LocationId) IN", in_list(toupper(colonies))),
  GroundCounts     = paste("LOWER(col) IN", in_list(tolower(colonies))),
  Models           = sprintf("ModelName = '%s'", model_name),
  ModelPredictions = sprintf("ModelName = '%s'", model_name),
  CalibratedCounts = "PredictId IN (SELECT PredictId FROM ModelPredictions)"
)

# Lookup tables from which rows not referred to by any kept row are
# removed (in this order)
prune_lookups <- c("UAVs", "LabelsClassSets", "LabelClasses")

# Text values matching this pattern are reported as possible file paths
path_pattern <- "^[A-Za-z]:[\\\\/]|^\\\\\\\\|^/(home|Users|mnt|Volumes|srv|data)/|[\\\\/](Informatics|Users|Desktop|Documents)[\\\\/]"

# --------------------------------------------------------------------
# Functions
# --------------------------------------------------------------------
# One row per column of every table, with keys and publication flags
inventory <- function(con) {
  tabs <- dbGetQuery(con, "SELECT name FROM sqlite_master WHERE type = 'table'
                           AND name NOT LIKE 'sqlite_%' ORDER BY name")$name
  out <- lapply(tabs, function(t) {
    info <- dbGetQuery(con, sprintf("PRAGMA table_info('%s')", t))
    fk   <- dbGetQuery(con, sprintf("PRAGMA foreign_key_list('%s')", t))
    n    <- dbGetQuery(con, sprintf('SELECT COUNT(*) FROM "%s"', t))[[1]]
    do.call(rbind, lapply(seq_len(nrow(info)), function(i) {
      col <- info$name[i]
      vals <- dbGetQuery(con, sprintf('SELECT "%s" AS v FROM "%s" WHERE typeof("%s") = \'text\'',
                                      col, t, col))$v
      ref <- fk[fk$from == col, ]
      data.frame(
        table = t, column = col, type = info$type[i], rows = n,
        non_null = dbGetQuery(con, sprintf('SELECT COUNT("%s") FROM "%s"', col, t))[[1]],
        primary_key = info$pk[i] > 0,
        references = if (nrow(ref) > 0) paste0(ref$table, "(", ref$to, ")") else "",
        path_like = sum(grepl(path_pattern, vals, perl = TRUE)),
        name_flag = grepl(drop_pattern, col, ignore.case = TRUE),
        stringsAsFactors = FALSE)
    }))
  })
  do.call(rbind, out)
}

# Foreign keys among the given tables: child table and column, parent
# table and column
foreign_keys <- function(con, tables) {
  fks <- do.call(rbind, lapply(tables, function(t) {
    f <- dbGetQuery(con, sprintf("PRAGMA foreign_key_list('%s')", t))
    if (nrow(f) == 0) return(NULL)
    if (any(duplicated(f$id))) stop("Composite foreign key in ", t, " is not supported.")
    data.frame(child = t, from = f$from, parent = f$table, to = f$to,
               stringsAsFactors = FALSE)
  }))
  if (is.null(fks)) data.frame(child = character(0), from = character(0),
                               parent = character(0), to = character(0)) else fks
}

row_counts <- function(con, tables) {
  sapply(tables, function(t) dbGetQuery(con, sprintf('SELECT COUNT(*) FROM "%s"', t))[[1]])
}

# --------------------------------------------------------------------
# Pass 1: report
# --------------------------------------------------------------------
src <- dbConnect(SQLite(), db_name)
inv <- inventory(src)
other <- dbGetQuery(src, "SELECT type, name, tbl_name FROM sqlite_master
                          WHERE type IN ('view', 'trigger') ORDER BY type, name")
dbDisconnect(src)

write.csv(inv, "data/database_inventory.csv", row.names = FALSE)
options(width = 200)
cat("Tables in", db_name, "(kept = in tables_keep):\n")
tab_summary <- unique(inv[, c("table", "rows")])
tab_summary$kept <- tab_summary$table %in% tables_keep
print(tab_summary, row.names = FALSE)
if (nrow(other) > 0) { cat("\nViews and triggers (not copied):\n"); print(other, row.names = FALSE) }
flagged <- inv[inv$table %in% tables_keep & (inv$path_like > 0 | inv$name_flag), ]
if (nrow(flagged) > 0) {
  cat("\nFlagged columns in kept tables (path-like values or names matching '",
      drop_pattern, "'):\n", sep = "")
  print(flagged[, c("table", "column", "non_null", "path_like", "name_flag")], row.names = FALSE)
}
cat("\nFull inventory written to data/database_inventory.csv\n")

if (!build_archive) {
  cat("\nSet build_archive <- TRUE to build", archive_db, "\n")
} else {

  # ------------------------------------------------------------------
  # Pass 2: build the archive
  # ------------------------------------------------------------------
  missing <- setdiff(c(tables_keep, names(row_filters), prune_lookups), unique(inv$table))
  if (length(missing) > 0) stop("Tables not found: ", paste(missing, collapse = ", "))
  not_kept <- setdiff(c(names(row_filters), prune_lookups), tables_keep)
  if (length(not_kept) > 0) stop("Filtered tables not in tables_keep: ", paste(not_kept, collapse = ", "))

  # Every table referenced by a kept table must also be kept
  refs <- inv[inv$table %in% tables_keep & nzchar(inv$references), ]
  needed <- setdiff(unique(sub("\\(.*", "", refs$references)), tables_keep)
  if (length(needed) > 0) {
    stop("Kept tables have foreign keys to tables not in tables_keep: ",
         paste(needed, collapse = ", "), ". Add them or drop the referencing tables.")
  }

  # Columns to drop
  drops <- inv[inv$table %in% tables_keep &
                 (inv$name_flag |
                    mapply(function(t, c) c %in% columns_drop[[t]], inv$table, inv$column)),
               c("table", "column", "primary_key", "references")]
  unknown <- unlist(lapply(names(columns_drop), function(t)
    setdiff(columns_drop[[t]], inv$column[inv$table == t])))
  if (length(unknown) > 0) stop("Columns in columns_drop not found: ", paste(unknown, collapse = ", "))
  if (any(drops$primary_key | nzchar(drops$references))) {
    stop("Cannot drop key columns: ",
         paste(with(drops[drops$primary_key | nzchar(drops$references), ],
                    paste0(table, ".", column)), collapse = ", "))
  }

  if (file.exists(archive_db)) file.remove(archive_db)
  file.copy(db_name, archive_db)
  con <- dbConnect(SQLite(), archive_db)
  if (package_version(dbGetQuery(con, "SELECT sqlite_version()")[[1]]) < "3.35") {
    dbDisconnect(con); stop("SQLite 3.35 or later is required; update RSQLite.")
  }
  dbExecute(con, "PRAGMA foreign_keys = OFF")

  # Existing violations among kept tables would be removed silently by the
  # foreign-key cascade below, so they must be fixed in the working
  # database first
  existing <- dbGetQuery(con, "PRAGMA foreign_key_check")
  existing <- existing[existing$table %in% tables_keep, ]
  if (nrow(existing) > 0) {
    dbDisconnect(con); file.remove(archive_db)
    print(table(existing$table, existing$parent))
    stop("The working database has foreign key violations in kept tables ",
         "(counts above). Fix them before building the archive.")
  }
  # The colonies and model must exist, or the filters would remove everything
  ids <- dbGetQuery(con, "SELECT LocationId FROM Locations")$LocationId
  models <- dbGetQuery(con, "SELECT ModelName FROM Models")$ModelName
  if (length(setdiff(toupper(colonies), toupper(ids))) > 0 || !model_name %in% models) {
    dbDisconnect(con); file.remove(archive_db)
    stop("Check colonies and model_name. LocationId values: ", paste(ids, collapse = ", "),
         "; models: ", paste(models, collapse = ", "))
  }
  before <- row_counts(con, tables_keep)

  # Views, triggers, and tables not kept
  for (i in seq_len(nrow(other))) {
    dbExecute(con, sprintf('DROP %s IF EXISTS "%s"', toupper(other$type[i]), other$name[i]))
  }
  for (t in setdiff(unique(inv$table), tables_keep)) {
    dbExecute(con, sprintf('DROP TABLE "%s"', t))
    message("Dropped table ", t)
  }

  # Columns (indexes that use a dropped column are dropped first)
  for (i in seq_len(nrow(drops))) {
    t <- drops$table[i]; c <- drops$column[i]
    idx <- dbGetQuery(con, sprintf("PRAGMA index_list('%s')", t))
    for (ix in idx$name[idx$origin == "c"]) {
      if (c %in% dbGetQuery(con, sprintf("PRAGMA index_info('%s')", ix))$name) {
        dbExecute(con, sprintf('DROP INDEX "%s"', ix))
        message("Dropped index ", ix)
      }
    }
    dbExecute(con, sprintf('ALTER TABLE "%s" DROP COLUMN "%s"', t, c))
    message("Dropped column ", t, ".", c)
  }

  # Row filters
  for (t in names(row_filters)) {
    dbExecute(con, sprintf('DELETE FROM "%s" WHERE NOT (%s)', t, row_filters[[t]]))
  }

  # Remove rows that refer to removed rows, until none remain
  fks <- foreign_keys(con, tables_keep)
  repeat {
    removed <- 0
    for (i in seq_len(nrow(fks))) {
      removed <- removed + dbExecute(con, sprintf(
        'DELETE FROM "%s" WHERE "%s" IS NOT NULL AND "%s" NOT IN
           (SELECT "%s" FROM "%s" WHERE "%s" IS NOT NULL)',
        fks$child[i], fks$from[i], fks$from[i],
        fks$to[i], fks$parent[i], fks$to[i]))
    }
    if (removed == 0) break
  }

  # Lookup rows no longer referred to by any kept row
  repeat {
    removed <- 0
    for (l in prune_lookups) {
      used <- fks[fks$parent == l, ]
      if (nrow(used) == 0) next
      key <- unique(used$to)
      if (length(key) != 1) stop("Lookup table ", l, " is referenced through more than one column.")
      in_use <- paste(sprintf('SELECT "%s" FROM "%s" WHERE "%s" IS NOT NULL',
                              used$from, used$child, used$from), collapse = " UNION ")
      removed <- removed + dbExecute(con, sprintf(
        'DELETE FROM "%s" WHERE "%s" NOT IN (%s)', l, key, in_use))
    }
    if (removed == 0) break
  }

  after <- row_counts(con, tables_keep)
  fk_problems <- dbGetQuery(con, "PRAGMA foreign_key_check")
  dbExecute(con, "VACUUM")
  final <- inventory(con)
  dbDisconnect(con)

  cat("\nRows kept:\n")
  print(data.frame(table = tables_keep, before = before, after = after,
                   removed = before - after), row.names = FALSE)

  if (nrow(fk_problems) > 0) {
    print(fk_problems)
    stop("Foreign key violations in the archive (listed above); it should not be published as is.")
  }
  message("Foreign key check: no violations")

  still_flagged <- final[final$path_like > 0, c("table", "column", "path_like")]
  if (nrow(still_flagged) > 0) {
    warning("Columns in the archive still contain path-like values:\n",
            paste(capture.output(print(still_flagged, row.names = FALSE)), collapse = "\n"),
            call. = FALSE)
  }
  cat("\nArchive written to", archive_db, "\n")
}
