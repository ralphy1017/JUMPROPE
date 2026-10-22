##Query data from MAST and download a .sh script
## Execute shell script to download data

from astroquery.mast import Observations
import os
import numpy as np
import pandas as pd
import argparse
from astropy.io import ascii
import glob
import sys
import shutil
import astropy.units as u
import astropy.table
from astropy.coordinates import SkyCoord
from astropy.table import vstack
import time

Observations.TIMEOUT = 3600 ## Is this useful?
#Observations.enable_cloud_dataset(provider='AWS')

parser = argparse.ArgumentParser(description='Download from MAST')
## Set up input args to run from command line
parser.add_argument('--RA', type=float, nargs="?", help='Central right ascension of catalogue (deg)', default=110.8375)
parser.add_argument('--DEC', type=float, nargs="?", help="Central declination of catalogue (deg)", default=-73.4391)
parser.add_argument('--RAD', type=float, nargs="?", help="Search radius (deg)", default=1.0)
parser.add_argument('--TELESCOPE', type=str, nargs="*", help="Telescope to download")
parser.add_argument('--CAMERA', type=str, nargs="*", help="Camera to download", default = ["ALL"])
parser.add_argument('--FILTER', type=str, nargs="*", help="Filter to download", default = ["ALL"])
parser.add_argument('--STAGE', type=str, nargs="*", default = ["UNCAL"], help='Product level (e.g., UN/CAL for un/cal files)')
parser.add_argument('--VISITID', type=int, nargs="*", help="VISIT ID (e.g., 2736 for SMACS)", default = None)
parser.add_argument('--dry_run', type=bool, nargs=1, help='Only download info table.')

args = parser.parse_args()

def check_dl_size(products_stage2):
    """Check the download size"""
    ind = np.unique(products_stage2['obsID'], return_index = True)[1]
    TBD = np.round(np.sum(products_stage2['size'][ind]) / 10**9, decimals=2)
    Nfiles = len(products_stage2['size'][ind])           
    print(f"You are about to download {Nfiles} images composing of {TBD} GB of Data.")
    input('Press any key to continue...')

def cone_query(ref_dir, ra, dec, rad, telescope, camera, filter, stage, dl_products):
    """Do the cone query"""
    print("Querying observation")

    ## Set up the search cone
    coord = SkyCoord(ra=ra, dec=dec, unit=(u.degree, u.degree), frame="icrs")

    ## convenience stub name for saving the astropy tables
    stub_name = str(round(ra, 2)) + "_" + str(round(dec, 2)) + "_" + str(round(rad, 2)) + "_" + telescope + "_" + camera + "_" + filter + "_" + stage

    ## where we will put the downloaded frames
    dl_dir = os.path.join(
        ref_dir, telescope,
        str(round(ra, 2)) + "_" + str(round(dec, 2)) + "_" +
        str(round(rad, 2)),
        stage
    ) + str("/")

    ## Make sure that we get all HST frames that are part of HAP or HLA products
    telescopes = [telescope]
    if "HST" in telescope:
        telescopes.append("HAP")
        telescopes.append("HLA")

    ## Now the meat of the code. Query MAST.
    if camera == filter == "ALL":
        obs_table = Observations.query_criteria(
            coordinates=coord,
            radius=rad * u.degree,
            project=telescopes,
            dataproduct_type=["IMAGE", "image"]
        )
    elif filter == "ALL" and camera != "ALL":
        obs_table = Observations.query_criteria(
            coordinates=coord,
            radius=rad * u.degree,
            project=telescopes,
            dataproduct_type=["IMAGE", "image"],
            instrument_name=[camera, camera + "/IMAGE"]
        )
    elif camera == "ALL" and filter != "ALL":
        obs_table = Observations.query_criteria(
            coordinates=coord,
            radius=rad * u.degree,
            project=telescopes,
            dataproduct_type=["IMAGE", "image"],
            filters = filter
        )
    else:
        obs_table = Observations.query_criteria(
            coordinates=coord,
            radius=rad * u.degree,
            project=telescopes,
            dataproduct_type=["IMAGE", "image"],
            instrument_name=[camera, camera + "/IMAGE"],
            filters = filter
        )

    if len(obs_table) == 0:
        pass
    else:
        # Observations.enable_cloud_dataset(provider='AWS')
        product_list = [Observations.get_product_list(obs) for obs in obs_table]
        data_products = vstack(product_list)

        products_stage2 = Observations.filter_products(
            data_products,
            extension="fits",
            productSubGroupDescription=stage
        )

        if "HAP-SVM" in set(products_stage2["project"]):
            products_stage2 = products_stage2[products_stage2["project"] == "HAP-SVM"]

        if len(products_stage2) == 0:
            pass
        else:

            os.makedirs(dl_dir, exist_ok=True)
            ascii.write(obs_table, dl_dir + stub_name + '_obs_table.csv', overwrite=True, format='csv')
            ascii.write(products_stage2, dl_dir + stub_name + '_info.csv', overwrite=True, format='csv')

            if dl_products:
                Observations.download_products(
                    products_stage2,
                    download_dir=dl_dir,
                    curl_flag=False,
                    cache=True
                )
            else:
                check_dl_size(products_stage2)
            return obs_table

