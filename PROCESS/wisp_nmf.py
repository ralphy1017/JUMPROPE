"""[nep-miri] Optional masked JADES NMF wisp estimator; never modifies inputs.
Upstream: Wu et al. 2026, arXiv:2601.15958, bd6609fa9a003d1737e3da6f7e266cf10d984bf9.
Sky and stripes are nuisance estimates only; the existing JumProPe stages subtract them.
"""
import argparse, json, hashlib
from pathlib import Path
import numpy as np
from astropy.io import fits
from astropy.wcs import WCS
from scipy import ndimage as ndi
from vendor import nmfwisp as nmf


def source_mask(reference, extra=None, dilation=8):
    valid=np.isfinite(reference)
    ref=np.where(valid,reference,0.)
    smooth=ndi.gaussian_filter(ref,1.5)
    center=np.median(smooth[valid])
    noise=1.4826*np.median(np.abs(smooth[valid]-center))
    if not np.isfinite(noise) or noise<=0:raise ValueError('Invalid reference noise')
    # Deep LW detection includes extended wings; no SW amplitude clipping.
    mask=smooth>center+2*noise
    for width in (4,12):
        s=ndi.gaussian_filter(ref,width)
        med=np.median(s[valid]); sig=1.4826*np.median(np.abs(s[valid]-med))
        mask |= s>med+3*sig
    if extra is not None:mask |= extra
    mask=ndi.binary_dilation(mask,iterations=int(dilation)) if dilation else mask
    # [nep-miri] Protect low surface-brightness wings around bright LW sources.
    # Thin segmentation dilation alone failed the 40-pixel halo injection test.
    bright=ndi.gaussian_filter(ref,2)
    eligible=valid & mask
    eligible[:170]=eligible[-170:]=False
    eligible[:,:170]=eligible[:,-170:]=False
    peaks=eligible & (bright==ndi.maximum_filter(bright,size=25)) & (bright>center+8*noise)
    yy,xx=np.where(peaks)
    order=np.argsort(bright[yy,xx])[::-1]
    chosen=[]
    for k in order:
        x,y=int(xx[k]),int(yy[k])
        if all((x-x0)**2+(y-y0)**2>340**2 for x0,y0 in chosen):chosen.append((x,y))
        if len(chosen)==8:break
    seeds=np.zeros(mask.shape,bool)
    for x,y in chosen:seeds[y,x]=True
    if chosen:mask |= ndi.distance_transform_edt(~seeds)<=160
    return mask | ~valid


def project_segmentation(path, header, shape):
    with fits.open(path,memmap=True,do_not_scale_image_data=True) as h:
        ext=next(x for x in h if x.data is not None and x.data.ndim==2)
        src=WCS(ext.header).celestial; dst=WCS(header).celestial
        if not src.has_celestial or not dst.has_celestial:raise ValueError('Segmentation needs celestial WCS')
        result=np.zeros(shape,bool)
        for y in range(0,shape[0],128):
            yy,xx=np.mgrid[y:min(y+128,shape[0]),:shape[1]]
            ra,dec=dst.pixel_to_world_values(xx,yy); sx,sy=src.world_to_pixel_values(ra,dec)
            finite=np.isfinite(sx)&np.isfinite(sy)
            ix=np.rint(np.where(finite,sx,-1)).astype(int);iy=np.rint(np.where(finite,sy,-1)).astype(int)
            ok=finite&(ix>=0)&(iy>=0)&(ix<ext.data.shape[1])&(iy<ext.data.shape[0])
            block=np.zeros(xx.shape,bool);block[ok]=(ext.data[iy[ok],ix[ok]].astype(float)*ext.header.get("BSCALE",1)+ext.header.get("BZERO",0))>0
            result[y:y+len(block)]=block
    return result


def fit(data,err,reference,detector,band,templates,extra=None,dilation=8,correct_1f=True):
    bases,te,region,high=nmf.load_wisp_templates(templates,detector,band)
    if bases is None:raise ValueError(f'No templates for {detector}/{band}')
    if bases.shape[1:]!=data.shape:raise ValueError('Only matching full-frame templates supported')
    protected=source_mask(reference,extra,dilation)
    invalid=~np.isfinite(data)|~np.isfinite(err)|(err<=0)
    invalid[:4]=invalid[-4:]=True;invalid[:,:4]=invalid[:,-4:]=True
    mask=protected|invalid
    sky_pixels=~mask&~region
    fit_pixels=~mask&high
    if sky_pixels.sum()<1000 or fit_pixels.sum()<500:raise ValueError('Insufficient unmasked sky/wisp support')
    sky=float(np.median(data[sky_pixels])); clean=np.where(invalid,0,data-sky)
    errors=np.where(invalid,np.inf,err).copy()
    # Published NNLS solve and iterative nuisance correction, with fixed external basis.
    stripes=np.zeros_like(clean)
    for i in range(4 if correct_1f else 1):
        _,model,model_err,amps,ae=nmf._subtract_wisp(clean-stripes,bases,errors.copy(),mask,
            template_err=te,high_snr_region=high)
        if i<3 and correct_1f:
            residual=np.where(mask,np.nan,clean-model)
            with np.errstate(invalid='ignore'):
                row=np.nanmedian(residual,axis=1)[:,None]
                col=np.nanmedian(residual-row,axis=0)[None,:]
            stripes=np.nan_to_num(row)+np.nan_to_num(col)
            stripes-=np.median(stripes[sky_pixels])
    if not np.all(np.isfinite(model)):raise ValueError('Nonfinite wisp model')
    model[invalid]=0;model_err[invalid]=0
    return dict(model=model,error=model_err,source_mask=protected,fit_mask=fit_pixels,stripes=stripes,
        meta=dict(method='nmf',sky=sky,amplitudes=amps.ravel().tolist(),amplitude_errors=ae.ravel().tolist(),
        source_fraction=float(protected.mean()),n_fit=int(fit_pixels.sum()),n_sky=int(sky_pixels.sum()),
        correct_1f=correct_1f,mask_dilate=dilation,n_components=len(bases),
        bright_guard_radius=160,max_bright_groups=8,min_bright_group_separation=340))


