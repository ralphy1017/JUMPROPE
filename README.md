# JumProPe for the NEP TDF reduction

This clone is the active `nep-miri` branch of [JumProPe](https://github.com/JordanDSilva/JUMPROPE), with MIRI/NIRCam fixes through commit `7f3d2b3`. It was pushed to `ralphy1017/JUMPROPE`, branch `nep-miri`; the default `main` branch is older. The upstream [manual](https://www.overleaf.com/read/ksqfmgvhtnhh#3a3d4d) describes the underlying suite.

The parent project at `/home/rzi/Work/pipeline` supplies configs, orchestration, reference catalogs, fixed grids, Image3/photutils, ProPane/ProFound comparison, notebooks and QA. Start with its [README](../../README.md), [live state](../../CONTEXT.md) and [reduction reference](../../JUMPROPE.md). This clone alone does **not** install the patched ProPane 1.12.1.2 package required for reliable large-grid stacking.

[PATCHES.md](PATCHES.md) is the canonical change ledger for this branch. The production NIRCam wisp path uses Jordan's normal settings; the branch repairs execution and resume checks, rather than changing the wisp model.
