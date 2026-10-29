## [nep-miri] Behavioural check: preserve a masked source and fit an exposed wisp.
env <- new.env(parent=globalenv())
for(e in parse('PROCESS/all_codes_process.R'))
 if(is.call(e)&&length(e)>=3L&&is.symbol(e[[2]])&&as.character(e[[2]])=='wispFixer') eval(e,env)
`[.mask_test_image` <- function(x,i,j,...) x$imDat
image <- function(a)structure(list(imDat=a,keyvalues=list()),class='mask_test_image')
env$profoundImBlur <- function(image,sigma)image
ref <- image(matrix(seq_len(1024)/1024,32,32))
science <- 2*ref$imDat;science[10,10] <- science[10,10]+100;science[12,12] <- science[12,12]+1000
mask <- matrix(FALSE,32,32);mask[11:13,11:13] <- TRUE
prior <- matrix(.25,32,32)
run <- function(a,protect=mask)env$wispFixer(image(a),ref,ref_is_warped=TRUE,
 source_mask=protect,source_fill=prior,sigma_hi=2,sigma_lo=2,clip_threshold=1)
one <- run(science);science[12,12] <- science[12,12]+1000;two <- run(science)
stopifnot(one$wisp_template[10,10]>90,
 all(one$wisp_template[mask]==prior[mask]),
 one$wisp_template[12,12]==two$wisp_template[12,12],
 abs(two$wisp_fix$imDat[12,12]-one$wisp_fix$imDat[12,12]-1000)<1e-10,
 all(is.finite(one$wisp_template)))
plain <- env$wispFixer(image(science),ref,ref_is_warped=TRUE,sigma_hi=2,sigma_lo=2,clip_threshold=1)
empty <- run(science,matrix(FALSE,32,32))
stopifnot(identical(plain$wisp_template,empty$wisp_template))
invalid <- try(run(science,matrix(FALSE,16,16)),silent=TRUE)
stopifnot(inherits(invalid,'try-error'))
cat('PASS: exposed wisp retained, masked source response preserved, empty-mask compatibility, invalid mask rejected\n')
