## [nep-miri] ProFound catalogues of the NEP TDF JumProPe (ProPane) mosaics, using JumProPe's own detection and
## measurement settings (ProFound_settings.R: profound_detect_master, profound_measure_master).
## The mosaics of an instrument share one grid (make_grids.py), so the detection image is the inverse-variance weighted
## stack of all filters of a set. The detection segmentation map is then measured in every filter (redosegim dilation,
## as in JumProPe). Star masks are not applied: the MIRI area has few bright Gaia stars.
## Usage: Rscript profound_nep.R <miri|nircam> <program id | all>
## Writes ~/JP/PRO/ProFound_NEP/<inst>_<prog>/: detect_segim.fits, cat_detect.csv, cat_<FILT>.csv and cat_multiband.csv.
setwd("/Users/ralphy/Work/research/codes/JUMPROPE/PROFOUND")
suppressMessages({library(Rfits); library(Rwcs); library(ProFound); library(data.table); library(magicaxis)})
source("ProFound_settings.R")

cmd = commandArgs(trailingOnly = TRUE)
inst = cmd[1]; prog = cmd[2]
tag = paste0("NEP", toupper(inst), prog)
files = list.files("/Users/ralphy/JP/PRO/Mosaic_Stacks/Patch", pattern = paste0("^patch_", tag, "_F.*\\.fits$"), full.names = TRUE)
filts = sub(".*_(F[0-9]+[WMN])\\.fits$", "\\1", files)
out = paste0("/Users/ralphy/JP/PRO/ProFound_NEP/", inst, "_", prog, "/")
dir.create(out, recursive = TRUE, showWarnings = FALSE)
message(tag, ": ", paste(filts, collapse = " "))

read_band = function(f){
  im = Rfits_read_image(f, ext = 1)                 # 'image', microJy per pixel (magzero 23.9)
  iv = Rfits_read_image(f, ext = 3, header = FALSE)   # 'inVar'
  im$imDat[!is.finite(im$imDat)] = NA
  iv[!is.finite(iv) | is.na(im$imDat)] = 0
  list(im = im, iv = iv)
}

## detection image: inverse-variance weighted mean of all bands
num = NULL; den = NULL; ref = NULL
for(f in files){
  b = read_band(f)
  if(is.null(ref)){ ref = b$im; num = 0 * b$iv; den = 0 * b$iv }
  num = num + ifelse(is.na(b$im$imDat), 0, b$im$imDat) * b$iv
  den = den + b$iv
  rm(b); gc()
}
det = ref
det$imDat = ifelse(den > 0, num / den, NA)
det$keyvalues$MAGZERO = 23.9
skyRMS = ifelse(den > 0, den^-0.5, NA)
star_mask = matrix(FALSE, nrow(det$imDat), ncol(det$imDat))
pro = profound_detect_master(det, skyRMS = skyRMS, star_mask = star_mask)
Rfits_write_image(pro$segim, paste0(out, "detect_segim.fits"), keyvalues = det$keyvalues)
seg = pro$segstats
fwrite(seg, paste0(out, "cat_detect.csv"))
message("detections: ", nrow(seg))

## forced measurement per band on the detection segments
multi = data.table(segID = seg$segID, RAcen = seg$RAcen, Deccen = seg$Deccen)
for(i in seq_along(files)){
  b = read_band(files[i])
  b$im$keyvalues$MAGZERO = 23.9
  m = profound_measure_master(b$im, inVar = b$iv, segim = pro$segim, mask = is.na(b$im$imDat))
  s = as.data.table(m$segstats)
  fwrite(s, paste0(out, "cat_", filts[i], ".csv"))
  keep = s[, .(segID, flux, flux_err)]
  setnames(keep, c("flux", "flux_err"), paste0(filts[i], c("_flux", "_flux_err")))
  multi = merge(multi, keep, by = "segID", all.x = TRUE)
  rm(b, m); gc()
  message(filts[i], " measured")
}
fwrite(multi, paste0(out, "cat_multiband.csv"))
message("PROFOUND_NEP_DONE ", tag, " ", nrow(multi), " sources")
