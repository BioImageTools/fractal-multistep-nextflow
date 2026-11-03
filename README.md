# Multi-step Fractal tasks in Nextflow

A small Nextflow pipeline that chains **several** [fractal-tasks-core](https://github.com/fractal-analytics-platform/fractal-tasks-core) tasks on the same OME-Zarr. [nf-fractal-demo](https://github.com/BioinfoTongLI/nf-fractal-demo) runs only one Fractal task per image.

- **Workflow idea and test data** come from [BioImageTools/ome-zarr-image-analysis-nextflow](https://github.com/BioImageTools/ome-zarr-image-analysis-nextflow): blur → segment → measure on two 682×682 nuclei images (PLK1 control / inhibition).
- **Every step is a stock fractal-tasks-core 2.1.0 task.** No custom Python.
- **Module format** follows [nf-fractal-demo](https://github.com/BioinfoTongLI/nf-fractal-demo): `modules/sanger/fractal/<task>/main.nf`, `tuple val(meta), path(ome_zarr), val(...)` inputs, task arguments written to JSON and passed with `--args-json`, plus `versions.yml` and a `stub:` block.

## Pipeline

```
data/*.ome.zarr
   │
   ▼
FRACTAL_IMPORT_OME_ZARR          fractal_tasks_core.import_ome_zarr
   │  <id>.zarr                  copies the input, adds image_ROI_table + omero channel metadata
   ▼
FRACTAL_THRESHOLD_SEGMENTATION   fractal_tasks_core.threshold_segmentation
   │  <id>.zarr, label_name      Gaussian blur (pre-process) → Otsu → size filter
   │                             writes labels/<label_name> and <label_name>_masking_ROI_table
   ▼
FRACTAL_MEASURE_FEATURES         fractal_tasks_core.measure_features
      <id>.zarr                  regionprops (shape + intensity) → tables/<label_name>_features
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
```

### Output

```
results/
├── ome_zarr/
│   ├── control.zarr/       labels/nuclei, tables/{image_ROI_table, nuclei_masking_ROI_table, nuclei_features}
│   └── inhibition.zarr/
├── features/
│   ├── control_nuclei_features.csv        # 13 nuclei with the default parameters
│   └── inhibition_nuclei_features.csv     # 20 nuclei
└── pipeline_info/versions.yml
```

Open `results/ome_zarr/*.zarr` in napari (with napari-ome-zarr) or another OME-Zarr viewer to see the labels on top of the image.

## Parameters

| param | default | meaning |
|---|---|---|
| `images` | the two bundled test images | list of `[meta, path]`. `meta.id` is required. `meta.channel` and `meta.label_name` override the global values for that image |
| `channel_mode` / `channel` | `index` / `0` | which channel to segment (`index`, `label` or `wavelength_id`) |
| `label_name` | `nuclei` | name of the label image. The feature table is `<label_name>_features` |
| `threshold_method` | `Otsu` | `Otsu` or `Simple Threshold` (set `threshold` too) |
| `sigma_xy` | `2.5` | Gaussian blur before thresholding. `null` disables it |
| `min_size` | `20` | removes objects smaller than this many pixels. `null` disables it |
| `out_dir` | `results` | |
| `fractal_container` | `quay.io/bioinfotongli/fractal-tasks-core:2.1.0` | |

You can set any other task argument in [conf/modules.config](conf/modules.config). There, `ext.args` is a **Map** that is merged into the task's JSON arguments. Field names follow the task's Pydantic models. For example, to measure shape features only:

```groovy
withName: 'FRACTAL_MEASURE_FEATURES' {
    ext.args = [features: [[type: 'ShapeFeatures']]]
}
```

## How the multi-step handoff works

1. **The OME-Zarr acts as Fractal's dataset; the Nextflow channel acts as Fractal's image list.** In Fractal, fractal-server tracks a list of `zarr_url`s and calls each task on each URL in turn. Here, a channel of `[meta, zarr]` tuples does that job. Each process writes into the zarr it receives and emits the same path for the next process. Anything the next step needs travels in the tuple, such as the `label_name` produced by segmentation.
2. **Only the first step copies data.** `import_ome_zarr` writes into the zarr it is given. To keep the input data unchanged, `FRACTAL_IMPORT_OME_ZARR` first makes a full copy (`cp -rL`) in its work dir. Later steps receive a symlink to that copy and write into it. This is the same in-place pattern as the original repo's `SEGMENT`/`MORPHOMETRY` steps.
3. **Paths in the JSON are absolute and resolved at run time** (`$PWD/<zarr>`). They therefore work inside containers and with `process.scratch`.
4. **Results are published once**, from the last step, with `mode: 'copy'`. All three steps write to the same directory, so the published zarr contains every label and table.
5. **Fractal's own metadata output is kept.** `import_ome_zarr`'s `--out-json` is the image-list update that fractal-server would read. It is emitted as `FRACTAL_IMPORT_OME_ZARR.out.image_list`.

### Adding another Fractal task as a step

Copy one of the three modules and change three things:

- the `python -m fractal_tasks_core.<task>` line;
- the map passed to `groovy.json.JsonOutput.toJson`, which holds the task's arguments; `zarr_url` is always `"\$PWD/${ome_zarr}"`. Use the fully qualified class name: the strict syntax in recent Nextflow versions rejects Groovy `import` lines;
- the output tuple, which should re-emit `path(ome_zarr)` plus anything the next step needs.

Then add the process to the chain in `main.nf`. The same pattern works for tasks from other Fractal task packages, for example a Cellpose package. Cellpose was removed from fractal-tasks-core in v2.0.0, so the `FRACTAL_CELLPOSE` module in nf-fractal-demo, which calls a hardcoded v1 script path, does not work with v2.

## Caveats

- **`-resume` caches only the first step.** Steps 2 and 3 write into step 1's output directory, which changes that directory's modification time. Nextflow therefore treats their inputs as changed and runs them again on `-resume`. The tasks run with `overwrite: true`, so a re-run is safe and gives the same result. Only the import/copy step is reliably cached.
- **Steps for one image must run one after another, not side by side.** Two processes writing different labels into the same zarr at the same time could race when updating `labels/.zattrs` or `tables/.zattrs`. Separate images run in parallel without problems.
- Pinned to **fractal-tasks-core 2.1.0** (ngio 0.5.x). The `main` branch upstream is moving to ngio 1.1, and task arguments may change.
- `import_ome_zarr` and the other tasks handle the test data's 5D `tczyx` axes as they are. No reshaping is needed.

## Layout

```
main.nf                                   # the 3-step workflow
nextflow.config                           # params + profiles
conf/modules.config                       # per-step Fractal task arguments (ext.args) + publishDir
modules/sanger/fractal/
├── import_ome_zarr/{main.nf,environment.yml}
├── threshold_segmentation/{main.nf,environment.yml}
└── measure_features/{main.nf,environment.yml}
containers/Dockerfile                     # python:3.12-slim + fractal-tasks-core==2.1.0
data/                                     # test images from ome-zarr-image-analysis-nextflow (MIT, embl-cba; see data/LICENSE)
```
