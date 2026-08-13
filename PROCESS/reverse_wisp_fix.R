library(Rfits)
library(ProFound)
library(ProPane)
library(foreach)
library(doParallel)
library(Cairo)

args = commandArgs(trailingOnly = T)
if(length(args)==0){
  message("Specify observation or visit ID list")
  VID = ""
  
}else{VID = toString(args[1])}


env_var = Sys.getenv(
  x = c('JUMPROPE_RAW_DIR', 
        'JUMPROPE_do_NIRISS', 
        'JUMPROPE_cores_pro',
        'JUMPROPE_cores_stack',
        'JUMPROPE_tasks_stack')
)

if(any(env_var == "")){
  message("Please set the env variables.")
  q()
}

ids = if(nzchar(VID)) unlist(strsplit(VID, "|", fixed = TRUE)) else ""
ids = ids[nzchar(ids)]

if(length(ids) == 0){
  filelist_all = c(
    list.files(env_var['JUMPROPE_RAW_DIR'],
               recursive = TRUE,
               pattern = glob2rx("*.fits$"),
               full.names = TRUE)
  )
}else{
  filelist_all = unique(unlist(lapply(ids, function(id){
    list.files(env_var['JUMPROPE_RAW_DIR'],
               recursive = TRUE,
               pattern = glob2rx(paste0("*", id, "*.fits$")),
               full.names = TRUE)
  })))
}

cores = suppressWarnings(as.integer(env_var['JUMPROPE_cores_pro']))
if(is.na(cores) || cores < 1L){
  cores = 1L
}

if(VID != ""){
  scan_wisp_rem = Rfits_key_scan(filelist = filelist_all, keylist = c("FILTER", "PROGRAM"))
  not_pid_idx = sapply(scan_wisp_rem$PROGRAM, function(x)grepl(x, VID, fixed = T)) ## make sure PID is not embedded in string of VID
  filelist = filelist_all[not_pid_idx]
}else{
  filelist = filelist_all
}
## stop edit 

info = Rfits_key_scan(filelist = filelist,
                      keylist=c('DETECTOR', 'MODULE', 'FILTER', 'VID'), cores=1)
info_wisp = info[DETECTOR %in% c('NRCA1', 'NRCA2', 'NRCA3','NRCA4', 'NRCB1','NRCB2', 'NRCB3','NRCB4', 'MIRIMAGE'),] 
## WISP remove reverseal for NIRCam (step 11) and background remove reversal for MIRI (step 12)
module_list = paste0("NRC", unique(info$MODULE))
unique_visits = unique(info_wisp$VID)

message("Reversing wisp correction on short wavelength detectors:")
cat('Processing',dim(info_wisp)[1],'files\n')

registerDoParallel(cores = min(cores, max(1L, dim(info_wisp)[1])))

temp = foreach(ii = 1:dim(info_wisp)[1], .errorhandling = "stop", .packages = c("Rfits"))%dopar%{
  ## copy original data to directory where we keep the wisps
  vid = paste0(info_wisp$VID[ii])
  modl = paste0("NRC", info_wisp$MODULE[ii])
  message(paste0("Running: ", info_wisp$file[ii]))
  
  wisp_frame = Rfits_read(info_wisp$full[ii])
  if(!is.null(wisp_frame$SCI_ORIG)){
    Rfits_write_pix(data = wisp_frame$SCI_ORIG[,]$imDat, filename = info_wisp$full[ii], ext = 2) 
  }
}
