###########################
## Initialise parameters ##
###########################

initialise_params = function(){
 
  ## Edit this:

  ## set up the keep_trend data
  additional_params = list(
    ## Keep trend data determines the aggressiveness of the 1/f. If nothing in this data frame, then default 1/f proceeds. 
    ## Default should be good for most blank fields.
    
    skip_completed_files = TRUE, ## Only process files (in any step) that do not exist in the specified directory
    
    ## vlarge for big objects that fill frame e.g., VV191. Least aggressive 1/f.
    ID_vlarge = data.frame(
      VISIT_ID = c(
        #<-- Put 10 digit VISITIDs here, e.g., 1176341001, 1176361001
      ),
      MODULE = c(
         #<-- Put 'A'/'B' here
      )
    ),
    
    ## large for crowded fields or wispy fields e.g., SMACS Cluster Module B. Less aggressive 1/f.
    ID_large = data.frame(
      VISIT_ID = c(

      ),
      MODULE = c(

      )
    ),
    
   ## overwrite and use one 1/f setting for everything. 
   ## so you don't have to laboriously type out every single VISITID and MODULE combination :D
   ow_vlarge = TRUE,
   ow_large = FALSE,
   
   ## Claws removal mode
   ## I.e., perform "wisp removal" algorithm on all NIRCam short wavelength detectors
   ## and not only wisp affected [A3,A4,B3,B4]
   do_claws = TRUE,

   ## Wisp removal long-wavelength reference selection.
   ## Same-visit/module references are preferred; a small number of nearby
   ## spatial references can be added from the existing Median_Stacks directory.
   max_wisp_visit_refs = 4,
   max_wisp_spatial_refs = 0,
   max_wisp_refs_per_file = 8,
   cores_wisp = 8,
   wisp_ref_search_radius_arcsec = 120,
   wisp_sigma_lo = NULL, ## Broad Gaussian smoothing scale for the derived wisp template; set NULL to disable
   
   ## Path to reference astrometric catalogue - to make the ProPane stacks
   tweak_catalogue = NULL, ## NULL will have no internal tweak

   NAXIS_long = NULL, ## Size of the long pixel scales mosaic, keep NULL for default (3000 pixels) 
   NAXIS_short = NULL, ## Size of the short pixel scales mosaic, keep NULL for default (6000 pixels) 
   module_list = NULL, ## What modules should we stack, options are ('NRCA_short', 'NRCA_long', 'NRCB_short', 'NRCB_long', 'NIS', 'MIRIMAGE')
   
   parallel_type = 'PSOCK' ## type options for makeCluster in parallel for stacking and wisp removal, type='PSOCK' might be more stable on Linux systems
  )
  ## Finish editing

  return( mget(ls()) )
}
