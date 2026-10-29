"""[nep-miri] Prepare portable independent residual assets from NMF working copies.

Manifest: {"frames": [{"input": "..._cal.fits"}, ...]}. Each input must contain
SCI_ORIG, ERR, DQ and NMF WISP_TEMPLATE/WISP_SOURCE_MASK/WISP_ERR. Alternatively,
provide an explicit `prior` FITS path and `prior_method: "nmf"` per record.
No input science file is modified. Run with a caller-managed CPU budget.
"""
import os
for _key in ('OMP_NUM_THREADS','OPENBLAS_NUM_THREADS','MKL_NUM_THREADS'):
    os.environ.setdefault(_key,'1')
import argparse,hashlib,json,shutil
from pathlib import Path
from concurrent.futures import ProcessPoolExecutor
import numpy as np
from astropy.io import fits
import wisp_continuous as continuous
from vendor import nmfwisp


def digest(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def image_digest(data):return hashlib.sha256(np.asarray(data,dtype='<f4').tobytes()).hexdigest()
def load(record):
    path=Path(record['input'])
    with fits.open(path,memmap=False) as h:
        data=np.asarray(h['SCI_ORIG'].data,float);err=np.asarray(h['ERR'].data,float)
        good=np.isfinite(data)&np.isfinite(err)&(err>0)&((h['DQ'].data.astype(np.uint32)&1)==0)
        detector=h[0].header['DETECTOR'];band=h[0].header['FILTER']
        method=h['SCI'].header.get('WISPMETH','')
    if record.get('prior'):
        if record.get('prior_method')!='nmf':raise ValueError('Explicit priors require prior_method="nmf"')
        prior_path=Path(record['prior'])
    else:
        if method.upper()!='NMF':raise ValueError(f'{path}: prepare from the NMF method, not a dynamic model')
        prior_path=path
    with fits.open(prior_path,memmap=False) as h:
        prior=np.asarray(h['WISP_TEMPLATE'].data,float);mask=h['WISP_SOURCE_MASK'].data!=0
        error=np.asarray(h['WISP_ERR'].data,float)
    if not (data.shape==prior.shape==mask.shape==error.shape):raise ValueError('Prior shape mismatch')
    if not np.isfinite(prior).all():raise ValueError('Nonfinite prior')
    good[:4]=good[-4:]=False;good[:,:4]=good[:,-4:]=False
    return data,good,prior,mask,error,detector,band,prior_path


def group_worker(job):
    group,output,templates,hi,lo,clip=job;output=Path(output)
    arrays=[];goods=[];metadata=[]
    for record in group:
        data,valid,prior,mask,error,det,band,prior_path=load(record)
        _,_,support,high=nmfwisp.load_wisp_templates(templates,det,band)
        if support is None or support.shape!=data.shape:raise ValueError('Missing matching templates')
        stem=Path(record['input']).stem.removesuffix('_cal')
        destination=output/'priors'/stem/'independent.fits';destination.parent.mkdir(parents=True,exist_ok=True)
        if prior_path.resolve()==destination.resolve():pass
        elif record.get('prior'):
            shutil.copyfile(prior_path,destination)
        else:
            hd=[fits.PrimaryHDU()]
            for name,a in [('WISP_TEMPLATE',prior),('WISP_SOURCE_MASK',mask),('WISP_ERR',error)]:
                hd.append(fits.ImageHDU(a.astype(np.uint8 if name=='WISP_SOURCE_MASK' else np.float32),name=name))
            fits.HDUList(hd).writeto(destination,overwrite=True,checksum=True)
        sky,stripes,_=continuous.baseline(data,mask,support,valid)
        arrays.append(np.asarray(data-sky-stripes-prior,np.float32));goods.append(valid&~mask)
        metadata.append(dict(frame=stem,original_sha256=image_digest(data),sky=sky,prior_sha256=digest(destination)))
    arrays=np.asarray(arrays);goods=np.asarray(goods)
    for i,meta in enumerate(metadata):
        refs=[j for j in range(len(group)) if j!=i]
        basis,count=continuous.residual_basis(arrays[refs],goods[refs],support,hi,lo,clip)
        header=fits.Header();header['SIG_HI']=hi;header['SIG_LO']=lo;header['CLIP']=clip
        header['ORIGSHA']=meta['original_sha256'];header['DETECTOR']=det;header['NREF']=len(refs)
        hd=[fits.PrimaryHDU(header=header)]
        for name,a in [('BROAD',basis[0]),('FINE',basis[1]),('SUPPORT',support),('HIGH_SNR',high),('COUNT',count)]:
            hd.append(fits.ImageHDU(a.astype(np.uint16 if name=='COUNT' else np.uint8 if name in ('SUPPORT','HIGH_SNR') else np.float32),name=name))
        target=output/'basis'/(meta['frame']+'.fits');target.parent.mkdir(parents=True,exist_ok=True)
        temporary=target.with_suffix('.tmp.fits');fits.HDUList(hd).writeto(temporary,overwrite=True,checksum=True);temporary.replace(target)
        info=dict(target=meta['frame'],reference_frames=[metadata[j]['frame'] for j in refs],target_excluded=True,
            **meta,parameters=dict(method='continuous_dynamic',sigma_hi=hi,sigma_lo=lo,clip_threshold=clip),
            code_sha256=digest(Path(continuous.__file__)),basis_sha256=digest(target))
        target.with_suffix('.json').write_text(json.dumps(info,indent=2))
        print('Prepared',meta['frame'],flush=True)


def verify(records,basis_dir,prior_dir):
    for record in records:
        data,_,_,_,_,det,band,_=load(record)
        stem=Path(record['input']).stem.removesuffix('_cal');path=Path(basis_dir)/(stem+'.fits')
        meta=json.loads(path.with_suffix('.json').read_text());prior=Path(prior_dir)/stem/'independent.fits'
        if meta['target']!=stem or stem in meta['reference_frames']:raise ValueError('Target leaked into reference set')
        if meta['original_sha256']!=image_digest(data):raise ValueError('Input calibration changed')
        if meta['basis_sha256']!=digest(path) or meta['prior_sha256']!=digest(prior):raise ValueError('Prepared asset changed')
        with fits.open(path,memmap=False) as h:
            if h[0].header['DETECTOR']!=det or h[0].header['ORIGSHA']!=meta['original_sha256']:raise ValueError('Header mismatch')
            if h[0].header['NREF']!=len(meta['reference_frames']):raise ValueError('Reference membership mismatch')
        print('Verified',stem,flush=True)


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--manifest',required=True,type=Path)
    p.add_argument('--output',type=Path);p.add_argument('--template-dir');p.add_argument('--workers',type=int,default=1)
    p.add_argument('--sigma-hi',type=float,default=2);p.add_argument('--sigma-lo',type=float,default=2)
    p.add_argument('--clip-threshold',type=float,default=.99999)
    p.add_argument('--verify-only',action='store_true');p.add_argument('--basis-dir');p.add_argument('--prior-dir')
    a=p.parse_args();records=json.loads(a.manifest.read_text())['frames']
    stems=[Path(r['input']).stem.removesuffix('_cal') for r in records]
    if len(set(stems))!=len(stems):p.error('Duplicate frame names')
    if a.verify_only:
        if not a.basis_dir or not a.prior_dir:p.error('--verify-only needs --basis-dir and --prior-dir')
        verify(records,a.basis_dir,a.prior_dir);return
    if not a.output or not a.template_dir:p.error('--output and --template-dir are required')
    if a.workers<1 or min(a.sigma_hi,a.sigma_lo)<=0 or not .5<a.clip_threshold<=1:p.error('Invalid fitting settings')
    groups={}
    for record in records:
        hd=fits.getheader(record['input']);groups.setdefault((hd['DETECTOR'],hd['FILTER']),[]).append(record)
    if any(len(g)<3 for g in groups.values()):p.error('At least three exposures per detector/filter are required; seven were validated')
    jobs=[(g,str(a.output.resolve()),a.template_dir,a.sigma_hi,a.sigma_lo,a.clip_threshold) for g in groups.values()]
    with ProcessPoolExecutor(max_workers=a.workers) as pool:list(pool.map(group_worker,jobs))
    options=dict(method='continuous_dynamic',template_dir=str(Path(a.template_dir).resolve()),
        sigma_hi=a.sigma_hi,sigma_lo=a.sigma_lo,clip_threshold=a.clip_threshold,
        prepared_prior_dir=str((a.output/'priors').resolve()),residual_basis_dir=str((a.output/'basis').resolve()))
    (a.output/'parameters.json').write_text(json.dumps(options,indent=2))

if __name__=='__main__':main()
