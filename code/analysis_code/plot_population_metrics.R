# --------------------------------------------------------------------
# plot_population_metrics.R
# Produces Figures 4, 5, and 6 of the manuscript (Results Section 3.6):
#   Figure 4: adjusted candidate nests, estimated occupied territories,
#             estimated total individuals, and estimated active nests
#             (occupied-territory pathway) by colony and year
#   Figure 5: estimated occupied territories and the whole-colony manual
#             count of occupied territories at Cape Royds
#   Figure 6: adjusted candidate nests, estimated occupied territories,
#             and the helicopter census by colony and year
# Error bars are 95% margins of error. Figures 4 and 6 share per-colony
# y-axis limits, spanning every metric and error bar shown in either
# figure, so that the two figures can be compared directly. Helicopter
# counts are shown only from each colony's first UAV survey year, and
# lines break at seasons without a helicopter census. In Figure 6 the
# helicopter census is drawn as a dashed dark gray line so that the UAV
# series stand apart, and the two UAV series are offset slightly to
# either side of each survey year (fig6_offset) so that overlapping
# points and error bars can be told apart.
#
# Inputs:  data/UAVSurveys.db
#          data/ross_sea_adelie_penguin_census_record_1981_2025.csv
# Outputs: figs/fig4_uav_metrics_by_year.jpg, .pdf
#          figs/fig5_royds_occupied_vs_manual.jpg, .pdf
#          figs/fig6_uav_vs_helicopter_by_year.jpg, .pdf
#
# Developed with assistance from Claude (Anthropic); reviewed and tested by the authors.
# --------------------------------------------------------------------

source("code/analysis_code/analysis_helpers.R")

# Figure dimensions (inches), matching the submitted figures
fig_size <- list(fig4 = c(width = 6.3, height = 7.3),
                 fig5 = c(width = 7, height = 5),
                 fig6 = c(width = 5.4, height = 7.3))

colony_label <- function(code) factor(colony_names[code], levels = colony_order)
year_span <- 2018:2025

# --------------------------------------------------------------------
# Assemble plotting data
# --------------------------------------------------------------------
s <- survey_totals(read_calibrated_counts())

# UAV-derived metrics, one row per survey and metric
uav_long <- s %>%
  select(colony, year, AdjCN, AdjCN_MoE, Occ, Occ_MoE, TI, TI_MoE, Active, Active_MoE) %>%
  pivot_longer(c(AdjCN, Occ, TI, Active), names_to = "key", values_to = "count") %>%
  mutate(moe = case_when(key == "AdjCN"  ~ AdjCN_MoE,
                         key == "Occ"    ~ Occ_MoE,
                         key == "TI"     ~ TI_MoE,
                         key == "Active" ~ Active_MoE),
         metric = case_when(key == "AdjCN"  ~ lab_cn,
                            key == "Occ"    ~ lab_occ,
                            key == "TI"     ~ lab_ti,
                            key == "Active" ~ lab_actocc)) %>%
  select(colony, year, metric, count, moe)

# Whole-colony manual count of occupied territories (Cape Royds)
manual_long <- read_royds_manual() %>%
  transmute(colony, year, metric = lab_mocc, count = manual_occ, moe = NA_real_)

# Helicopter census within each colony's UAV era, with explicit missing
# rows so that lines break at seasons without a census
first_uav <- s %>% group_by(colony) %>% summarise(first_uav = min(year), .groups = "drop")
heli_long <- read_helicopter_census() %>%
  inner_join(first_uav, by = "colony") %>%
  filter(year >= first_uav, year %in% year_span) %>%
  select(colony, year, count = heli) %>%
  complete(colony, year = year_span) %>%
  inner_join(first_uav, by = "colony") %>%
  filter(year >= first_uav) %>%
  transmute(colony, year, metric = lab_aerial, count, moe = NA_real_)

metric_levels <- c(lab_cn, lab_aerial, lab_occ, lab_ti, lab_actocc, lab_mocc)
plot_data <- bind_rows(uav_long, manual_long, heli_long) %>%
  mutate(metric = factor(metric, levels = metric_levels),
         colony_label = colony_label(colony))

fig4_metrics <- c(lab_cn, lab_occ, lab_ti, lab_actocc)
fig6_metrics <- c(lab_cn, lab_aerial, lab_occ)

# Per-colony y-axis limits shared by Figures 4 and 6, including error bars
y_limits <- plot_data %>%
  filter(metric %in% union(fig4_metrics, fig6_metrics), !is.na(count)) %>%
  group_by(colony_label) %>%
  summarise(ymin = min(count - coalesce(moe, 0)),
            ymax = max(count + coalesce(moe, 0)), .groups = "drop") %>%
  pivot_longer(c(ymin, ymax), values_to = "count") %>%
  mutate(year = min(year_span))

