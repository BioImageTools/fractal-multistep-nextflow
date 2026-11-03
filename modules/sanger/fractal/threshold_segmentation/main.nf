process FRACTAL_THRESHOLD_SEGMENTATION {
    tag "$meta.id"
    label 'process_low'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        "docker://${params.fractal_container}":
        "${params.fractal_container}" }"

    input:
    tuple val(meta), path(ome_zarr), val(channel_identifier), val(label_name)

    output:
    // The same OME-Zarr, now with labels/<label_name>, handed to the next step
    tuple val(meta), path(ome_zarr), val(label_name), emit: zarr
    path "versions.yml"                              , emit: versions

    script:
    // task.ext.args (a Map) can override/extend any task argument, e.g.
    // segmentation_method, pre_post_process, create_masking_roi_table
    def task_args = groovy.json.JsonOutput.toJson([
        zarr_url         : "\$PWD/${ome_zarr}",
        channel          : [mode: params.channel_mode, identifier: "${channel_identifier}"],
        output_label_name: label_name,
        overwrite        : true,
    ] + (task.ext.args ?: [:]))
    """
    cat > args.json <<EOF
    ${task_args}
    EOF

    python -m fractal_tasks_core.threshold_segmentation \\
        --args-json args.json \\
        --out-json out.json

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        fractal-tasks-core: \$(python -c "import importlib.metadata as m; print(m.version('fractal-tasks-core'))")
        ngio: \$(python -c "import importlib.metadata as m; print(m.version('ngio'))")
    END_VERSIONS
    """

    stub:
    """
    mkdir -p ${ome_zarr}/labels/${label_name}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        fractal-tasks-core: stub
    END_VERSIONS
    """
}
