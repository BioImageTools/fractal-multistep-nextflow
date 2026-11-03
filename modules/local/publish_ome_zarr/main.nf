process PUBLISH_OME_ZARR {
    tag "$meta.id"
    label 'process_single'

    input:
    tuple val(meta), path(ome_zarr)

    output:
    tuple val(meta), path(ome_zarr), emit: zarr

    script:
    // Nothing to compute. All images of a plate write into the same OME-Zarr, so
    // this runs once per plate after every image is done, and its publishDir
    // (conf/modules.config) copies the finished plate to the results folder.
    """
    ls -d ${ome_zarr}
    """
}
