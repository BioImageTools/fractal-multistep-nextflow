process FRACTAL_MEASURE_FEATURES {
    tag "$meta.id"
    label 'process_low'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        "docker://${params.fractal_container}":
        "${params.fractal_container}" }"

    input:
    tuple val(meta), path(ome_zarr), val(label_name), val(table_name)

    output:
    // The same OME-Zarr, now with tables/<table_name>
    tuple val(meta), path(ome_zarr)                           , emit: zarr
    // A flat copy of the feature table for convenience
    tuple val(meta), path("${meta.id}_${table_name}.csv")     , emit: features
    path "versions.yml"                                       , emit: versions

    script:
    // task.ext.args (a Map) can override/extend any task argument, e.g. features
    def task_args = groovy.json.JsonOutput.toJson([
        zarr_url         : "\$PWD/${ome_zarr}",
        input_label_name : label_name,
        output_table_name: table_name,
        advanced_options : [table_backend: 'csv'],
        overwrite        : true,
    ] + (task.ext.args ?: [:]))
    """
    cat > args.json <<EOF
    ${task_args}
    EOF

    python -m fractal_tasks_core.measure_features \\
        --args-json args.json \\
        --out-json out.json

    cp ${ome_zarr}/tables/${table_name}/table.csv ${meta.id}_${table_name}.csv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        fractal-tasks-core: \$(python -c "import importlib.metadata as m; print(m.version('fractal-tasks-core'))")
        ngio: \$(python -c "import importlib.metadata as m; print(m.version('ngio'))")
    END_VERSIONS
    """

    stub:
    """
    mkdir -p ${ome_zarr}/tables/${table_name}
    touch ${meta.id}_${table_name}.csv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        fractal-tasks-core: stub
    END_VERSIONS
    """
}
