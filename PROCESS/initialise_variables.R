###########################
## Initialise parameters ##
###########################

initialise_params = function(){
 
  ## Edit this:

  ## set up the keep_trend data
  additional_params = list(
    ## Keep trend data determines the aggressiveness of the 1/f. If nothing in this data frame, then default 1/f proceeds. 
    ## Default should be good for most blank fields.
    
    ## [nep-miri] env-driven so one config file can drive any programme.
    skip_completed_files = toupper(Sys.getenv("JUMPROPE_SKIP_COMPLETED_FILES", "FALSE")) %in% c("T","TRUE","1","YES"),
    
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
   
   ## Path to reference astrometric catalogue - to make the ProPane stacks
   ## [nep-miri] JUMPROPE_TWEAK_CATALOGUE: path to the astrometric reference
   ## catalogue for the ProPane stacks. Empty/unset keeps the upstream NULL
   ## (no internal tweak), which is what we want once the exposures have
   ## already been aligned by jwst tweakreg.
   tweak_catalogue = local({
     v = Sys.getenv("JUMPROPE_TWEAK_CATALOGUE", "")
     if(!nzchar(v) || toupper(v) == "NULL") NULL else v
   }),

   ## [nep-miri] env-driven: JUMPROPE_NAXIS_LONG / JUMPROPE_NAXIS_SHORT.
   NAXIS_long = local({v = Sys.getenv("JUMPROPE_NAXIS_LONG", ""); if(nzchar(v)) as.integer(v) else NULL}),
   NAXIS_short = local({v = Sys.getenv("JUMPROPE_NAXIS_SHORT", ""); if(nzchar(v)) as.integer(v) else NULL}),

   ## [nep-miri] JUMPROPE_MODULE_LIST, comma or pipe separated, e.g.
   ## "MIRIMAGE" or "NRCA_long,NRCB_long". Unset keeps the upstream default.
   module_list = local({
     v = Sys.getenv("JUMPROPE_MODULE_LIST", "")
     if(!nzchar(v)) NULL else trimws(strsplit(v, "[,|]")[[1]])
   }),

   ## [nep-miri] JUMPROPE_PARALLEL_TYPE, default PSOCK: on Linux, forked
   ## workers plus a multi-threaded BLAS can deadlock on a mutex, and PSOCK
   ## workers are fresh processes that avoid it.
   parallel_type = local({
     v = Sys.getenv("JUMPROPE_PARALLEL_TYPE", "PSOCK")
     if(!nzchar(v) || toupper(v) == "NULL") NULL else v
   })
  )
  ## Finish editing

  return( mget(ls()) )
}
