# setup ---------
source("R/setup.R")

## read functions --------------
source("R/functions.R")


## load data --------
dt <- fst::read_fst(fs::path(new_dir,
                             "raw_recovered_dist", ext = "fst"),
                    as.data.table = TRUE)
#
# write_parquet(dt, fs::path(new_dir,
#                           "raw_recovered_dist"))
#


## by vars ---------
by_vars <- c("country_code", "reporting_year", "reporting_level", "welfare_type")


# format data -----------

# I tried using arrow but it does not support window calculations and joining the databases is super slow. I also tried data.table way but it is slower than collapse.

## get the min difference ----------
med <- dt  |>
  ftransform(diff_med = abs(.5 - headcount)) |>
  fgroup_by(by_vars) |>
  fmutate(gmin = (fmin(diff_med) == diff_med)) |>
  fungroup() |>
  fsubset(gmin)

## Find duplicates ---------
med_dup <-  duplicated(med, by = c(by_vars, "diff_med"))

## filter and SPL ------
med2 <- med |>
  fsubset(!med_dup) |>
  fselect(c(by_vars, median = "poverty_line")) |>
  fsubset(!(country_code %in% c("CHN", "IDN", "IND") &
              reporting_level != "national")) |>
  ftransform(spl = wbpip:::compute_spl(median, ppp_year))


# calculate SPR -------------

spl <- med2 |>
  fselect(country = country_code ,
          povline = spl,
          year    = reporting_year,
          welfare_type) |>
  as.list()


spr <-
  purrr::pmap(spl,
              \(country, year, povline, welfare_type) {
    y <-
      pipapi::pip(country      = country,
                  year         = year,
                  povline      = povline,
                  lkup         = lkup,
                  fill_gaps    = TRUE,
                  welfare_type = welfare_type)
  },
  .progress = TRUE
  ) |>
  rbindlist()


spr  %<>%
  fselect(country_code,
          reporting_year,
          reporting_level,
          welfare_type,
          spl = poverty_line,
          spr = headcount)

d_med <- med |>
  fsubset(!med_dup) |>
  fselect(c(by_vars, median = "poverty_line"))

# join the median by reporting level
d_spr <- joyn::merge(spr, d_med,
                     match_type = "1:1",
                     reportvar = FALSE)



# save ---------

## Project dir --------------
spl_datadir <-
  fs::path("data", version) |>
  fs::dir_create(recurse = TRUE)


fst::write_fst(d_spr, fs::path(spl_datadir, "spr_lnp", ext = "fst"))
haven::write_dta(d_spr, fs::path(spl_datadir, "spr_lnp", ext = "dta"))

spr_id <- joyn::is_id(d_spr,by_vars, return_report = TRUE )
spr_id[copies > 1]


# spr <- fst::read_fst(fs::path(spl_datadir, "spr_lnp", ext = "fst"))
fst::write_fst(d_spr, fs::path(gls$OUT_AUX_DIR_PC, "spr_lnp", ext = "fst"))





# data.table way.
# rdt0 <- dt  |>
#   ftransform(diff_med = abs(.5 - headcount)) |>
#   {\(.) .[.[, .I[diff_med == min(diff_med, na.rm = TRUE)],
#             by = by_vars]$V1]}() |>
#   na_omit()

