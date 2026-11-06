process FRACTAL_THRESHOLD_SEGMENTATION {
    tag "$meta.id"
    label 'process_low'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        "docker://${params.fractal_container}":
        "${params.fractal_container}" }"

    input:
    tuple val(meta), path(ome_zarr), val(image_path), val(channel_identifier), val(label_name)

    output:
    // The same plate, now with <image_path>/labels/<label_name>, handed to the next step
    tuple val(meta), path(ome_zarr), val(image_path), val(label_name), emit: zarr
    // The exact arguments the Fractal task received (listed in the nf-prov RO-Crate)
    tuple val(meta), path("${meta.id}.threshold_segmentation.args.json"), emit: args
    path "versions.yml"                                                  , emit: versions

    script:
    // `ome_zarr` is the whole plate (staged as a symlink, so this is cheap);
    // `image_path` selects one image inside it, e.g. "B/03/0" ("" for a single image)
    def zarr_url = image_path ? "\$PWD/${ome_zarr}/${image_path}" : "\$PWD/${ome_zarr}"
    // task.ext.args (a Map) can override/extend any task argument, e.g.
    // segmentation_method, pre_post_process, create_masking_roi_table
    def task_args = groovy.json.JsonOutput.toJson([
        zarr_url         : zarr_url,
        channel          : [mode: params.channel_mode, identifier: "${channel_identifier}"],
        output_label_name: label_name,
        overwrite        : true,
    ] + (task.ext.args ?: [:]))
    """
    cat > ${meta.id}.threshold_segmentation.args.json <<EOF
    ${task_args}
    EOF

    python -m fractal_tasks_core.threshold_segmentation \\
        --args-json ${meta.id}.threshold_segmentation.args.json \\
        --out-json out.json

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        fractal-tasks-core: \$(python -c "import importlib.metadata as m; print(m.version('fractal-tasks-core'))")
        ngio: \$(python -c "import importlib.metadata as m; print(m.version('ngio'))")
    END_VERSIONS
    """

    stub:
    def image_dir = image_path ? "${ome_zarr}/${image_path}" : "${ome_zarr}"
    """
    mkdir -p ${image_dir}/labels/${label_name}
    touch ${meta.id}.threshold_segmentation.args.json

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        fractal-tasks-core: stub
    END_VERSIONS
    """
}
