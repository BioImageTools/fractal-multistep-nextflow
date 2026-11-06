process FRACTAL_IMPORT_OME_ZARR {
    tag "$meta.id"
    label 'process_low'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        "docker://${params.fractal_container}":
        "${params.fractal_container}" }"

    input:
    tuple val(meta), path(ome_zarr, stageAs: 'input/*')

    output:
    // A fresh copy of the OME-Zarr (plate or image) that every downstream Fractal
    // task writes into, together with Fractal's own "image list update": one
    // entry per image (i.e. per well/field for a plate). The workflow uses the
    // latter to fan out to one downstream task per image, as fractal-server does.
    tuple val(meta), path("${meta.id}.zarr"), path("${meta.id}.image_list.json"), emit: zarr
    // The exact arguments the Fractal task received, published so that nf-prov
    // lists them in the run's RO-Crate
    tuple val(meta), path("${meta.id}.import_ome_zarr.args.json")            , emit: args
    path "versions.yml"                                                      , emit: versions

    script:
    // task.ext.args (a Map) is merged into advanced_options, see conf/modules.config
    def advanced = [
        add_image_roi_table  : true,
        update_omero_metadata: true,
    ] + (task.ext.args ?: [:])
    // '$PWD' is expanded by the shell at run time, so the path is valid inside
    // containers and with process.scratch alike
    def task_args = groovy.json.JsonOutput.toJson([
        zarr_dir        : '$PWD',
        zarr_name       : "${meta.id}.zarr",
        advanced_options: advanced,
    ])
    """
    # import_ome_zarr modifies the OME-Zarr in place (ROI tables, omero metadata).
    # Work on a dereferenced copy so the input data is never touched.
    cp -rL ${ome_zarr} ${meta.id}.zarr

    cat > ${meta.id}.import_ome_zarr.args.json <<EOF
    ${task_args}
    EOF

    python -m fractal_tasks_core.import_ome_zarr \\
        --args-json ${meta.id}.import_ome_zarr.args.json \\
        --out-json ${meta.id}.image_list.json

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        fractal-tasks-core: \$(python -c "import importlib.metadata as m; print(m.version('fractal-tasks-core'))")
        ngio: \$(python -c "import importlib.metadata as m; print(m.version('ngio'))")
    END_VERSIONS
    """

    stub:
    """
    cp -rL ${ome_zarr} ${meta.id}.zarr
    mkdir -p ${meta.id}.zarr/tables/image_ROI_table
    # treat the whole OME-Zarr as a single image when stubbing
    cat > ${meta.id}.image_list.json <<EOF
    {"image_list_updates": [{"zarr_url": "\$PWD/${meta.id}.zarr"}]}
    EOF
    touch ${meta.id}.import_ome_zarr.args.json

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        fractal-tasks-core: stub
    END_VERSIONS
    """
}
