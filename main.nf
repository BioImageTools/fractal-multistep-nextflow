#!/usr/bin/env nextflow
/*
 * Multi-step Fractal workflow in Nextflow
 * ---------------------------------------
 * Same idea as BioImageTools/ome-zarr-image-analysis-nextflow
 * (blur -> segment -> measure on an OME-Zarr), but every step is a stock
 * task from fractal-tasks-core, wrapped as a Nextflow module the way
 * BioinfoTongLI/nf-fractal-demo does it.
 *
 *   FRACTAL_IMPORT_OME_ZARR          once per plate: copy, add image_ROI_table + omero metadata
 *        |  split by Fractal's image list -> one item per image (well/field)
 *   FRACTAL_THRESHOLD_SEGMENTATION   per image: Gaussian blur + Otsu -> labels/<label>
 *        |
 *   FRACTAL_MEASURE_FEATURES         per image: regionprops -> tables/<label>_features
 *        |  regroup by plate
 *   PUBLISH_OME_ZARR                 once per plate: copy the finished plate to out_dir
 *
 * The OME-Zarr plays the role of Fractal's dataset and the Nextflow channel
 * ([meta, plate, image_path]) plays the role of Fractal's image list.
 */

include { FRACTAL_IMPORT_OME_ZARR        } from './modules/sanger/fractal/import_ome_zarr/main'
include { FRACTAL_THRESHOLD_SEGMENTATION } from './modules/sanger/fractal/threshold_segmentation/main'
include { FRACTAL_MEASURE_FEATURES       } from './modules/sanger/fractal/measure_features/main'
include { PUBLISH_OME_ZARR               } from './modules/local/publish_ome_zarr/main'

workflow {
    // [ [id: ...], /path/to/plate.zarr ]  (a single-image OME-Zarr works too)
    plates = channel
        .fromList(params.images)
        .map { meta, zarr -> [ meta, file(zarr, checkIfExists: true) ] }

    // Step 1 (per plate): register the OME-Zarr with Fractal conventions
    FRACTAL_IMPORT_OME_ZARR(plates)

    // Split each plate into its images using import_ome_zarr's own output, i.e.
    // the "image_list_updates" that fractal-server would use to schedule the
    // next tasks. Every zarr_url (".../<plate>.zarr/B/03/0") becomes one item
    // carrying the plate plus the image path inside it ("B/03/0").
    images = FRACTAL_IMPORT_OME_ZARR.out.zarr.flatMap { meta, zarr, image_list ->
        def updates = new groovy.json.JsonSlurper().parse(image_list.toFile()).image_list_updates
        updates.collect { img ->
            def parts      = img.zarr_url.tokenize('/')
            def image_path = parts.drop(parts.lastIndexOf(zarr.name) + 1).join('/')
            def image_meta = meta + [
                id      : image_path ? "${meta.id}_${image_path.replace('/', '_')}" : meta.id,
                plate   : meta.id,
                well    : img.attributes?.well,
                n_images: updates.size(),
            ]
            [ image_meta, zarr, image_path ]
        }
    }

    // Step 2 (per image): segment; channel and label name can be overridden via meta
    FRACTAL_THRESHOLD_SEGMENTATION(
        images.map { meta, zarr, image_path ->
            [ meta, zarr, image_path, meta.channel ?: params.channel, meta.label_name ?: params.label_name ]
        }
    )

    // Step 3 (per image): measure the label produced by step 2 for the same image
    FRACTAL_MEASURE_FEATURES(
        FRACTAL_THRESHOLD_SEGMENTATION.out.zarr.map { meta, zarr, image_path, label_name ->
            [ meta, zarr, image_path, label_name, "${label_name}_features" ]
        }
    )

    // Regroup per plate: groupKey with the number of images lets each plate be
    // published as soon as its last image is done, not at the end of the run
    PUBLISH_OME_ZARR(
        FRACTAL_MEASURE_FEATURES.out.zarr
            .map { meta, zarr, image_path -> [ groupKey(meta.plate, meta.n_images), zarr ] }
            .groupTuple()
            .map { plate, zarrs -> [ [id: plate.toString()], zarrs.first() ] }
    )

    FRACTAL_IMPORT_OME_ZARR.out.versions
        .mix(FRACTAL_THRESHOLD_SEGMENTATION.out.versions, FRACTAL_MEASURE_FEATURES.out.versions)
        .unique { it.text }
        .collectFile(name: 'versions.yml', storeDir: "${params.out_dir}/pipeline_info", sort: true)
}
