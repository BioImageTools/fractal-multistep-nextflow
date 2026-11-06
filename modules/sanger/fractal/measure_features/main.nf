process FRACTAL_MEASURE_FEATURES {
    tag "$meta.id"
    label 'process_low'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        "docker://${params.fractal_container}":
        "${params.fractal_container}" }"

    input:
    tuple val(meta), path(ome_zarr), val(image_path), val(label_name), val(table_name)

    output:
    // The same plate, now with <image_path>/tables/<table_name>
    tuple val(meta), path(ome_zarr), val(image_path)          , emit: zarr
    // A flat copy of the feature table for convenience
    tuple val(meta), path("${meta.id}_${table_name}.csv")     , emit: features
    // The exact arguments the Fractal task received (listed in the nf-prov RO-Crate)
    tuple val(meta), path("${meta.id}.measure_features.args.json"), emit: args
    path "versions.yml"                                       , emit: versions

    script:
    def image_dir = image_path ? "${ome_zarr}/${image_path}" : "${ome_zarr}"
    // `ome_zarr` is the whole plate (staged as a symlink, so this is cheap);
    // `image_path` selects one image inside it, e.g. "B/03/0" ("" for a single image)
    def zarr_url = image_path ? "\$PWD/${ome_zarr}/${image_path}" : "\$PWD/${ome_zarr}"
    // task.ext.args (a Map) can override/extend any task argument, e.g. features
    def task_args = groovy.json.JsonOutput.toJson([
        zarr_url         : zarr_url,
        input_label_name : label_name,
        output_table_name: table_name,
        advanced_options : [table_backend: 'csv'],
        overwrite        : true,
    ] + (task.ext.args ?: [:]))
    """
    cat > ${meta.id}.measure_features.args.json <<EOF
    ${task_args}
    EOF

    python -m fractal_tasks_core.measure_features \\
        --args-json ${meta.id}.measure_features.args.json \\
        --out-json out.json

    cp ${image_dir}/tables/${table_name}/table.csv ${meta.id}_${table_name}.csv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        fractal-tasks-core: \$(python -c "import importlib.metadata as m; print(m.version('fractal-tasks-core'))")
        ngio: \$(python -c "import importlib.metadata as m; print(m.version('ngio'))")
    END_VERSIONS
    """

    stub:
    def image_dir = image_path ? "${ome_zarr}/${image_path}" : "${ome_zarr}"
    """
    mkdir -p ${image_dir}/tables/${table_name}
    touch ${meta.id}_${table_name}.csv
    touch ${meta.id}.measure_features.args.json

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        fractal-tasks-core: stub
    END_VERSIONS
    """
}
