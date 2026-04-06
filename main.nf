#!/usr/bin/env nextflow

nextflow.enable.dsl = 2

params.cohort_file = 'cohort.csv'
params.script_file = 'run_analysis.R'

process runCharacterization {
    tag 'OHDSI Characterization'

    publishDir '.', mode: 'copy', overwrite: true

    input:
    path cohort_csv
    path r_script

    output:
    path 'output/**',   emit: results,  optional: true
    path 'report.html', emit: report,   optional: true

    script:
    """
    export LD_LIBRARY_PATH=/usr/lib/jvm/java-21-openjdk-amd64/lib/server:\$LD_LIBRARY_PATH
    Rscript ${r_script}
    """
}

workflow {
    runCharacterization(
        file(params.cohort_file),
        file(params.script_file)
    )
}
