###########################
## Initialise parameters ##
###########################

initialise_params = function(){
 
  ## Edit this:

  ## set up the keep_trend data
  additional_params = list(
    ## Keep trend data determines the aggressiveness of the 1/f. If nothing in this data frame, then default 1/f proceeds. 
    ## Default should be good for most blank fields.
    
    skip_completed_files = FALSE, ## Only process files (in any step) that do not exist in the specified directory
    
    ## vlarge for big objects that fill frame e.g., VV191. Least aggressive 1/f.
    ID_vlarge = data.frame(
      VISIT_ID = c(
        2561001003 #<-- Put 10 digit VISITIDs here, e.g., 1176341001, 1176361001
      ),
      MODULE = c(
       'A'   #<-- Put 'A'/'B' here 
      )
    ),
    
    ## large for crowded fields or wispy fields e.g., SMACS Cluster Module B. Less aggressive 1/f.
    ID_large = data.frame(
      VISIT_ID = c(
        2561001003
      ),
      MODULE = c(
       'B' 
      )
    ),
    
   ## overwrite and use one 1/f setting for everything. 
   ## so you don't have to laboriously type out every single VISITID and MODULE combination :D
   ow_vlarge = FALSE,
   ow_large = FALSE,
   
   ## Claws removal mode
   ## I.e., perform "wisp removal" algorithm on all NIRCam short wavelength detectors
   ## and not only wisp affected [A3,A4,B3,B4]
   do_claws = FALSE,

   ## Wisp removal settings, passed to wispFixer (NIRCam A3, A4, B3, B4; all SW detectors with do_claws).
   ## sigma_lo = NULL turns the low-pass fill off. Visits listed in ID_large/ID_vlarge always use sigma_lo = NULL.
   wisp_params = list(
     source_threshold = 0.95, ## quantile of the LW reference above which pixels are real sources
     scale_threshold = 0.95, ## quantile of the SW/LW flux ratio used to scale out sources
     sky_threshold = 0.5, ## quantile used for the sky level
     clip_threshold = 0.9999, ## clip the brightest/faintest template pixels (1 = no clipping)
     sigma_hi = 2, ## Gaussian smoothing of the wisp template (pixels)
     sigma_lo = 2 ## low-pass smoothing used to fill template holes (pixels)
   ),

   ## ProPane stacks, patched stacks and RGBs. FALSE gives only Pro1oF/cal and Pro1oF/cal_sky_renorm
   ## (NIRCam long wavelength stacks are still made, because wisp removal uses them as the reference).
   make_stacks = TRUE,

   ## Path to reference astrometric catalogue - to make the ProPane stacks
   tweak_catalogue = NULL, ## NULL will have no internal tweak

   NAXIS_long = NULL, ## Size of the long pixel scales mosaic, keep NULL for default (3000 pixels) 
   NAXIS_short = NULL, ## Size of the short pixel scales mosaic, keep NULL for default (6000 pixels) 
   module_list = NULL, ## What modules should we stack, options are ('NRCA_short', 'NRCA_long', 'NRCB_short', 'NRCB_long', 'NIS', 'MIRIMAGE')
   
   parallel_type = NULL ## type options for makeCluster in parallel for stacking and wisp removal, type='PSOCK' might be more stable on Linux systems
  )
  ## Finish editing

  return( mget(ls()) )
}
