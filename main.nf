#!/usr/bin/env nextflow
/*
 * Multi-step Fractal workflow in Nextflow
 * ---------------------------------------
 * Same idea as BioImageTools/ome-zarr-image-analysis-nextflow
 * (blur -> segment -> measure on an OME-Zarr), but every step is a stock
 * task from fractal-tasks-core, wrapped as a Nextflow module the way
 * BioinfoTongLI/nf-fractal-demo does it.
 *
 *   FRACTAL_IMPORT_OME_ZARR          copy input, add image_ROI_table + omero metadata
 *        |  (same OME-Zarr)
 *   FRACTAL_THRESHOLD_SEGMENTATION   Gaussian blur pre-process + Otsu -> labels/<label>
 *        |  (same OME-Zarr + label name)
 *   FRACTAL_MEASURE_FEATURES         regionprops on labels/<label> -> tables/<table>
 *
 * Each process writes into the OME-Zarr it receives and passes it to the next,
 * so the OME-Zarr plays the role of Fractal's "dataset" and the Nextflow channel
 * (meta + path) plays the role of Fractal's image list.
 */

include { FRACTAL_IMPORT_OME_ZARR        } from './modules/sanger/fractal/import_ome_zarr/main'
include { FRACTAL_THRESHOLD_SEGMENTATION } from './modules/sanger/fractal/threshold_segmentation/main'
include { FRACTAL_MEASURE_FEATURES       } from './modules/sanger/fractal/measure_features/main'

workflow {
    // [ [id: ...], /path/to/image.ome.zarr ]
    images = channel
        .fromList(params.images)
        .map { meta, zarr -> [ meta, file(zarr, checkIfExists: true) ] }

    // Step 1: register the OME-Zarr with Fractal conventions (ROI table, channel metadata)
    FRACTAL_IMPORT_OME_ZARR(images)

    // Step 2: segment; channel and label name can be overridden per image via meta
    FRACTAL_THRESHOLD_SEGMENTATION(
        FRACTAL_IMPORT_OME_ZARR.out.zarr.map { meta, zarr ->
            [ meta, zarr, meta.channel ?: params.channel, meta.label_name ?: params.label_name ]
        }
    )

    // Step 3: measure the label produced by step 2 (label name travels in the channel)
    FRACTAL_MEASURE_FEATURES(
        FRACTAL_THRESHOLD_SEGMENTATION.out.zarr.map { meta, zarr, label_name ->
            [ meta, zarr, label_name, "${label_name}_features" ]
        }
    )

    FRACTAL_IMPORT_OME_ZARR.out.versions
        .mix(FRACTAL_THRESHOLD_SEGMENTATION.out.versions, FRACTAL_MEASURE_FEATURES.out.versions)
        .unique { it.text }
        .collectFile(name: 'versions.yml', storeDir: "${params.out_dir}/pipeline_info", sort: true)
}
