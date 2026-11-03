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
    // A fresh copy of the OME-Zarr that every downstream Fractal task writes into
    tuple val(meta), path("${meta.id}.zarr")        , emit: zarr
    // Fractal's own "image list update" (what fractal-server would ingest)
    tuple val(meta), path("${meta.id}.image_list.json"), emit: image_list
    path "versions.yml"                              , emit: versions

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

    cat > args.json <<EOF
    ${task_args}
    EOF

    python -m fractal_tasks_core.import_ome_zarr \\
        --args-json args.json \\
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
    echo '{"image_list_updates": []}' > ${meta.id}.image_list.json

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        fractal-tasks-core: stub
    END_VERSIONS
    """
}