def vid_query(ref_dir, visit_id, stage, dl_products=False):
    """Do the VID query"""

    pid = str(visit_id)[0:4]

    ## where we will put the downloaded frames
    dl_dir = os.path.join(ref_dir, pid,
                          stage) + str("/")
    
    os.makedirs(dl_dir, exist_ok=True)

    print("Querying observation")
    obs_table = Observations.query_criteria(
        proposal_id=pid,
        project='JWST',
        dataproduct_type = ["IMAGE", "image"]
    )

    product_list = [Observations.get_product_list(obs) for obs in obs_table]
    data_products = vstack(product_list)
    products_stage2 = Observations.filter_products(
        data_products,
        extension="fits",
        productSubGroupDescription=stage,
    )

    visit_ids = np.array([obs[3:13] for obs in products_stage2["obs_id"]])
    idx = np.flatnonzero(np.char.find(visit_ids,str(visit_id))!=-1)

    ## [nep-miri] keep imaging frames of the cameras JumProPe processes (NIRCam, MIRI imager, NIRISS imaging), and drop
    ## the MIRI coronagraphic filters (F1065C etc.) and target-acquisition / other-instrument images
    keep_inst = {"NIRCAM/IMAGE", "MIRI/IMAGE", "NIRISS/IMAGE"}
    obs_ok = {str(o["obsid"]) for o in obs_table
              if str(o["instrument_name"]) in keep_inst and not str(o["filters"]).upper().endswith("C")}
    idx = np.array([i for i in idx if str(products_stage2["parent_obsid"][i]) in obs_ok
                    and any(k in products_stage2["productFilename"][i] for k in ("_nrc", "_mirimage_", "_nis_"))], dtype=int)
    print(f"[nep-miri] {len(idx)} {stage} imaging files for {visit_id}")

    ascii.write(products_stage2, dl_dir + pid + '_' + stage + '.csv', overwrite=True, format='csv')
    ascii.write(obs_table, dl_dir + pid + '_' + stage + '_obs_table.csv', overwrite=True, format='csv')

    if dl_products:
        ## [nep-miri] parallel download (8 threads) into the usual mastDownload/JWST/<obs_id>/ layout, keeping complete files
        from concurrent.futures import ThreadPoolExecutor
        def fetch(i):
            row = products_stage2[i]
            out_dir = os.path.join(dl_dir, "mastDownload", "JWST", str(row["obs_id"]))
            os.makedirs(out_dir, exist_ok=True)
            path = os.path.join(out_dir, str(row["productFilename"]))
            if os.path.isfile(path) and os.path.getsize(path) == int(row["size"]):
                return "kept"
            return Observations.download_file(row["dataURI"], local_path=path)[0]
        with ThreadPoolExecutor(int(os.getenv("JUMPROPE_dl_threads", "8"))) as pool:
            res = list(pool.map(fetch, idx))
        print(f"[nep-miri] downloaded {res.count('COMPLETE')}, kept {res.count('kept')}, other {len(res) - res.count('COMPLETE') - res.count('kept')}")

    else:
        check_dl_size(products_stage2)
    return obs_table

def main(args_dict):
    JUMPROPE_MAST_TOKEN = os.getenv('JUMPROPE_MAST_TOKEN')
    JUMPROPE_DOWNLOAD_DIR = os.getenv('JUMPROPE_DOWNLOAD_DIR')

    if None in [JUMPROPE_DOWNLOAD_DIR]:
        print("Please set ENV variables. ")
        exit()

    if JUMPROPE_MAST_TOKEN is not None:
        ## Used for proprietary data, not a requirement for JP
        my_session = Observations.login(token=str(JUMPROPE_MAST_TOKEN))

    ref_dir = str(JUMPROPE_DOWNLOAD_DIR)

    if args_dict["VISITID"] is not None:
        args_grid = [(a, b) for a in args_dict["VISITID"]
                            for b in args_dict["STAGE"]]
        for i in range(len(args_grid)):
            vid_query(
                ref_dir = ref_dir,
                visit_id = args_grid[i][0],
                stage = args_grid[i][1],
                dl_products = not args_dict["dry_run"]
            )
    else:
        args_grid = [(a,b,c,d) for a in args_dict["TELESCOPE"]
                               for b in args_dict["CAMERA"]
                               for c in args_dict["FILTER"]
                               for d in args_dict["STAGE"]]

        for i in range(len(args_grid)):
            cone_query(
                ref_dir,
                args_dict["RA"],
                args_dict["DEC"],
                args_dict["RAD"],
                args_grid[i][0],
                args_grid[i][1],
                args_grid[i][2],
                args_grid[i][3],
                dl_products = not args_dict["dry_run"]
            )

if __name__ == "__main__":
    if len(sys.argv) == 1:
        parser.print_help()
        sys.exit(1)
    else:
        args_dict = {
            "RA" : args.RA,
            "DEC" : args.DEC,
            "RAD" : args.RAD,
            "TELESCOPE" : args.TELESCOPE,
            "CAMERA" : args.CAMERA,
            "FILTER" : args.FILTER,
            "STAGE" : args.STAGE,
            "dry_run" : args.dry_run,
            "VISITID" : args.VISITID
        }

        main(args_dict)
