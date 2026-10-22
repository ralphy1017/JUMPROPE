## Deep stacker + Alignment

library(Rfits)
library(Rwcs)
library(ProPane)
library(ProFound)
library(celestial)
library(foreach)
library(doParallel)
library(data.table)
library(stringr)
library(Cairo)

## -- START OF EDIT --
## [nep-miri] NEP TDF: mosaics from the cal_sky_renorm frames (calstack) on the global grid of make_grids.py
## (~/JP/grids/grid_<inst>.rds: one tangent point and footprint for all imaging, north up, native scale), so every
## mosaic of an instrument is pixel- and WCS-aligned; aligned to ~/JP/refcat_nep.csv (NIRCam F444W, HST F606W, Gaia DR3).
## Usage: Rscript tile_stack_nep.R <miri|nircam> <FILT regex> <program id | all>
cmd = commandArgs(trailingOnly = TRUE)
inst = cmd[1]; filt = cmd[2]; prog = ifelse(length(cmd) >= 3, cmd[3], "all")
pixscale = ifelse(inst == "miri", 0.11, 0.03)
ref_cat = fread("/Users/ralphy/JP/refcat_nep.csv")
names(ref_cat) = c("RA", "Dec")
tag = paste0(toupper(inst), prog)
input_args = list(
  ref_dir = "/Users/ralphy/JP/PRO",
  super_name = paste0("NEP", tag),
  ref_cat = ref_cat,
  RA = 260.70,
  Dec = 65.80,
  calstack = TRUE,
  grid_size = "",
  mosaic_size = NULL,
  rotation = "North",
  pixelscale = pixscale,
  magzero_out = 23.9,
  program_id = if (prog == "all") NULL else prog,
  FILT = filt,
  ref_frame = sprintf("/Users/ralphy/JP/grids/grid_%s.rds", inst),
  cores = as.integer(Sys.getenv("JUMPROPE_cores_pro", "12")),
  cores_search = as.integer(Sys.getenv("JUMPROPE_cores_pro", "12"))
)
additional_args = list(
  mosaic_dir = paste0("/Users/ralphy/JP/PRO/Mosaics/", inst, "/", prog, "/"),
  dump_dir = "/Users/ralphy/JP/PRO/dump/",
  cal_sky_info_stub = "/Users/ralphy/JP/PRO/Pro1oF/cal_sky_info.csv",
  patch_dir = "/Users/ralphy/JP/PRO/Patch_Stacks/",
  cal_sky_renorm_dir = "/Users/ralphy/JP/PRO/Pro1oF/cal_sky_renorm/",
  sky_frames_dir = "/Users/ralphy/JP/PRO/sky_pro/sky_frames/"
)
dir.create(additional_args$mosaic_dir, recursive = TRUE, showWarnings = FALSE)
## -- END OF EDIT --
input_args$additional_args = additional_args
deep_stacker = function(input_args){
  
  ## Find aligning frames in search radius, align with ProPaneTweakCat and stack with ProPane
  
  additional_args = input_args$additional_args
  if( !is.null(input_args$ref_dir) & !input_args$calstack ){
    patch_dir = paste0(input_args$ref_dir, "/Patch_Stacks")
    dump_dir = paste0(input_args$ref_dir, "/dump")
    cal_sky_info = fread(paste0(input_args$ref_dir, "/Pro1oF/cal_sky_info.csv"))
    mosaic_dir = paste0(input_args$ref_dir, "/Mosaic_Stacks/")
  }else if ( !is.null(input_args$ref_dir) & input_args$calstack ){
    cal_sky_renorm_dir = paste0(input_args$ref_dir, "/Pro1oF/cal_sky_renorm/")
    sky_frames_dir = paste0(input_args$ref_dir, "/sky_pro/sky_frames/")
    dump_dir = paste0(input_args$ref_dir, "/dump")
    cal_sky_info = fread(paste0(input_args$ref_dir, "/Pro1oF/cal_sky_info.csv"))
    mosaic_dir = paste0(input_args$ref_dir, "/Mosaic_Stacks/")
  }else if ( is.null(input_args$ref_dir) & !input_args$calstack ){
    patch_dir = additional_args$patch_dir
    dump_dir = additional_args$dump_dir
    cal_sky_info = fread(additional_args$cal_sky_info_stub)
    mosaic_dir = additional_args$mosaic_dir
  }else if ( is.null(input_args$ref_dir) & input_args$calstack ){
    cal_sky_renorm_dir = additional_args$cal_sky_renorm_dir
    sky_frames_dir = additional_args$sky_frames_dir
    dump_dir = additional_args$dump_dir
    cal_sky_info = fread(additional_args$cal_sky_info_stub)
    mosaic_dir = additional_args$mosaic_dir
  }
  
  mosaic_invar = paste0(mosaic_dir, "/inVar/")
  mosaic_med = paste0(mosaic_dir, "/Median/")
  mosaic_patch = paste0(mosaic_dir, "/Patch/")
  dir.create(mosaic_dir, recursive = T)
  dir.create(mosaic_invar, recursive = T)
  dir.create(mosaic_med, recursive = T)
  dir.create(mosaic_patch, recursive = T)

  VIDS = paste0(cal_sky_info$VISIT_ID)
  
  if(is.null(input_args$mosaic_size)){
    search_rad = 2.0
  }else{
    search_rad = input_args$mosaic_size
  }
  if(is.null(input_args$program_id)){
    program_id = ""
  }else{
    program_id = input_args$program_id
  }
  
  if(input_args$calstack){
    ## Pull the files form the cal_sky_renorm directory. Must have the cal_sky_info.csv
    
    list_files = cal_sky_info$full[
      grepl(paste0("^",program_id), cal_sky_info$VISIT_ID)
    ]
    list_files_names = cal_sky_info$stub[
      grepl(paste0("^",program_id), cal_sky_info$VISIT_ID)
    ]
    
    message("Searching for frames in ", input_args$RA, " ", input_args$Dec, " rad=", search_rad, "deg")
    find_frames = propaneFrameFinder(
      filelist = list_files,
      RAcen = input_args$RA,
      Deccen = input_args$Dec,
      rad = search_rad,
      extlist = 2, ## WCS for cal_sky_renorm
      plot=F, 
      cores = input_args$cores_search
    )
    
    find_frames$FILT = Rfits_key_scan(
      find_frames$full, 
      keylist = c("FILTER"),
      extlist = 1,
      cores = input_args$cores_search
    )$FILTER
    find_frames$MAGZERO_FIX = cal_sky_info$MAGZERO_FIX[cal_sky_info$full %in% find_frames$full]
    
  }else{
    ## Pull the files form the stack_patch directory
    list_files = list.files(
      path = patch_dir, 
      pattern = paste0("^.*?patch_.*?(", input_args$program_id, ").*\\.fits$"),
      full.names = T
    )
    
    list_files_names = list.files(
      path = patch_dir, 
      pattern = paste0("^.*?patch_.*?(", input_args$program_id, ").*\\.fits$"),
      full.names = F
    )
    
    message("Searching for frames in ", input_args$RA, " ", input_args$Dec, " rad=", search_rad, "deg")
    find_frames = propaneFrameFinder(
      filelist = list_files,
      RAcen = input_args$RA,
      Deccen = input_args$Dec,
      rad = search_rad,
      plot=F,
      cores = input_args$cores_search
    )
    filters_all = str_extract(find_frames$file, pattern = regex("F(\\d+).[W2WMN]")) ## Regex pattern all kinds of filters
    find_frames$FILT = filters_all
  }
  
  UNIQUE_VIDS = VIDS[sapply(VIDS, function(x){any(grepl(x,find_frames$file))} )==TRUE]

  stack_grid = cal_sky_info[paste0(cal_sky_info$VISIT_ID) %in% UNIQUE_VIDS, c("VISIT_ID", "FILTER", "DETECTOR")]
 
  if(input_args$calstack){
    input_args$grid_size = c("") ## So grep all of the cal_sky_renorm files 
  }
  for(grid_size in c(input_args$grid_size)){
    
    file_info = find_frames[grepl(paste0(grid_size, "|MIRI"), find_frames$file), ] ## Force find MIRI
    
    if(is.null(input_args$ref_frame)){
      if(input_args$calstack){
        wcs = propaneGenWCS(
          filelist = file_info$full, 
          rotation = input_args$rotation, 
          pixscale = input_args$pixelscale, 
          extlist = 2,
          cores = input_args$cores_search
        )
        saveRDS(wcs, paste0(mosaic_dir, "/wcs_", input_args$super_name, ifelse(grid_size == "", ".rds", paste0("_", grid_size, ".rds"))))
      }else{
        wcs = propaneGenWCS(
          filelist = file_info$full, 
          rotation = input_args$rotation, 
          pixscale = input_args$pixelscale, 
          extlist = 1,
          cores = input_args$cores_search
        )
        saveRDS(wcs, paste0(mosaic_dir, "/wcs_", input_args$super_name, ifelse(grid_size == "", ".rds", paste0("_", grid_size, ".rds"))))
      }
    }else if(endsWith(input_args$ref_frame, ".fits")){
      temp = Rfits_read_header(
        input_args$ref_frame
      )
      wcs = Rwcs_setkeyvalues(
        CRVAL1 = temp$keyvalues$CRVAL1,
        CRVAL2 = temp$keyvalues$CRVAL2,
        NAXIS1 = temp$keyvalues$NAXIS1,
        NAXIS2 = temp$keyvalues$NAXIS2,
        CRPIX1 = temp$keyvalues$CRPIX1,
        CRPIX2 = temp$keyvalues$CRPIX2,
        CTYPE1 = temp$keyvalues$CTYPE1,
        CTYPE2 = temp$keyvalues$CTYPE2,
        CUNIT1 = temp$keyvalues$CUNIT1,
        CUNIT2 = temp$keyvalues$CUNIT2,
        CD1_1 = temp$keyvalues$CD1_1,
        CD1_2 = temp$keyvalues$CD1_2,
        CD2_1 = temp$keyvalues$CD2_1,
        CD2_2 = temp$keyvalues$CD2_2
      )
    }else if(endsWith(input_args$ref_frame, ".rds")){
        wcs = readRDS(input_args$ref_frame)
    }else{
        stop("Invalid WCS - please supply a fits file or saved RDS.")
    }
    
    ref_cat = input_args$ref_cat
    
    UNIQUE_FILTERS = unique(stack_grid$FILTER)
    UNIQUE_FILTERS = UNIQUE_FILTERS[!grepl("CLEAR", UNIQUE_FILTERS) & UNIQUE_FILTERS %in% file_info$FILT]
    
    count = TRUE
    for(i in which(grepl(input_args$FILT, UNIQUE_FILTERS))){
      
      file_info_filt = file_info[file_info$FILT == paste0(UNIQUE_FILTERS[i]),]
      filenames = file_info_filt$full
 
      if(input_args$calstack){

        image_list = lapply(1:dim(file_info_filt)[1], function(kk){
          ## Same masking as in gen_stack
          temp_image = Rfits_read_image(file_info_filt[kk,'full'], ext=2)
          temp_mask = Rfits_read_image(file_info_filt[kk,'full'], ext=4, header=FALSE); temp_mask = array(as.numeric(temp_mask), dim = dim(temp_mask)) ## [nep-miri] integer64 DQ (jwst 3)
          temp_image = propaneBadPix(
            image = temp_image,
            patch = T
          )
          JWST_cal_mask = profoundDilate(temp_mask %% 2 == 1, size=3)
          temp_image$imDat[JWST_cal_mask==1] = NA
          return(temp_image)
        })
        
        inVar_list = lapply(1:dim(file_info_filt)[1], function(kk){
          sky_file = paste0(sky_frames_dir, sub('_rem', '', file_info_filt$stub[kk]),'_',file_info_filt$FILT[kk],'.fits')
          Rfits::Rfits_read_key(sky_file, 'SKYRMS')^-2
        }) ## Same logic that is in the gen_stack module in all_codes_process.R
        
        weight_list = lapply(1:dim(file_info_filt)[1], function(x){
        matrix(1L, file_info_filt$dim_1[x], file_info_filt$dim_2[x]) ## Might need this for MIRI
        })
        
        magzero_list = file_info_filt$MAGZERO_FIX
      }else{
        image_extlist = sapply(filenames, function(x)Rfits_extname_to_ext(x, extname = "image"))
        inVar_extlist = sapply(filenames, function(x)Rfits_extname_to_ext(x, extname = "inVar"))
        weight_extlist = sapply(filenames, function(x)Rfits_extname_to_ext(x, extname = "weight"))
        
        image_list = Rfits_make_list(
          filelist = filenames,
          extlist = image_extlist,
          pointer = T
        )
        weight_list = Rfits_make_list(
          filelist = filenames,
          extlist = weight_extlist,
          pointer = T,
          header = F
        )
        inVar_list = Rfits_make_list(
          filelist = filenames,
          extlist = inVar_extlist,
          pointer = T,
          header = F
        )
        magzero_list = rep(23.9, length(filenames))
      }
      
      if(count){
        CairoPNG(paste0(mosaic_dir,input_args$super_name, "_footprints.png"))
        for(k in 1:length(image_list)){
          if(k == 1){
            Rwcs_overlap(
              keyvalues_test = image_list[[k]]$keyvalues, keyvalues_ref = wcs, plot = T
            )
          }else{
            Rwcs_overlap(
              keyvalues_test = image_list[[k]]$keyvalues, keyvalues_ref = wcs, plot = T, add = T
            )
          }
        }
        dev.off()
        count = FALSE
      }
      
      tweak_idx = c()
      for(k in 1:length(image_list)){
        
        message(
          paste0("Tweaking ", filenames[k])
        )
        ## Default ProFound source detection, ends up being ~1.5 sigma source detect level
        pro_test = profoundProFound( 
          image = image_list[[k]][,],
          magzero = magzero_list[k],
          mask = is.infinite(image_list[[k]][,]$imDat),
          rem_mask = T
        )
        
        mag = ifelse(is.na(pro_test$segstats$mag), 35, pro_test$segstats$mag)
        match_cat = coordmatch(
          coordref = ref_cat,
          coordcompare = pro_test$segstats[mag < quantile(mag[mag<35], 0.5), c("RAmax", "Decmax")] ## tweak on sources brighter than 50th percentile
        )
        
        if(any(is.na(match_cat$bestmatch))){
          tweak_cat = list(par = c(0,0,0)) ## No matches => nothing to tweak on unfortunately...
          twIDX = k ## [nep-miri] keep the frame with its pipeline WCS (it was dropped from the stack)
        }else{
          pix_cat = Rwcs_s2p(RA = ref_cat$RA, Dec = ref_cat$Dec, keyvalues = image_list[[k]]$keyvalues)
          propaneTweak_cat_ref = pix_cat[match_cat$bestmatch$refID, ]
          if( is.null(dim(propaneTweak_cat_ref)) ){
            tweak_cat = list(par = c(0,0,0))
            twIDX = k ## [nep-miri] keep the frame untweaked
          }else{
            tweak_cat = propaneTweakCat(
              cat_ref = propaneTweak_cat_ref,
              cat_pre_fix = pro_test$segstats[match_cat$bestmatch$compareID,c("xmax","ymax")],
              delta_max = c(20,1),
              mode = "pix"
            )
            twIDX = k
          }
        }
        
        tempim = image_list[[k]][,]
        tempim$imDat[is.infinite(tempim$imDat)] = NA
        image_list[[k]] = propaneWCSmod(
          tempim,
          delta_x = tweak_cat$par[1],
          delta_y = tweak_cat$par[2],
          delta_rot = tweak_cat$par[3]
        )
        rm(tempim)
        
        if(!input_args$calstack){
          ## Have to adjust the WCS for Rfits objects when doing patch_stack mosaicking
          weight_list[[k]] = propaneWCSmod(
            weight_list[[k]][,],
            delta_x = tweak_cat$par[1],
            delta_y = tweak_cat$par[2],
            delta_rot = tweak_cat$par[3]
          )
          
          inVar_list[[k]] = propaneWCSmod(
            inVar_list[[k]][,],
            delta_x = tweak_cat$par[1],
            delta_y = tweak_cat$par[2],
            delta_rot = tweak_cat$par[3]
          )
        }
        if(!is.na(twIDX)){
          tweak_idx = c(tweak_idx, twIDX)
        }
      }
      
      cores = ifelse(is.null(input_args$cores), 1, input_args$cores)
      deep_frame = propaneStackWarpInVar(
        image_list = image_list[tweak_idx],
        inVar_list = inVar_list[tweak_idx],
        weight_list = weight_list[tweak_idx],
        keyvalues_out = wcs,
        magzero_in = magzero_list[tweak_idx], ## Use appropriate magzero ins
        magzero_out = input_args$magzero_out,
        direction="backward",
        dump_frames = T,
        dump_dir = paste0(dump_dir, "/", input_args$super_name, "/", grid_size, "/", UNIQUE_FILTERS[i], "/"),
        multitype = "cluster",
        cores = cores,
        cores_warp = 1
      )
      
      deep_frame$image$imDat[is.infinite(deep_frame$image$imDat)] = NA
      deep_frame$info = file_info_filt
      
      Rfits_write(
        deep_frame,
        paste0(mosaic_invar, "/stack_", input_args$super_name, "_", UNIQUE_FILTERS[i], ifelse(grid_size == "", ".fits", paste0("_", grid_size, ".fits")))
      )
      
      med_stack = propaneStackWarpMed(
        dirlist = deep_frame$dump_dir,
        pattern = glob2rx("*image*.fits"),
        keyvalues_out = deep_frame$image$keyvalues, 
        cores = cores, 
        multitype = "cluster"
      )
      
      Rfits_write(
        med_stack,
        paste0(mosaic_med, "/med_", input_args$super_name, "_", UNIQUE_FILTERS[i], ifelse(grid_size == "", ".fits", paste0("_", grid_size, ".fits")))
      )
      
      patch_stack = propanePatch(
        image_inVar = deep_frame$image,
        image_med = med_stack$image
      )
      temp = deep_frame
      temp$image = patch_stack$image
      
      Rfits_write(
        temp,
        paste0(mosaic_patch, "/patch_", input_args$super_name, "_", UNIQUE_FILTERS[i], ifelse(grid_size == "", ".fits", paste0("_", grid_size, ".fits")))
      )
      
      rm(deep_frame)
      rm(med_stack)
      rm(patch_stack)
      rm(temp)
      gc()
    }
  }
}

if (sys.nframe() == 0){
  deep_stacker(input_args = input_args)
}
