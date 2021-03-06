#!/usr/bin/env nextflow

/*
vim: syntax=groovy
-*- mode: groovy;-*-
*/

if (params.help ) {
    return help()
}

if( params.reference_genome ) {
    reference_genome = file(params.reference_genome)
}

if( params.amr ) {
    amr = file(params.amr)
    if( !amr.exists() ) return amr_error(amr)
}
if( params.adapters ) {
    adapters = file(params.adapters)
    if( !adapters.exists() ) return adapter_error(adapters)
}
if( params.annotation ) {
    annotation = file(params.annotation)
    if( !annotation.exists() ) return annotation_error(annotation)
}

if(params.kraken_db) {
    kraken_db = file(params.kraken_db)
}

clusterOptions = ''

threads = params.threads
output = params.output

threshold = params.threshold

min = params.min
max = params.max
skip = params.skip
samples = params.samples

leading = params.leading
trailing = params.trailing
slidingwindow = params.slidingwindow
minlen = params.minlen

fasta_allele = file(params.fasta_allele)


/*
Channel
    .fromFilePairs( params.reference_genome, size: 1)
    .ifEmpty { exit 1, "Reference genome could not be found: ${params.reference_genome}" }
    .set { reference_genome }
*/

Channel
    .fromFilePairs( params.reads, flat: true )
    .ifEmpty { exit 1, "Read pair files could not be found: ${params.reads}" }
    .set { reads }



/*
Process reads to fasta
*/

process etoki_FastqQC {
    tag {sample_id}

    module 'singularity'
    errorStrategy 'ignore'
    publishDir "${params.output}/etoki_fastqQC", mode: "symlink"

    container 'shub://TheNoyesLab/WGS_SNP_pipelines:etoki'

    input:
      set sample_id, file(forward), file(reverse) from reads

    output:
       set sample_id, file("${sample_id}_trimmed*R1.fastq.gz"), file("${sample_id}_trimmed*R2.fastq.gz") into (trimmed_fastq)

    """
    python /usr/local/EToKi/EToKi.py prepare --pe ${forward},${reverse} -p ${sample_id}_trimmed --merge
    """
}


process etoki_assemble {
    tag {sample_id}

    module 'singularity'
    errorStrategy 'ignore'
    publishDir "${params.output}/etoki_assemble", mode: "symlink"

    container 'shub://TheNoyesLab/WGS_SNP_pipelines:etoki'
    /* container '/home/noyes046/shared/tools/Singularity_etoki_kraken.simg' */

    input:
      set sample_id, file(forward), file(reverse) from trimmed_fastq
      file reference_genome

    output:
      file("${sample_id}_assemble.result.fasta") into (assembled_fasta,assembled_fasta_list)

    """
    python /usr/local/EToKi/EToKi.py assemble --pe ${forward},${reverse} -p ${sample_id}_assemble --assembler megahit --reassemble
    """
}



/*
Etoki MLST analysis
*/

process etoki_prep_MLST {
    tag {sample_id}

    module 'singularity'
    errorStrategy 'ignore'
    publishDir "${params.output}/etoki_ref_MLST", mode: "symlink"

    container 'shub://TheNoyesLab/WGS_SNP_pipelines:etoki'

    input:
      file allele_fasta

    output:
      file("reference_alleles.fasta") into (reference_alleles)
      file("lookup_alleles") into (lookup_alleles)
    

    """
    python /usr/local/EToKi/EToKi.py MLSTdb -i ${allele_fasta} -r reference_alleles.fasta -d lookup_alleles
    """
}


process etoki_MLST_type {
    tag {sample_id}

    module 'singularity'
    errorStrategy 'ignore'
    publishDir "${params.output}/etoki_MLST_results", mode: "symlink"

    container 'shub://TheNoyesLab/WGS_SNP_pipelines:etoki'

    input:
      file reference_alleles
      file lookup_alleles

    output:
      file("calculated_allele.convert.tab") into (calculated_alleles)

    """
    python /usr/local/EToKi/EToKi.py MLSTdb -i ${assembled_fasta} -r ${reference_alleles} -d ${lookup_alleles} -k ${sample_id} -o ${sample_id}_generated_alleles.fasta
    """
}

