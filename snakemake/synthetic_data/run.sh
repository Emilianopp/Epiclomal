snakemake -s /shahlab/pye/projects/epiclomal/Epiclomal/snakemake/synthetic_data/Snakefile --configfile /shahlab/pye/projects/epiclomal/Epiclomal/snakemake/synthetic_data/config.yaml --cluster 'qsub -V -hard -q shahlab.q -l h_vmem={resources.h_vmem}G -P shahlab_high -S /bin/bash -o {params.qsub_out} -e {params.qsub_err}' -j 32
