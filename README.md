# Multi-step Fractal tasks in Nextflow

A small Nextflow pipeline that chains **several** [fractal-tasks-core](https://github.com/fractal-analytics-platform/fractal-tasks-core) tasks on an OME-Zarr HCS plate, well by well. [nf-fractal-demo](https://github.com/BioinfoTongLI/nf-fractal-demo) runs only one Fractal task per image.

- **Workflow idea and test data** come from [BioImageTools/ome-zarr-image-analysis-nextflow](https://github.com/BioImageTools/ome-zarr-image-analysis-nextflow): blur → segment → measure on two 682×682 nuclei images (PLK1 control / inhibition). For this pipeline the two images are put into a small HCS plate, `data/PLK1_plate.zarr` (control in well B/03, inhibition in B/04), built by [scripts/make_test_plate.py](scripts/make_test_plate.py).
- **Every step is a stock fractal-tasks-core 2.1.0 task.** No custom Python.
- **Module format** follows [nf-fractal-demo](https://github.com/BioinfoTongLI/nf-fractal-demo): `modules/sanger/fractal/<task>/main.nf`, `tuple val(meta), path(ome_zarr), val(...)` inputs, task arguments written to JSON and passed with `--args-json`, plus `versions.yml` and a `stub:` block.

## Pipeline

```
data/PLK1_plate.zarr
   │
   ▼
FRACTAL_IMPORT_OME_ZARR          once per plate · fractal_tasks_core.import_ome_zarr
   │                             copies the plate, adds image_ROI_table + omero channel metadata
   │                             to every image, returns Fractal's image list (one zarr_url per image)
   │
   ├── split by image list ──────────────────────────────┐
   ▼                                                      ▼
FRACTAL_THRESHOLD_SEGMENTATION   B/03/0                  B/04/0      per image (in parallel)
   │                             Gaussian blur → Otsu → size filter
   │                             writes <image>/labels/<label_name> + <label_name>_masking_ROI_table
   ▼                                                      ▼
FRACTAL_MEASURE_FEATURES         B/03/0                  B/04/0      per image (in parallel)
   │                             regionprops (shape + intensity) → <image>/tables/<label_name>_features
   │                                                      │
   ├── regroup by plate ─────────────────────────────────┘
   ▼
PUBLISH_OME_ZARR                 once per plate: copies the finished plate to out_dir
```

How the steps map to the original workflow:

| ome-zarr-image-analysis-nextflow | here (fractal-tasks-core 2.1.0) |
|---|---|
| `BLUR` (`blur.py`) | `pre_post_process.pre_process: Gaussian Blur Filter` inside `threshold_segmentation` |
| `SEGMENT` (`segment.py`, Otsu) | `threshold_segmentation` with `segmentation_method: Otsu` |
| `MORPHOMETRY` (`extract_features.py`) | `measure_features` |
| (none) | `import_ome_zarr`, which adds the ROI table and channel metadata that Fractal tasks expect |

## Run it

> **Tested:** `-profile local` (Python 3.12, fractal-tasks-core 2.1.0, Nextflow 26.10.5) and `-stub`.
> The Docker image and the docker/singularity/conda/wave profiles are written but **not yet run**.

### With Docker

No public image exists yet. Build it once; Docker then uses the local tag:

```bash
docker build -t quay.io/bioinfotongli/fractal-tasks-core:2.1.0 containers/
nextflow run . -profile docker
```

You can push that tag, or point `--fractal_container` at another image that has `fractal-tasks-core==2.1.0` installed.

### Other ways to run it

```bash
nextflow run . -profile singularity        # same image, through Singularity
nextflow run . -profile conda              # uses modules/*/environment.yml
nextflow run . -profile wave               # Wave builds the image from environment.yml (runs with Docker)
nextflow run . -profile local              # uses `python` on PATH (pip install fractal-tasks-core==2.1.0)
nextflow run . -stub                       # dry run of the wiring only, no Python needed
nextflow run . -profile docker,prov        # add provenance with nf-prov (RO-Crate, BCO, trace...), see below
```

### Output

```
results/
├── ome_zarr/
│   └── PLK1_plate.zarr/
│       ├── B/03/0/          labels/nuclei, tables/{image_ROI_table, nuclei_masking_ROI_table, nuclei_features}
│       └── B/04/0/          same
├── features/
│   ├── PLK1_plate_B_03_0_nuclei_features.csv   # control: 13 nuclei with the default parameters
│   └── PLK1_plate_B_04_0_nuclei_features.csv   # inhibition: 20 nuclei
├── task_args/PLK1_plate/                       # the exact JSON arguments each Fractal task received
│   ├── PLK1_plate.import_ome_zarr.args.json
│   ├── PLK1_plate_B_03_0.{threshold_segmentation,measure_features}.args.json
│   └── PLK1_plate_B_04_0.{threshold_segmentation,measure_features}.args.json
└── pipeline_info/versions.yml
```

Open `results/ome_zarr/*.zarr` in napari (with napari-ome-zarr) or another OME-Zarr viewer to see the labels on top of the image.

## Parameters

| param | default | meaning |
|---|---|---|
| `images` | `data/PLK1_plate.zarr` | list of `[meta, path]`, each an HCS plate or a single OME-Zarr image. `meta.id` is required. `meta.channel` and `meta.label_name` override the global values for every image in that entry |
| `channel_mode` / `channel` | `index` / `0` | which channel to segment (`index`, `label` or `wavelength_id`) |
| `label_name` | `nuclei` | name of the label image. The feature table is `<label_name>_features` |
| `threshold_method` | `Otsu` | `Otsu` or `Simple Threshold` (set `threshold` too) |
| `sigma_xy` | `2.5` | Gaussian blur before thresholding. `null` disables it |
| `min_size` | `20` | removes objects smaller than this many pixels. `null` disables it |
| `out_dir` | `results` | |
| `fractal_container` | `quay.io/bioinfotongli/fractal-tasks-core:2.1.0` | |
| `prov_license` | `BSD-3-Clause` | `-profile prov` only: licence of the RO-Crate, i.e. of the run's results (SPDX id or URL) |
| `prov_agent_name` / `prov_agent_orcid` / `prov_agent_email` | none | `-profile prov` only: the person running the pipeline, recorded as the agent of the run and of every task |
| `prov_organization_name` / `prov_organization_ror` | none | `-profile prov` only: their organisation; with a ROR id it is also the crate's publisher |

You can set any other task argument in [conf/modules.config](conf/modules.config). There, `ext.args` is a **Map** that is merged into the task's JSON arguments. Field names follow the task's Pydantic models. For example, to measure shape features only:

```groovy
withName: 'FRACTAL_MEASURE_FEATURES' {
    ext.args = [features: [[type: 'ShapeFeatures']]]
}
```

## How the multi-step handoff works

1. **The plate is split with Fractal's own image list.** In Fractal, `import_ome_zarr` returns `image_list_updates`, one `zarr_url` per image in the plate (for example `.../PLK1_plate.zarr/B/03/0`, with `attributes.well = "B03"`), and fractal-server then runs every following task once per `zarr_url`. Here `FRACTAL_IMPORT_OME_ZARR` emits that JSON next to the plate (`out.zarr` = `[meta, plate, image_list.json]`), and a `flatMap` in `main.nf` turns it into one channel item per image: `[meta, plate, "B/03/0"]`. `meta.id` becomes `<plate>_B_03_0`, and `meta.plate`, `meta.well` and `meta.n_images` are added. A single-image OME-Zarr gives one item with an empty image path.
2. **Downstream tasks get the whole plate plus one image path.** Nextflow stages the plate as a symlink, so passing it costs nothing, and the module builds `zarr_url = $PWD/<plate>/<image_path>`. Each task only writes inside its own image group (`B/03/0/labels`, `B/03/0/tables`), so the images of one plate can be processed in parallel without touching each other. Anything the next step needs travels in the tuple, such as the `label_name` produced by segmentation.
3. **Only the first step copies data.** `import_ome_zarr` writes into the zarr it is given. To keep the input data unchanged, `FRACTAL_IMPORT_OME_ZARR` first makes a full copy (`cp -rL`) in its work dir. Every later task receives a symlink to that copy and writes into it. This is the same in-place pattern as the original repo's `SEGMENT`/`MORPHOMETRY` steps.
4. **Paths in the JSON are absolute and resolved at run time** (`$PWD/...`). They therefore work inside containers and with `process.scratch`.
5. **Each plate is published once, when all its images are done.** After measurement, the items are regrouped by plate with `groupKey(plate, n_images)`, so a plate is released as soon as its last image finishes. `PUBLISH_OME_ZARR` does no work itself; its `publishDir` copies the plate with `mode: 'copy'`. The per-image feature CSVs are published directly by `FRACTAL_MEASURE_FEATURES`.

### Adding another Fractal task as a step

Copy one of the three modules and change these things:

- the `python -m fractal_tasks_core.<task>` line;
- the map passed to `groovy.json.JsonOutput.toJson`, which holds the task's arguments; keep `zarr_url: zarr_url` (built from the plate and `image_path`). Use the fully qualified class name: the strict syntax in recent Nextflow versions rejects Groovy `import` lines;
- the name of the arguments file, `${meta.id}.<step>.args.json`, in the script and in the `args` output, so the arguments are published under a name of their own;
- the output tuple, which should re-emit `path(ome_zarr), val(image_path)` plus anything the next step needs.

Then add the process to the chain in `main.nf`. The same pattern works for tasks from other Fractal task packages, for example a Cellpose package. Cellpose was removed from fractal-tasks-core in v2.0.0, so the `FRACTAL_CELLPOSE` module in nf-fractal-demo, which calls a hardcoded v1 script path, does not work with v2.

## Provenance

Provenance comes from the [nf-prov](https://github.com/nextflow-io/nf-prov) plugin (1.8.0) and Nextflow's own reports, enabled with `-profile prov` ([conf/prov.config](conf/prov.config)). The pipeline has no provenance code of its own.

```bash
nextflow run . -profile docker,prov \
    --prov_agent_name 'Jane Doe' --prov_agent_orcid https://orcid.org/0000-0000-0000-0000 \
    --prov_organization_name 'Wellcome Sanger Institute' --prov_organization_ror https://ror.org/05cy4wa09
```

This adds to `results/`:

```
results/
├── ro-crate-metadata.json     # Workflow Run RO-Crate: run, params, every task, its inputs/outputs, published files
├── main.nf, nextflow.config,  # copied in by nf-prov so the crate is self-contained
│   README.md
└── pipeline_info/
    ├── bco.json               # BioCompute Object
    ├── dag.html               # task graph of this run
    ├── trace.tsv              # per-task timing, CPU, memory, exit status
    └── report.html, timeline.html
```

- **Each Fractal task's arguments are in the crate.** nf-prov records pipeline parameters but not the JSON each module builds for its Fractal task (module defaults merged with `ext.args`). So every Fractal step writes that JSON to `<meta.id>.<step>.args.json`, passes it to the task with `--args-json`, and publishes it to `results/task_args/<plate>/` (with or without `-profile prov`). The crate lists each file as a result of the task that wrote it. The file holds the arguments as given: defaults that the task's Pydantic models fill in are not listed, and paths are the absolute paths in the task's work directory.
- **Software versions** are in `pipeline_info/versions.yml` (fractal-tasks-core and ngio per step), as in nf-core.
- **The crate is valid.** It passes the required checks of RO-Crate 1.1, Workflow RO-Crate 1.0 and Workflow Run Crate 0.5 ([roc-validator](https://github.com/crs4/rocrate-validator) 0.13.1).
- **The crate is written into `out_dir`.** nf-prov leaves out any published file outside the crate's folder.
- **The trace has no `script` or `env` columns.** Those are multi-line and break the TSV; the exact script is in each task's `.command.sh`, and the task arguments are in `task_args/`.
- **The repository URL is only recorded when the pipeline is run by its name**, e.g. `nextflow run BioImageTools/fractal-multistep-nextflow -r main`. With `nextflow run .`, nf-prov warns about it and leaves it out.
- **The "recommended" level still has warnings that come from nf-prov itself**, such as no version on the modules and no description or end time per task.

### Provenance inside the OME-Zarr

There is a [`provenance:` Zarr convention](https://github.com/BioImageTools/zarr-convention-provenance) for storing provenance in the attributes of the Zarr nodes themselves (`zarr.json`), so that it travels with the data. The convention is not stable yet, so this pipeline does not write it. A proper implementation, with each step's provenance written into the `zarr.json` of the nodes it created, is future work, for when the convention is stable and there is enough interest.

## Caveats

- **`-resume` caches only the first step.** Steps 2 and 3 write into step 1's output directory, which changes that directory's modification time. Nextflow therefore treats their inputs as changed and runs them again on `-resume`. The tasks run with `overwrite: true`, so a re-run is safe and gives the same result. Only the import/copy step is reliably cached.
- **Steps for one image must run one after another, not side by side.** Two processes writing different labels into the same image at the same time could race when updating its `labels/.zattrs` or `tables/.zattrs`. Different images of the same plate run in parallel without problems, because each writes only inside its own image group.
- **Only per-image tasks are wired up.** Plate-level Fractal tasks (for example `init_projection_hcs`/`compute_projection_hcs` or the registration tasks) build their own image lists and would need their own split step.
- **In a `-stub` run the whole plate counts as one image**, because listing the wells needs Python. The stub `args.json` files are empty.
- Pinned to **fractal-tasks-core 2.1.0** (ngio 0.5.x). The `main` branch upstream is moving to ngio 1.1, and task arguments may change.
- `import_ome_zarr` and the other tasks handle the test data's 5D `tczyx` axes as they are. No reshaping is needed.

## Layout

```
main.nf                                   # the workflow: import → split per image → segment → measure → publish
nextflow.config                           # params + profiles
conf/modules.config                       # per-step Fractal task arguments (ext.args) + publishDir
modules/sanger/fractal/
├── import_ome_zarr/{main.nf,environment.yml}
├── threshold_segmentation/{main.nf,environment.yml}
└── measure_features/{main.nf,environment.yml}
modules/local/publish_ome_zarr/main.nf    # publishes each finished plate once
conf/prov.config                          # -profile prov: nf-prov RO-Crate/BCO/DAG + trace/report/timeline
scripts/make_test_plate.py                # builds data/PLK1_plate.zarr from the two test images (ngio)
containers/Dockerfile                     # python:3.12-slim + fractal-tasks-core==2.1.0
data/                                     # PLK1_plate.zarr + the two original test images from ome-zarr-image-analysis-nextflow (MIT, embl-cba; see data/LICENSE)
```