# --------------------------------------------------------------------
# Shared base plot
# --------------------------------------------------------------------
# Points drive the legend; error bars and lines are drawn without one
base_ts <- ggplot(mapping = aes(x = year, y = count, colour = metric, shape = metric)) +
  geom_errorbar(aes(ymin = count - moe, ymax = count + moe), width = 0.2,
                linewidth = 1, na.rm = TRUE, show.legend = FALSE) +
  geom_line(linewidth = 0.8, show.legend = FALSE) +
  geom_point(size = 2, na.rm = TRUE) +
  scale_x_continuous(breaks = seq(2018, 2025, by = 2)) +
  scale_colour_manual(values = metric_cols, drop = TRUE) +
  scale_shape_manual(values = metric_shapes, drop = TRUE) +
  labs(x = "Year", y = "Count", colour = NULL, shape = NULL) +
  uav_theme() +
  theme(legend.position = "right",
        strip.text = element_text(face = "bold", size = 10))

faceted <- function(p) {
  p + geom_blank(data = y_limits, aes(x = year, y = count), inherit.aes = FALSE) +
    facet_wrap(~ colony_label, scales = "free_y", ncol = 1) +
    scale_y_continuous(n.breaks = 8)
}

# --------------------------------------------------------------------
# Figure 4: UAV-derived metrics
# --------------------------------------------------------------------
fig4 <- faceted(base_ts %+% (plot_data %>%
                               filter(metric %in% fig4_metrics, !is.na(count)) %>%
                               droplevels()))
save_figure(fig4, "fig4_uav_metrics_by_year",
            width = fig_size$fig4[["width"]], height = fig_size$fig4[["height"]])

# --------------------------------------------------------------------
# Figure 5: Cape Royds estimated vs manual occupied territories
# --------------------------------------------------------------------
fig5 <- base_ts %+% (plot_data %>%
                       filter(colony == "royd", metric %in% c(lab_occ, lab_mocc)) %>%
                       droplevels()) +
  geom_point(size = 4, na.rm = TRUE)
save_figure(fig5, "fig5_royds_occupied_vs_manual",
            width = fig_size$fig5[["width"]], height = fig_size$fig5[["height"]])

# --------------------------------------------------------------------
# Figure 6: UAV metrics vs the helicopter census
# --------------------------------------------------------------------
# Helicopter census in dark gray with a dashed line; all other series
# keep their palette colors and solid lines
fig6_cols <- metric_cols
fig6_cols[lab_aerial] <- "grey25"
fig6_lines <- setNames(rep("solid", length(metric_levels)), metric_levels)
fig6_lines[lab_aerial] <- "22"

# Horizontal offset (years) of the two UAV series; 0 places all series on
# the survey year
# fig6_offset <- 0.08
fig6_offset <- 0.0
fig6_shift <- setNames(rep(0, length(metric_levels)), metric_levels)
fig6_shift[lab_cn]  <- -fig6_offset
fig6_shift[lab_occ] <-  fig6_offset

# Missing helicopter rows are kept so that the line breaks at gaps
fig6_data <- plot_data %>%
  filter(metric %in% fig6_metrics) %>%
  droplevels() %>%
  mutate(year = year + fig6_shift[as.character(metric)])

fig6 <- ggplot(fig6_data, aes(x = year, y = count, colour = metric,
                              shape = metric, linetype = metric)) +
  geom_errorbar(aes(ymin = count - moe, ymax = count + moe), width = 0.12,
                linewidth = 0.5, na.rm = TRUE, show.legend = FALSE) +
  geom_line(linewidth = 0.8) +
  geom_point(size = 2.5, na.rm = TRUE) +
  geom_blank(data = y_limits, aes(x = year, y = count), inherit.aes = FALSE) +
  facet_wrap(~ colony_label, scales = "free_y", ncol = 1) +
  scale_x_continuous(breaks = seq(2018, 2025, by = 2)) +
  scale_y_continuous(n.breaks = 8) +
  scale_colour_manual(values = fig6_cols, drop = TRUE) +
  scale_shape_manual(values = metric_shapes, drop = TRUE) +
  scale_linetype_manual(values = fig6_lines, drop = TRUE) +
  labs(x = "Year", y = "Count", colour = NULL, shape = NULL, linetype = NULL) +
  uav_theme() +
  theme(legend.position = "right",
        legend.key.width = unit(1.5, "lines"),
        strip.text = element_text(face = "bold", size = 10))
save_figure(fig6, "fig6_uav_vs_helicopter_by_year",
            width = fig_size$fig6[["width"]], height = fig_size$fig6[["height"]])