def main():
    p=argparse.ArgumentParser();p.add_argument('--input',required=True);p.add_argument('--reference',required=True)
    p.add_argument('--output',required=True);p.add_argument('--options',required=True);a=p.parse_args()
    opts=json.loads(Path(a.options).read_text())
    if isinstance(opts.get('source_mask_files'),str):opts['source_mask_files']=[opts['source_mask_files']]
    with fits.open(a.input,memmap=False) as h:
        data=np.asarray(h['SCI_ORIG' if 'SCI_ORIG' in h else 'SCI'].data,float)
        err=np.asarray(h['ERR'].data,float);header=h['SCI'].header.copy();primary=h[0].header.copy()
        bad=(h['DQ'].data.astype(np.uint32)&1)!=0
    ref=fits.getdata(a.reference).astype(float)
    err[bad]=np.inf
    extra=np.zeros(data.shape,bool)
    if opts.get('method')!='continuous_dynamic':
        for path in opts.get('source_mask_files',[]):extra |= project_segmentation(path,header,data.shape)
    if opts.get('method')=='continuous_dynamic':
        from wisp_continuous import fit as continuous_fit
        stem=Path(a.input).stem.removesuffix('_cal')
        basis_path=Path(opts['residual_basis_dir'])/(stem+'.fits')
        prior_path=Path(opts['prepared_prior_dir'])/stem/'independent.fits'
        with fits.open(basis_path,memmap=False) as h:
            fingerprint=hashlib.sha256(np.asarray(data,dtype='<f4').tobytes()).hexdigest()
            if fingerprint!=h[0].header['ORIGSHA']:raise ValueError('Residual basis calibration/input mismatch')
            for key,param in [('SIG_HI','sigma_hi'),('SIG_LO','sigma_lo'),('CLIP','clip_threshold')]:
                if abs(h[0].header[key]-opts[param])>1e-12:raise ValueError('Rebuild residual basis for changed parameters')
            basis=np.asarray([h['BROAD'].data,h['FINE'].data],float)
            support=h['SUPPORT'].data!=0;high=h['HIGH_SNR'].data!=0
        basis_meta=json.loads(basis_path.with_suffix('.json').read_text())
        if basis_meta['target']!=stem or stem in basis_meta['reference_frames']:
            raise ValueError('Residual basis is not independent of the target')
        if hashlib.sha256(prior_path.read_bytes()).hexdigest()!=basis_meta['prior_sha256']:
            raise ValueError('Prepared prior changed after residual template construction')
        with fits.open(prior_path,memmap=False) as h:
            prior=np.asarray(h['WISP_TEMPLATE'].data,float);protected=h['WISP_SOURCE_MASK'].data!=0
            prior_error=np.asarray(h['WISP_ERR'].data,float)
        valid=np.isfinite(data)&np.isfinite(err)&(err>0)
        valid[:4]=valid[-4:]=False;valid[:,:4]=valid[:,-4:]=False
        actual=continuous_fit(data,err,prior,protected,support,high,basis,valid)
        result=dict(model=actual['model'],error=prior_error,source_mask=protected,
            fit_mask=valid&~protected&high,stripes=actual['stripes'],meta=actual['meta'])
    else:
        result=fit(data,err,ref,primary['DETECTOR'],primary['FILTER'],opts['template_dir'],extra,
                   opts.get('mask_dilate',8),opts.get('correct_1f',True))
    hd=[fits.PrimaryHDU()]
    for key,name in [('model','WISP_TEMPLATE'),('error','WISP_ERR'),('source_mask','WISP_SOURCE_MASK'),
                     ('fit_mask','WISP_FIT_MASK'),('stripes','WISP_FIT_1F')]:
        hd.append(fits.ImageHDU(result[key].astype(np.float32),name=name))
    fits.HDUList(hd).writeto(a.output,overwrite=True,checksum=True)
    result['meta']['implementation_sha256']=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    result['meta']['upstream_commit']='bd6609fa9a003d1737e3da6f7e266cf10d984bf9'
    result['meta']['options']=opts
    result['meta']['source_mask_inputs']=[dict(path=str(p),size=Path(p).stat().st_size,
        mtime_ns=Path(p).stat().st_mtime_ns) for p in opts.get('source_mask_files',[])]
    Path(a.output+'.json').write_text(json.dumps(result['meta'],indent=2))
if __name__=='__main__':main()