/*
Etoki alignment and phylogenetic tree
*/



assembled_fasta_list.toSortedList().set { all_assembled_genomes }

process etoki_align {
    tag {etoki_align}

    module 'singularity'
    errorStrategy 'ignore'
    publishDir "${params.output}/etoki_align", mode: "symlink"

    container 'shub://TheNoyesLab/WGS_SNP_pipelines:etoki'


    input:
      file reference_genome
      file all_assembled_genomes

    output:
      file("phylo_out*") into (phylo_output)

    """
    python /usr/local/EToKi/EToKi.py align -r ${reference_genome} -p phylo_out ${all_assembled_genomes}
    """
}

process etoki_phylo_tree {
    tag {sample_id}

    module 'singularity'
    errorStrategy 'ignore'
    publishDir "${params.output}/etoki_phylo_output", mode: "symlink"

    container 'shub://TheNoyesLab/WGS_SNP_pipelines:etoki'

    input:
      file reference_genome
      file phylo_output

    output:
      file("phylo_tree*") into (phylo_tree)

    """
    python /usr/local/EToKi/EToKi.py phylo -t snp2mut -p phylo_tree -s ${phylo_output}
    """
}



def nextflow_version_error() {
    println ""
    println "This workflow requires Nextflow version 0.25 or greater -- You are running version $nextflow.version"
    println "Run ./nextflow self-update to update Nextflow to the latest available version."
    println ""
    return 1
}

def adapter_error(def input) {
    println ""
    println "[params.adapters] fail to open: '" + input + "' : No such file or directory"
    println ""
    return 1
}

def amr_error(def input) {
    println ""
    println "[params.amr] fail to open: '" + input + "' : No such file or directory"
    println ""
    return 1
}

def annotation_error(def input) {
    println ""
    println "[params.annotation] fail to open: '" + input + "' : No such file or directory"
    println ""
    return 1
}

def fastq_error(def input) {
    println ""
    println "[params.reads] fail to open: '" + input + "' : No such file or directory"
    println ""
    return 1
}

def host_error(def input) {
    println ""
    println "[params.host] fail to open: '" + input + "' : No such file or directory"
    println ""
    return 1
}

def index_error(def input) {
    println ""
    println "[params.host_index] fail to open: '" + input + "' : No such file or directory"
    println ""
    return 1
}

def help() {
    println ""
    println "Program: AmrPlusPlus"
    println "Documentation: https://github.com/colostatemeg/amrplusplus/blob/master/README.md"
    println "Contact: Christopher Dean <cdean11@colostate.edu>"
    println ""
    println "Usage:    nextflow run main.nf [options]"
    println ""
    println "Input/output options:"
    println ""
    println "    --reads         STR      path to FASTQ formatted input sequences"
    println "    --adapters      STR      path to FASTA formatted adapter sequences"
    println "    --host          STR      path to FASTA formatted host genome"
    println "    --host_index    STR      path to BWA generated index files"
    println "    --amr           STR      path to AMR resistance database"
    println "    --annotation    STR      path to AMR annotation file"
    println "    --output        STR      directory to write process outputs to"
    println "    --KRAKENDB      STR      path to kraken database"
    println ""
    println "Trimming options:"
    println ""
    println "    --leading       INT      cut bases off the start of a read, if below a threshold quality"
    println "    --minlen        INT      drop the read if it is below a specified length"
    println "    --slidingwindow INT      perform sw trimming, cutting once the average quality within the window falls below a threshold"
    println "    --trailing      INT      cut bases off the end of a read, if below a threshold quality"
    println ""
    println "Algorithm options:"
    println ""
    println "    --threads       INT      number of threads to use for each process"
    println "    --threshold     INT      gene fraction threshold"
    println "    --min           INT      starting sample level"
    println "    --max           INT      ending sample level"
    println "    --samples       INT      number of sampling iterations to perform"
    println "    --skip          INT      number of levels to skip"
    println ""
    println "Help options:"
    println ""
    println "    --help                   display this message"
    println ""
    return 1
}
