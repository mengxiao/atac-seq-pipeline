import "https://api.firecloud.org/ga4gh/v1/tools/mxhe:parse_attach_file_list/versions/1/plain-WDL/descriptor" as read_lines_sub
import "https://api.firecloud.org/ga4gh/v1/tools/mxhe:read_tsv/versions/1/plain-WDL/descriptor" as read_tsv_sub

workflow atac {
	String docker = "quay.io/encode-dcc/atac-seq-pipeline:v1.1.6"
	String pipeline_ver = 'v1.1.6'
	### sample name, description
	String title = 'Untitled'
	String description = 'No description'

	### pipeline type
	String pipeline_type = 'atac'	# ATAC-Seq (atac) or DNase-Seq (dnase)
									# the only difference is that tn5 shiting is enabled for atac
	### mandatory genome param
	File genome_tsv 		# reference genome data TSV file including
							# all important genome specific data file paths and parameters
	Boolean paired_end

	### optional but important
	Boolean align_only = false		# disable all post-align analysis (peak-calling, overlap, idr, ...)
	Boolean true_rep_only = false 	# disable all analyses for pseudo replicates
									# overlap and idr will also be disabled

	Boolean auto_detect_adapter = false	# automatically detect/trim adapters
	Int cutadapt_min_trim_len = 5	# minimum trim length for cutadapt -m
	Float cutadapt_err_rate = 0.1	# Maximum allowed adapter error rate for cutadapt -e	

	Int multimapping = 0			# for multimapping reads

	String bowtie2_score_min = ''	# min acceptable alignment score func w.r.t read length

	String dup_marker = 'picard'	# picard MarkDuplicates (picard) or sambamba markdup (sambamba)
	Int mapq_thresh = 30			# threshold for low MAPQ reads removal
	Boolean no_dup_removal = false 	# no dupe reads removal when filtering BAM
									# dup.qc and pbc.qc will be empty files
									# and nodup_bam in the output is filtered bam with dupes

	String mito_chr_name = 'chrM' 	# name of mito chromosome. THIS IS NOT A REG-EX! you can define only one chromosome name for mito.
	String regex_filter_reads = 'chrM' 	# Perl-style regular expression pattern for chr name to filter out reads
									# those reads with this chromosome name (in the 1st column) will be excluded from peak calling
	Int subsample_reads = 0		# number of reads to subsample TAGALIGN
								# 0 for no subsampling. this affects all downstream analysis

	Boolean enable_xcor = false 	# enable cross-correlation analysis
	Int xcor_subsample_reads = 25000000	# number of reads to subsample TAGALIGN
								# this will be used for xcor only
								# will not affect any downstream analysis

	Boolean keep_irregular_chr_in_bfilt_peak = false # when filtering with blacklist
								# do not filter peaks with irregular chr name
								# and just keep them in bfilt_peak file
								# (e.g. keep chr1_AABBCC, AABR07024382.1, ...)
								# reg-ex pattern for regular chr names: /chr[\dXY]+[ \t]/
	Int cap_num_peak = 300000	# cap number of raw peaks called from MACS2
	Float pval_thresh = 0.01	# p.value threshold for MACS2
	Int smooth_win = 150		# size of smoothing window

	Boolean enable_idr = false 	# enable IDR analysis on raw peaks
	Float idr_thresh = 0.1		# IDR threshold

	Boolean disable_ataqc = false

	### resources (disks: for cloud platforms)
	String disks

	Int trim_adapter_cpu = 2
	Int trim_adapter_mem_mb = 12000
	Int trim_adapter_time_hr = 24

	Int bowtie2_cpu = 4
	Int bowtie2_mem_mb = 20000
	Int bowtie2_time_hr = 48

	Int filter_cpu = 2
	Int filter_mem_mb = 20000
	Int filter_time_hr = 24

	Int bam2ta_cpu = 2
	Int bam2ta_mem_mb = 10000
	Int bam2ta_time_hr = 6

	Int spr_mem_mb = 16000

	Int xcor_cpu = 2
	Int xcor_mem_mb = 16000
	Int xcor_time_hr = 6

	Int macs2_mem_mb = 16000
	Int macs2_time_hr = 24

	Int ataqc_mem_mb = 16000
	Int ataqc_mem_java_mb = 15000
	Int ataqc_time_hr = 24

	#### input file definition
		# pipeline can start from any type of inputs and then leave all other types undefined
		# supported types: fastq, bam, nodup_bam (filtered bam), ta (tagAlign), peak
		# define up to 6 replicates
		# [rep_id] is for each replicate

 	### fastqs and adapters  	
	 	# [merge_id] is for pooing fastqs after trimming adapters
	 	# if adapters defined with any style, keep the same structure/dimension as fastq arrays
	 	# only defined adapters will be trimmed
	 	# or undefined adapters will be detected/trimmed by trim_adapter.auto_detect_adapter=true 
	 	# so you can selectively detect/trim adapters for a specific fastq
 		# [read_end_id] is for fastq R1 or fastq R2

	### other input types (bam, nodup_bam, ta)
	Array[File] bams = [] 		# [rep_id]
	Array[File] nodup_bams = [] # [rep_id]
	Array[File] tas = []		# [rep_id]

	### other input types (peak)
	Array[File] peaks = []		# [PAIR(rep_id1,rep_id2)]. example for 3 reps: [rep1_rep2, rep1_rep3, rep2_rep3]
	Array[File] peaks_pr1 = []	# [rep_id]. do not define if true_rep=true
	Array[File] peaks_pr2 = []	# [rep_id]. do not define if true_rep=true
	File? peak_ppr1				# do not define if you have a single replicate or true_rep=true
	File? peak_ppr2				# do not define if you have a single replicate or true_rep=true
	File? peak_pooled			# do not define if you have a single replicate or true_rep=true

	### other inputs used for resuming pipelines (QC/txt/log/png files, ...)
	File? ta_pooled
	Array[File] read_len_logs = []
	Array[File] flagstat_qcs = []
	Array[File] align_logs = []
	Array[File] pbc_qcs = []
	Array[File] dup_qcs = []
	Array[File] nodup_flagstat_qcs = []
	Array[File] mito_dup_logs = []
	Array[File] sig_pvals = []
	Array[File] xcor_plots = []
	Array[File] xcor_scores = []
	Array[File] macs2_frip_qcs = []
	Array[File] macs2_pr1_frip_qcs = []
	Array[File] macs2_pr2_frip_qcs = []
	File? macs2_pooled_frip_qc_
	File? macs2_ppr1_frip_qc_
	File? macs2_ppr2_frip_qc_
	Array[File] ataqc_htmls = []
	Array[File] ataqc_txts = []

	### read genome data and paths
	call read_genome_tsv { input:genome_tsv = genome_tsv }
	File bowtie2_idx_tar = read_genome_tsv.genome['bowtie2_idx_tar']
	File blacklist = read_genome_tsv.genome['blacklist']
	File chrsz = read_genome_tsv.genome['chrsz']
	String gensz = read_genome_tsv.genome['gensz']
	File ref_fa = read_genome_tsv.genome['ref_fa']
	# genome data for ATAQC
	File tss_enrich = read_genome_tsv.genome['tss_enrich']
	File dnase = read_genome_tsv.genome['dnase']
	File prom = read_genome_tsv.genome['prom']
	File enh = read_genome_tsv.genome['enh']
	File reg2map = read_genome_tsv.genome['reg2map']
	File reg2map_bed = read_genome_tsv.genome['reg2map_bed']
	File roadmap_meta = read_genome_tsv.genome['roadmap_meta']

	### temp vars (do not define these)
	String peak_type = 'narrowPeak' # peak type for IDR and overlap
	String idr_rank = 'p.value' # IDR ranking method

	### pipeline starts here
	# Parse fastq and corresponding adapters files. There needs to be a file listing TSVs, each of which corresponds
	# to a replicate. In each replicate's TSV, there needs to be a 2 row table, with row 1 corresponding to R1 FASTQs
	# and row 2 corresponding to R2 FASTQs
	File fastq_tsv_list
	call read_lines_sub.parse_attach_file_list as read_fastq_tsv_list { input : file_listing = fastq_tsv_list }
	scatter( tsv in read_fastq_tsv_list.files ) {
		call read_tsv_sub.read_tsv as read_fastq_lists {
			input : tsv = tsv
		}
	}
	Array[Array[Array[File]]] fastqs_ = read_fastq_lists.parsed

	File? adapter_tsv_list
	Boolean adapters_specified = defined(adapter_tsv_list)
	if ( adapters_specified ) {
		call read_lines_sub.parse_attach_file_list as read_adapter_tsv_list { input : file_listing = adapter_tsv_list }
		scatter( tsv in read_adapter_tsv_list.files ) {
			call read_tsv_sub.read_tsv as read_adapter_lists {
				input : tsv = tsv
			}
		}
		Array[Array[Array[String]]] adapters = read_adapter_lists.parsed
	}
	Array[Array[Array[String]]] adapters_ = if adapters_specified then adapters_specified else []

	## temp vars for resuming pipelines
	Boolean need_to_process_ta = length(peaks_pr1)==0 && length(peaks)==0
	Boolean need_to_process_nodup_bam = need_to_process_ta && length(tas)==0
	Boolean need_to_process_bam = need_to_process_nodup_bam && length(nodup_bams)==0
	Boolean need_to_process_fastq = need_to_process_bam && length(bams)==0

	scatter( i in range(if need_to_process_fastq then length(fastqs_) else 0) ) {
		# trim adapters and merge trimmed fastqs
		call trim_adapter { input :
			fastqs = fastqs_[i],
			adapters = if length(adapters_)>0 then adapters_[i] else [],
			auto_detect_adapter = auto_detect_adapter,
			paired_end = paired_end,
			min_trim_len = cutadapt_min_trim_len,
			err_rate = cutadapt_err_rate,

			cpu = trim_adapter_cpu,
			mem_mb = trim_adapter_mem_mb,
			time_hr = trim_adapter_time_hr,
			disks = disks,
			docker = docker
		}
		# align trimmed/merged fastqs with bowtie2s
		call bowtie2 { input :
			idx_tar = bowtie2_idx_tar,
			fastqs = trim_adapter.trimmed_merged_fastqs, #[R1,R2]
			score_min = bowtie2_score_min,
			paired_end = paired_end,
			multimapping = multimapping,

			cpu = bowtie2_cpu,
			mem_mb = bowtie2_mem_mb,
			time_hr = bowtie2_time_hr,
			disks = disks,
			docker = docker
		}
	}

	Array[File] bams_ = flatten([bowtie2.bam, bams])
	scatter( bam in if need_to_process_bam then bams_ else [] ) {
		# filter/dedup bam
		call filter { input :
			bam = bam,
			paired_end = paired_end,
			dup_marker = dup_marker,
			mapq_thresh = mapq_thresh,
			no_dup_removal = no_dup_removal,
			multimapping = multimapping,
			mito_chr_name = mito_chr_name,

			cpu = filter_cpu,
			mem_mb = filter_mem_mb,
			time_hr = filter_time_hr,
			disks = disks,
			docker = docker
		}
	}

	Array[File] nodup_bams_ = flatten([filter.nodup_bam, nodup_bams])
	scatter( bam in if need_to_process_nodup_bam then nodup_bams_ else [] ) {
		# convert bam to tagalign and subsample it if necessary
		call bam2ta { input :
			bam = bam,
			disable_tn5_shift = if pipeline_type=='atac' then false else true,
			regex_grep_v_ta = regex_filter_reads,
			subsample = subsample_reads,
			paired_end = paired_end,
			mito_chr_name = mito_chr_name,

			cpu = bam2ta_cpu,
			mem_mb = bam2ta_mem_mb,
			time_hr = bam2ta_time_hr,
			disks = disks,
			docker = docker
		}
	}

	Array[File] tas_ = if align_only then [] else flatten([bam2ta.ta, tas])
	Array[File] tas__ = if need_to_process_ta then tas_ else []
	scatter( ta in tas__ ) {
		# call peaks on tagalign
		call macs2 { input :
			ta = ta,
			gensz = gensz,
			chrsz = chrsz,
			cap_num_peak = cap_num_peak,
			pval_thresh = pval_thresh,
			smooth_win = smooth_win,
			make_signal = true,
			blacklist = blacklist,
			keep_irregular_chr_in_bfilt_peak = keep_irregular_chr_in_bfilt_peak,

			mem_mb = macs2_mem_mb,
			disks = disks,
			time_hr = macs2_time_hr,
			docker = docker
		}
	}
	if ( length(tas__)>1 ) {
		# pool tagaligns from true replicates
		call pool_ta { input :
			tas = tas__,
			docker = docker
		}
		# call peaks on pooled replicate
		call macs2 as macs2_pooled { input :
			ta = pool_ta.ta_pooled,
			gensz = gensz,
			chrsz = chrsz,
			cap_num_peak = cap_num_peak,
			pval_thresh = pval_thresh,
			smooth_win = smooth_win,
			make_signal = true,
			blacklist = blacklist,
			keep_irregular_chr_in_bfilt_peak = keep_irregular_chr_in_bfilt_peak,

			mem_mb = macs2_mem_mb,
			disks = disks,
			time_hr = macs2_time_hr,
			docker = docker
		}
	}
	if ( enable_xcor && length(xcor_scores)<1 ) {
		scatter( ta in tas__ ) {
			# subsample tagalign (non-mito) and cross-correlation analysis
			call xcor { input :
				ta = ta,
				subsample = xcor_subsample_reads,
				paired_end = paired_end,
				mito_chr_name = mito_chr_name,

				cpu = xcor_cpu,
				mem_mb = xcor_mem_mb,
				time_hr = xcor_time_hr,
				disks = disks,
				docker = docker
			}
		}
	}

	if ( !true_rep_only ) {
		scatter( ta in tas__ ) {
			# make two self pseudo replicates per true replicate
			call spr { input :
				ta = ta,
				paired_end = paired_end,
				mem_mb = spr_mem_mb,
				docker = docker
			}
			# call peaks on 1st pseudo replicated tagalign 
			call macs2 as macs2_pr1 { input :
				ta = spr.ta_pr1,
				gensz = gensz,
				chrsz = chrsz,
				cap_num_peak = cap_num_peak,
				pval_thresh = pval_thresh,
				smooth_win = smooth_win,
				blacklist = blacklist,
				make_signal = false,
				keep_irregular_chr_in_bfilt_peak = keep_irregular_chr_in_bfilt_peak,

				mem_mb = macs2_mem_mb,
				disks = disks,
				time_hr = macs2_time_hr,
				docker = docker
			}
			# call peaks on 2nd pseudo replicated tagalign 
			call macs2 as macs2_pr2 { input :
				ta = spr.ta_pr2,
				gensz = gensz,
				chrsz = chrsz,
				cap_num_peak = cap_num_peak,
				pval_thresh = pval_thresh,
				smooth_win = smooth_win,
				blacklist = blacklist,
				make_signal = false,
				keep_irregular_chr_in_bfilt_peak = keep_irregular_chr_in_bfilt_peak,

				mem_mb = macs2_mem_mb,
				disks = disks,
				time_hr = macs2_time_hr,
				docker = docker
			}
		}
	}

	if ( !true_rep_only && length(tas__)>1 ) {
		# pool tagaligns from pseudo replicates
		call pool_ta as pool_ta_pr1 { input :
			tas = spr.ta_pr1,
			docker = docker
		}
		call pool_ta as pool_ta_pr2 { input :
			tas = spr.ta_pr2,
			docker = docker
		}
		# call peaks on 1st pooled pseudo replicates
		call macs2 as macs2_ppr1 { input :
			ta = pool_ta_pr1.ta_pooled,
			gensz = gensz,
			chrsz = chrsz,
			cap_num_peak = cap_num_peak,
			pval_thresh = pval_thresh,
			smooth_win = smooth_win,
			blacklist = blacklist,
			make_signal = false,
			keep_irregular_chr_in_bfilt_peak = keep_irregular_chr_in_bfilt_peak,

			mem_mb = macs2_mem_mb,
			disks = disks,
			time_hr = macs2_time_hr,
			docker = docker
		}
		# call peaks on 2nd pooled pseudo replicates
		call macs2 as macs2_ppr2 { input :
			ta = pool_ta_pr2.ta_pooled,
			gensz = gensz,
			chrsz = chrsz,
			cap_num_peak = cap_num_peak,
			pval_thresh = pval_thresh,
			smooth_win = smooth_win,
			blacklist = blacklist,
			make_signal = false,
			keep_irregular_chr_in_bfilt_peak = keep_irregular_chr_in_bfilt_peak,

			mem_mb = macs2_mem_mb,
			disks = disks,
			time_hr = macs2_time_hr,
			docker = docker
		}
	}

	# make peak arrays
	Array[File] peaks_ = flatten([macs2.npeak, peaks])

	# generate all possible pairs of true replicates (pair: left=prefix, right=[peak1,peak2])
	Array[Pair[String,Array[File]]] peak_pairs =  
		if length(peaks_)<=1 then [] # 1 rep
		else if length(peaks_)<=2 then # 2 reps
			 [('rep1-rep2',[peaks_[0],peaks_[1]])]
		else if length(peaks_)<=3 then # 3 reps
			 [('rep1-rep2',[peaks_[0],peaks_[1]]), ('rep1-rep3',[peaks_[0],peaks_[2]]),
			  ('rep2-rep3',[peaks_[1],peaks_[2]])]
		else if length(peaks_)<=4 then # 4 reps
			 [('rep1-rep2',[peaks_[0],peaks_[1]]), ('rep1-rep3',[peaks_[0],peaks_[2]]), ('rep1-rep4',[peaks_[0],peaks_[3]]),
			  ('rep2-rep3',[peaks_[1],peaks_[2]]), ('rep2-rep4',[peaks_[1],peaks_[3]]),
			  ('rep3-rep4',[peaks_[2],peaks_[3]])]
		else if length(peaks_)<=5 then # 5 reps
			 [('rep1-rep2',[peaks_[0],peaks_[1]]), ('rep1-rep3',[peaks_[0],peaks_[2]]), ('rep1-rep4',[peaks_[0],peaks_[3]]), ('rep1-rep5',[peaks_[0],peaks_[4]]),
			  ('rep2-rep3',[peaks_[1],peaks_[2]]), ('rep2-rep4',[peaks_[1],peaks_[3]]), ('rep2-rep5',[peaks_[1],peaks_[4]]),
			  ('rep3-rep4',[peaks_[2],peaks_[3]]), ('rep3-rep5',[peaks_[2],peaks_[4]]),
			  ('rep4-rep5',[peaks_[3],peaks_[4]])]
		else # 6 reps
			 [('rep1-rep2',[peaks_[0],peaks_[1]]), ('rep1-rep3',[peaks_[0],peaks_[2]]), ('rep1-rep4',[peaks_[0],peaks_[3]]), ('rep1-rep5',[peaks_[0],peaks_[4]]), ('rep1-rep6',[peaks_[0],peaks_[5]]),
			  ('rep2-rep3',[peaks_[1],peaks_[2]]), ('rep2-rep4',[peaks_[1],peaks_[3]]), ('rep2-rep5',[peaks_[1],peaks_[4]]), ('rep2-rep6',[peaks_[1],peaks_[5]]),
			  ('rep3-rep4',[peaks_[2],peaks_[3]]), ('rep3-rep5',[peaks_[2],peaks_[4]]), ('rep3-rep6',[peaks_[2],peaks_[5]]),
			  ('rep4-rep5',[peaks_[3],peaks_[4]]), ('rep4-rep6',[peaks_[3],peaks_[5]]),
			  ('rep5-rep6',[peaks_[4],peaks_[5]])]
	if ( length(peaks_)>0 ) {
		scatter( pair in peak_pairs ) {
			# Naive overlap on every pair of true replicates
			call overlap { input :
				prefix = pair.left,
				peak1 = pair.right[0],
				peak2 = pair.right[1],
				peak_pooled = select_first([macs2_pooled.npeak, peak_pooled]),
				peak_type = peak_type,
				blacklist = blacklist,
				chrsz = chrsz,
				keep_irregular_chr_in_bfilt_peak = keep_irregular_chr_in_bfilt_peak,
				ta = if defined(ta_pooled) then ta_pooled else pool_ta.ta_pooled,
				docker = docker
			}
		}
	}
	if ( length(peaks_)>0 && enable_idr ) {
		scatter( pair in peak_pairs ) {
			# IDR on every pair of true replicates
			call idr { input : 
				prefix = pair.left,
				peak1 = pair.right[0],
				peak2 = pair.right[1],
				peak_pooled = select_first([macs2_pooled.npeak, peak_pooled]),
				idr_thresh = idr_thresh,
				peak_type = peak_type,
				rank = idr_rank,
				blacklist = blacklist,
				chrsz = chrsz,
				keep_irregular_chr_in_bfilt_peak = keep_irregular_chr_in_bfilt_peak,
				ta = if defined(ta_pooled) then ta_pooled else pool_ta.ta_pooled,
				docker = docker
			}
		}
	}

	Array[File] peaks_pr1_ = flatten(select_all([macs2_pr1.npeak, peaks_pr1]))
	Array[File] peaks_pr2_ = flatten(select_all([macs2_pr2.npeak, peaks_pr2]))

	scatter( i in range(length(peaks_pr1_)) ) {
		# Naive overlap on pseduo replicates
		call overlap as overlap_pr { input : 
			prefix = "rep"+(i+1)+"-pr",
			peak1 = peaks_pr1_[i],
			peak2 = peaks_pr2_[i],
			peak_pooled = peaks_[i],
			peak_type = peak_type,
			blacklist = blacklist,
			chrsz = chrsz,
			keep_irregular_chr_in_bfilt_peak = keep_irregular_chr_in_bfilt_peak,
			ta = if length(tas_)>0 then tas_[i] else if defined(ta_pooled) then ta_pooled else pool_ta.ta_pooled,
			docker = docker
		}
	}
	if ( enable_idr ) {
		scatter( i in range(length(peaks_pr1_)) ) {
			# IDR on pseduo replicates
			call idr as idr_pr { input : 
				prefix = "rep"+(i+1)+"-pr",
				peak1 = peaks_pr1_[i],
				peak2 = peaks_pr2_[i],
				peak_pooled = peaks_[i],
				idr_thresh = idr_thresh,
				peak_type = peak_type,
				rank = idr_rank,
				blacklist = blacklist,
				chrsz = chrsz,
				keep_irregular_chr_in_bfilt_peak = keep_irregular_chr_in_bfilt_peak,
				ta = if length(tas_)>0 then tas_[i] else if defined(ta_pooled) then ta_pooled else pool_ta.ta_pooled,
				docker = docker
			}
		}
	}
	if ( length(peaks_pr1_)>1 ) {
		# Naive overlap on pooled pseudo replicates
		call overlap as overlap_ppr { input : 
			prefix = "ppr",
			peak1 = select_first([macs2_ppr1.npeak, peak_ppr1]),
			peak2 = select_first([macs2_ppr2.npeak, peak_ppr2]),
			peak_pooled = select_first([macs2_pooled.npeak, peak_pooled]),
			peak_type = peak_type,
			blacklist = blacklist,
			chrsz = chrsz,
			keep_irregular_chr_in_bfilt_peak = keep_irregular_chr_in_bfilt_peak,
			ta = if defined(ta_pooled) then ta_pooled else pool_ta.ta_pooled,
			docker = docker
		}
	}
	if ( enable_idr && length(peaks_pr1_)>1  ) {
		# IDR on pooled pseduo replicates
		call idr as idr_ppr { input : 
			docker = docker,
			prefix = "ppr",
			peak1 = select_first([macs2_ppr1.npeak, peak_ppr1]),
			peak2 = select_first([macs2_ppr2.npeak, peak_ppr2]),
			peak_pooled = select_first([macs2_pooled.npeak, peak_pooled]),
			idr_thresh = idr_thresh,
			peak_type = peak_type,
			rank = idr_rank,
			blacklist = blacklist,
			chrsz = chrsz,
			keep_irregular_chr_in_bfilt_peak = keep_irregular_chr_in_bfilt_peak,
			ta = if defined(ta_pooled) then ta_pooled else pool_ta.ta_pooled
		}
	}
	if ( !align_only && !true_rep_only ) {
		# reproducibility QC for overlapping peaks
		call reproducibility as reproducibility_overlap { input :
			prefix = 'overlap',
			peaks = overlap.bfilt_overlap_peak,
			peaks_pr = overlap_pr.bfilt_overlap_peak,
			peak_ppr = overlap_ppr.bfilt_overlap_peak,
			peak_type = peak_type,
			chrsz = chrsz,
			keep_irregular_chr_in_bfilt_peak = keep_irregular_chr_in_bfilt_peak,
			docker = docker
		}
	}
	if ( !align_only && !true_rep_only && enable_idr ) {
		# reproducibility QC for IDR peaks
		call reproducibility as reproducibility_idr { input :
			prefix = 'idr',
			peaks = idr.bfilt_idr_peak,
			peaks_pr = idr_pr.bfilt_idr_peak,
			peak_ppr = idr_ppr.bfilt_idr_peak,
			peak_type = peak_type,
			chrsz = chrsz,
			keep_irregular_chr_in_bfilt_peak = keep_irregular_chr_in_bfilt_peak,
			docker = docker
		}
	}

	# count number of replicates for ataqc	
	Int num_rep = if disable_ataqc || length(ataqc_htmls)>0 then 0
		else if length(fastqs_)>0 then length(fastqs_)
		else if length(bams_)>0 then length(bams_)
		else if length(tas_)>0 then length(tas_)
		else if length(peaks_pr1)>0 then length(peaks_pr1)
		else 0
	File? null

	Array[File] read_len_logs_ = flatten([read_len_logs, bowtie2.read_len_log])
	Array[File] flagstat_qcs_ = flatten([flagstat_qcs, bowtie2.flagstat_qc])
	Array[File] align_logs_ = flatten([align_logs, bowtie2.align_log])
	Array[File] pbc_qcs_ = flatten([pbc_qcs, filter.pbc_qc])
	Array[File] dup_qcs_ = flatten([dup_qcs, filter.dup_qc])
	Array[File] nodup_flagstat_qcs_ = flatten([nodup_flagstat_qcs, filter.flagstat_qc])
	Array[File] mito_dup_logs_ = flatten([mito_dup_logs, filter.mito_dup_log])
	Array[File] xcor_plots_ = flatten(select_all([xcor_plots, xcor.plot_png]))
	Array[File] xcor_scores_ = flatten(select_all([xcor_scores, xcor.score]))
	Array[File] sig_pvals_ = flatten([sig_pvals, macs2.sig_pval])
	Array[File] macs2_frip_qcs_ = flatten([macs2_frip_qcs, macs2.frip_qc])
	Array[File] macs2_pr1_frip_qcs_ = flatten(select_all([macs2_pr1_frip_qcs, macs2_pr1.frip_qc]))
	Array[File] macs2_pr2_frip_qcs_ = flatten(select_all([macs2_pr2_frip_qcs, macs2_pr2.frip_qc]))

	scatter( i in range(num_rep) ) {
		call ataqc { input : 
			paired_end = paired_end,
			read_len_log = if length(read_len_logs_)>0 then read_len_logs_[i] else null,
			flagstat_log = if length(flagstat_qcs_)>0 then flagstat_qcs_[i] else null,
			bowtie2_log = if length(align_logs_)>0 then align_logs_[i] else null,
			pbc_log = if length(pbc_qcs_)>0 then pbc_qcs_[i] else null,
			dup_log = if length(dup_qcs_)>0 then dup_qcs_[i] else null,
			bam = if length(bams_)>0 then bams_[i] else null,
			nodup_flagstat_log = if length(nodup_flagstat_qcs_)>0 then nodup_flagstat_qcs_[i] else null,
			mito_dup_log = if length(mito_dup_logs_)>0 then mito_dup_logs_[i] else null,
			nodup_bam = if length(nodup_bams_)>0 then nodup_bams_[i] else null,
			ta = if length(tas_)>0 then tas_[i] else null,
			peak = if align_only then null
					else if enable_idr then select_first([idr_pr.bfilt_idr_peak])[i]
					else reproducibility_overlap.optimal_peak,
			idr_peak = if align_only || !enable_idr then null
					else reproducibility_idr.optimal_peak, #idr_peaks_ataqc[i],
			overlap_peak= if align_only then null
					else reproducibility_overlap.optimal_peak, #overlap_peaks_ataqc[i],
			bigwig = if length(sig_pvals_)>0 then sig_pvals_[i] else null,
			ref_fa = ref_fa,
			chrsz = chrsz,
			tss_enrich = tss_enrich,
			blacklist = blacklist,
			dnase = dnase,
			prom = prom,
			enh = enh,
			reg2map_bed = reg2map_bed,
			reg2map = reg2map,
			roadmap_meta = roadmap_meta,
			mito_chr_name = mito_chr_name,

			mem_mb = ataqc_mem_mb,
			mem_java_mb = ataqc_mem_java_mb,
			time_hr = ataqc_time_hr,
			docker = docker
		}
	}

	# Generate final QC report and JSON		
	call qc_report { input :
		pipeline_ver = pipeline_ver,
		title = title,
		description = description,
		genome = basename(genome_tsv),
		multimapping = multimapping,
		paired_end = paired_end,
		pipeline_type = pipeline_type,
		peak_caller = 'macs2',
		macs2_cap_num_peak = cap_num_peak,
		idr_thresh = idr_thresh,
		flagstat_qcs = flagstat_qcs_,
		nodup_flagstat_qcs = nodup_flagstat_qcs_,
		dup_qcs = dup_qcs_,
		pbc_qcs = pbc_qcs_,
		xcor_plots = xcor_plots_,
		xcor_scores = xcor_scores_,

		frip_macs2_qcs = macs2_frip_qcs_,
		frip_macs2_qcs_pr1 = macs2_pr1_frip_qcs_,
		frip_macs2_qcs_pr2 = macs2_pr2_frip_qcs_,
		frip_macs2_qc_pooled = if defined(macs2_pooled_frip_qc_) then macs2_pooled_frip_qc_ else macs2_pooled.frip_qc,
		frip_macs2_qc_ppr1 = if defined(macs2_ppr1_frip_qc_) then macs2_ppr1_frip_qc_ else macs2_ppr1.frip_qc,
		frip_macs2_qc_ppr2 = if defined(macs2_ppr2_frip_qc_) then macs2_ppr2_frip_qc_ else macs2_ppr2.frip_qc,

		idr_plots = idr.idr_plot,
		idr_plots_pr = idr_pr.idr_plot,
		idr_plot_ppr = idr_ppr.idr_plot,
		frip_idr_qcs = idr.frip_qc,
		frip_idr_qcs_pr = idr_pr.frip_qc,
		frip_idr_qc_ppr = idr_ppr.frip_qc,
		frip_overlap_qcs = overlap.frip_qc,
		frip_overlap_qcs_pr = overlap_pr.frip_qc,
		frip_overlap_qc_ppr = overlap_ppr.frip_qc,
		idr_reproducibility_qc = reproducibility_idr.reproducibility_qc,
		overlap_reproducibility_qc = reproducibility_overlap.reproducibility_qc,
		ataqc_txts = flatten([ataqc.txt, ataqc_txts]),
		ataqc_htmls = flatten([ataqc.html, ataqc_htmls]),
		docker = docker
	}

	output {
		File report = qc_report.report
		File qc_json = qc_report.qc_json
		Boolean qc_json_ref_match = qc_report.qc_json_ref_match
	}
}

task trim_adapter { # trim adapters and merge trimmed fastqs
	Array[Array[File]] fastqs 		# [merge_id][read_end_id]
	Array[Array[String]] adapters 	# [merge_id][read_end_id]
	Boolean paired_end
	# mandatory
	Boolean auto_detect_adapter	# automatically detect/trim adapters
	# optional
	Int min_trim_len 		# minimum trim length for cutadapt -m
	Float err_rate			# Maximum allowed adapter error rate 
							# for cutadapt -e	
	Int cpu
	Int mem_mb
	Int time_hr
	String disks
	String docker

	command {
		python $(which encode_trim_adapter.py) \
			${write_tsv(fastqs)} \
			--adapters ${write_tsv(adapters)} \
			${if paired_end then "--paired-end" else ""} \
			${if auto_detect_adapter then "--auto-detect-adapter" else ""} \
			${"--min-trim-len " + min_trim_len} \
			${"--err-rate " + err_rate} \
			${"--nth " + cpu}
	}
	output {
		# WDL glob() globs in an alphabetical order
		# so R1 and R2 can be switched, which results in an
		# unexpected behavior of a workflow
		# so we prepend merge_fastqs_'end'_ (R1 or R2)
		# to the basename of original filename
		# this prefix will be later stripped in bowtie2 task
		Array[File] trimmed_merged_fastqs = glob("merge_fastqs_R?_*.fastq.gz")
	}
	runtime {
		cpu : cpu
		memory : "${mem_mb} MB"
		time : time_hr
		disks : disks
		preemptible : 3
		docker : "${docker}"
	}
}

task bowtie2 {
	File idx_tar 		# reference bowtie2 index tar
	Array[File] fastqs 	# [read_end_id]
	Boolean paired_end
	Int multimapping
	String score_min 	# min acceptable alignment score func
						# w.r.t read length
	Int cpu
	Int mem_mb
	Int time_hr
	String disks
	String docker

	command {
		python $(which encode_bowtie2.py) \
			${idx_tar} \
			${sep=' ' fastqs} \
			${if paired_end then "--paired-end" else ""} \
			${"--multimapping " + multimapping} \
			${if score_min!="" then "--score-min " + score_min else ""} \
			${"--nth " + cpu}
	}
	output {
		File bam = glob("*.bam")[0]
		File bai = glob("*.bai")[0]
		File align_log = glob("*.align.log")[0]
		File flagstat_qc = glob("*.flagstat.qc")[0]
		File read_len_log = glob("*.read_length.txt")[0] # read_len
	}
	runtime {
		cpu : cpu
		memory : "${mem_mb} MB"
		time : time_hr
		disks : disks
		preemptible: 0
		docker : "${docker}"
	}
}

task filter {
	File bam
	Boolean paired_end
	Int multimapping
	String dup_marker 			# picard.jar MarkDuplicates (picard) or 
								# sambamba markdup (sambamba)
	Int mapq_thresh				# threshold for low MAPQ reads removal
	Boolean no_dup_removal 		# no dupe reads removal when filtering BAM
								# dup.qc and pbc.qc will be empty files
								# and nodup_bam in the output is 
								# filtered bam with dupes	
	String mito_chr_name
	Int cpu
	Int mem_mb
	Int time_hr
	String disks
	String docker

	command {
		${if no_dup_removal then "touch null.dup.qc null.pbc.qc null.mito_dup.txt; " else ""}
		touch null
		python $(which encode_filter.py) \
			${bam} \
			${if paired_end then "--paired-end" else ""} \
			${"--multimapping " + multimapping} \
			${"--dup-marker " + dup_marker} \
			${"--mapq-thresh " + mapq_thresh} \
			${if no_dup_removal then "--no-dup-removal" else ""} \
			${"--mito-chr-name " + mito_chr_name} \
			${"--nth " + cpu}
	}
	output {
		File nodup_bam = glob("*.bam")[0]
		File nodup_bai = glob("*.bai")[0]
		File flagstat_qc = glob("*.flagstat.qc")[0]
		File dup_qc = if no_dup_removal then glob("null")[0] else glob("*.dup.qc")[0]
		File pbc_qc = if no_dup_removal then glob("null")[0] else glob("*.pbc.qc")[0]
		File mito_dup_log = if no_dup_removal then glob("null")[0] else glob("*.mito_dup.txt")[0] # mito_dups, fract_dups_from_mito
	}
	runtime {
		cpu : cpu
		memory : "${mem_mb} MB"
		time : time_hr
		disks : disks
		preemptible : 3
		docker : "${docker}"
	}
}

task bam2ta {
	File bam
	Boolean paired_end
	Boolean disable_tn5_shift 	# no tn5 shifting (it's for dnase-seq)
	String regex_grep_v_ta   	# Perl-style regular expression pattern 
                        		# to remove matching reads from TAGALIGN
	String mito_chr_name 		# mito chromosome name
	Int subsample 				# number of reads to subsample TAGALIGN
								# this affects all downstream analysis
	Int cpu
	Int mem_mb
	Int time_hr
	String disks
	String docker

	command {
		python $(which encode_bam2ta.py) \
			${bam} \
			${if paired_end then "--paired-end" else ""} \
			${if disable_tn5_shift then "--disable-tn5-shift" else ""} \
			${if regex_grep_v_ta!="" then "--regex-grep-v-ta '"+regex_grep_v_ta+"'" else ""} \
			${"--mito-chr-name " + mito_chr_name} \
			${"--subsample " + subsample} \
			${"--nth " + cpu}
	}
	output {
		File ta = glob("*.tagAlign.gz")[0]
	}
	runtime {
		cpu : cpu
		memory : "${mem_mb} MB"
		time : time_hr
		disks : disks
		preemptible : 3
		docker : "${docker}"
	}
}

task spr { # make two self pseudo replicates
	File ta
	Boolean paired_end

	Int mem_mb
	String docker

	command {
		python $(which encode_spr.py) \
			${ta} \
			${if paired_end then "--paired-end" else ""}
	}
	output {
		File ta_pr1 = glob("*.pr1.tagAlign.gz")[0]
		File ta_pr2 = glob("*.pr2.tagAlign.gz")[0]
	}
	runtime {
		cpu : 1
		memory : "${mem_mb} MB"
		time : 1
		disks : "local-disk 50 HDD"
		preemptible : 3
		docker : "${docker}"
	}
}

task pool_ta {
	Array[File] tas

	String docker

	command {
		python $(which encode_pool_ta.py) \
			${sep=' ' tas}
	}
	output {
		File ta_pooled = glob("*.tagAlign.gz")[0]
	}
	runtime {
		cpu : 1
		memory : "3700 MB"
		time : 1
		disks : "local-disk 50 HDD"
		preemptible : 3
		docker : "${docker}"
	}
}

task xcor {
	File ta
	Boolean paired_end
	String mito_chr_name
	Int subsample  # number of reads to subsample TAGALIGN
				# this will be used for xcor only
				# will not affect any downstream analysis
	Int cpu
	Int mem_mb	
	Int time_hr
	String disks
	String docker

	command {
		python $(which encode_xcor.py) \
			${ta} \
			${if paired_end then "--paired-end" else ""} \
			${"--mito-chr-name " + mito_chr_name} \
			${"--subsample " + subsample} \
			--speak=0 \
			${"--nth " + cpu}
	}
	output {
		File plot_pdf = glob("*.cc.plot.pdf")[0]
		File plot_png = glob("*.cc.plot.png")[0]
		File score = glob("*.cc.qc")[0]
		Int fraglen = read_int(glob("*.cc.fraglen.txt")[0])
	}
	runtime {
		cpu : cpu
		memory : "${mem_mb} MB"
		time : time_hr
		disks : disks
		preemptible : 3
		docker : "${docker}"
	}
}

task macs2 {
	File ta
	String gensz		# Genome size (sum of entries in 2nd column of 
                        # chr. sizes file, or hs for human, ms for mouse)
	File chrsz			# 2-col chromosome sizes file
	Int cap_num_peak	# cap number of raw peaks called from MACS2
	Float pval_thresh  	# p.value threshold
	Int smooth_win 		# size of smoothing window
	Boolean make_signal
	File blacklist 		# blacklist BED to filter raw peaks
	Boolean	keep_irregular_chr_in_bfilt_peak
	
	Int mem_mb
	Int time_hr
	String disks
	String docker

	command {
		${if make_signal then "" 
			else "touch null.pval.signal.bigwig null.fc.signal.bigwig"}
		touch null 
		python $(which encode_macs2_atac.py) \
			${ta} \
			${"--gensz "+ gensz} \
			${"--chrsz " + chrsz} \
			${"--cap-num-peak " + cap_num_peak} \
			${"--pval-thresh "+ pval_thresh} \
			${"--smooth-win "+ smooth_win} \
			${if make_signal then "--make-signal" else ""} \
			${if keep_irregular_chr_in_bfilt_peak then "--keep-irregular-chr" else ""} \
			${"--blacklist "+ blacklist}
	}
	output {
		File npeak = glob("*[!.][!b][!f][!i][!l][!t].narrowPeak.gz")[0]
		File bfilt_npeak = glob("*.bfilt.narrowPeak.gz")[0]
		File bfilt_npeak_bb = glob("*.bfilt.narrowPeak.bb")[0]
		Array[File] bfilt_npeak_hammock = glob("*.bfilt.narrowPeak.hammock.gz*")
		File sig_pval = if make_signal then glob("*.pval.signal.bigwig")[0] else glob("null")[0]
		File sig_fc = if make_signal then glob("*.fc.signal.bigwig")[0] else glob("null")[0]
		File frip_qc = glob("*.frip.qc")[0]
	}
	runtime {
		cpu : 1
		memory : "${mem_mb} MB"
		time : time_hr
		disks : disks
		preemptible : 3
		docker : "${docker}"
	}
}

task idr {
	String prefix 		# prefix for IDR output file
	File peak1 			
	File peak2
	File peak_pooled
	Float idr_thresh
	File blacklist 	# blacklist BED to filter raw peaks
	Boolean	keep_irregular_chr_in_bfilt_peak
	# parameters to compute FRiP
	File? ta		# to calculate FRiP
	File chrsz			# 2-col chromosome sizes file
	String peak_type
	String rank

	String docker

	command {
		${if defined(ta) then "" else "touch null.frip.qc"}
		touch null 
		python $(which encode_idr.py) \
			${peak1} ${peak2} ${peak_pooled} \
			${"--prefix " + prefix} \
			${"--idr-thresh " + idr_thresh} \
			${"--peak-type " + peak_type} \
			--idr-rank ${rank} \
			${"--chrsz " + chrsz} \
			${"--blacklist "+ blacklist} \
			${if keep_irregular_chr_in_bfilt_peak then "--keep-irregular-chr" else ""} \
			${"--ta " + ta}
	}
	output {
		File idr_peak = glob("*[!.][!b][!f][!i][!l][!t]."+peak_type+".gz")[0]
		File bfilt_idr_peak = glob("*.bfilt."+peak_type+".gz")[0]
		File bfilt_idr_peak_bb = glob("*.bfilt."+peak_type+".bb")[0]
		Array[File] bfilt_idr_peak_hammock = glob("*.bfilt."+peak_type+".hammock.gz*")
		File idr_plot = glob("*.txt.png")[0]
		File idr_unthresholded_peak = glob("*.txt.gz")[0]
		File idr_log = glob("*.log")[0]
		File frip_qc = if defined(ta) then glob("*.frip.qc")[0] else glob("null")[0]
	}
	runtime {
		cpu : 1
		memory : "7400 MB"
		time : 1
		disks : "local-disk 50 HDD"
		preemptible : 3
		docker : "${docker}"
	}
}

task overlap {
	String prefix 		# prefix for IDR output file
	File peak1
	File peak2
	File peak_pooled
	File blacklist 	# blacklist BED to filter raw peaks
	Boolean	keep_irregular_chr_in_bfilt_peak
	File? ta		# to calculate FRiP
	File chrsz			# 2-col chromosome sizes file
	String peak_type

	String docker

	command {
		${if defined(ta) then "" else "touch null.frip.qc"}
		touch null 
		python $(which encode_naive_overlap.py) \
			${peak1} ${peak2} ${peak_pooled} \
			${"--prefix " + prefix} \
			${"--peak-type " + peak_type} \
			${"--chrsz " + chrsz} \
			${"--blacklist "+ blacklist} \
			--nonamecheck \
			${if keep_irregular_chr_in_bfilt_peak then "--keep-irregular-chr" else ""} \
			${"--ta " + ta}
	}
	output {
		File overlap_peak = glob("*[!.][!b][!f][!i][!l][!t]."+peak_type+".gz")[0]
		File bfilt_overlap_peak = glob("*.bfilt."+peak_type+".gz")[0]
		File bfilt_overlap_peak_bb = glob("*.bfilt."+peak_type+".bb")[0]
		Array[File] bfilt_overlap_peak_hammock = glob("*.bfilt."+peak_type+".hammock.gz*")
		File frip_qc = if defined(ta) then glob("*.frip.qc")[0] else glob("null")[0]
	}
	runtime {
		cpu : 1
		memory : "3700 MB"
		time : 1
		disks : "local-disk 50 HDD"
		preemptible : 3
		docker : "${docker}"
	}
}

task reproducibility {
	String prefix
	Array[File]? peaks # peak files from pair of true replicates
						# in a sorted order. for example of 4 replicates,
						# 1,2 1,3 1,4 2,3 2,4 3,4.
                        # x,y means peak file from rep-x vs rep-y
	Array[File]? peaks_pr	# peak files from pseudo replicates
	File? peak_ppr			# Peak file from pooled pseudo replicate.
	String peak_type
	File chrsz			# 2-col chromosome sizes file
	Boolean	keep_irregular_chr_in_bfilt_peak

	String docker

	command {
		python $(which encode_reproducibility_qc.py) \
			${sep=' ' peaks} \
			--peaks-pr ${sep=' ' peaks_pr} \
			${"--peak-ppr "+ peak_ppr} \
			--prefix ${prefix} \
			${"--peak-type " + peak_type} \
			${if keep_irregular_chr_in_bfilt_peak then "--keep-irregular-chr" else ""} \
			${"--chrsz " + chrsz}
	}
	output {
		File optimal_peak = glob("optimal_peak.*.gz")[0]
		File conservative_peak = glob("conservative_peak.*.gz")[0]
		File optimal_peak_bb = glob("optimal_peak.*.bb")[0]
		File conservative_peak_bb = glob("conservative_peak.*.bb")[0]
		Array[File] optimal_peak_hammock = glob("optimal_peak.*.hammock.gz*")
		Array[File] conservative_peak_hammock = glob("conservative_peak.*.hammock.gz*")
		File reproducibility_qc = glob("*reproducibility.qc")[0]
	}
	runtime {
		cpu : 1
		memory : "3700 MB"
		time : 1
		disks : "local-disk 50 HDD"
		preemptible : 3
		docker : "${docker}"
	}
}

task ataqc { # generate ATAQC report
	Boolean paired_end
	File? read_len_log
	File? flagstat_log
	File? bowtie2_log
	File? bam
	File? nodup_flagstat_log
	File? mito_dup_log
	File? dup_log
	File? pbc_log
	File? nodup_bam
	File? ta
	File? peak
	File? idr_peak 
	File? overlap_peak
	File? bigwig
	# from genome database
	File? ref_fa
	File? chrsz
	File? tss_enrich
	File? blacklist
	File? dnase
	File? prom
	File? enh
	File? reg2map_bed
	File? reg2map
	File? roadmap_meta
	String mito_chr_name

	Int mem_mb
	Int mem_java_mb
	Int time_hr
	String disks
	String docker

	command {
		export _JAVA_OPTIONS="-Xms256M -Xmx${mem_java_mb}M -XX:ParallelGCThreads=1 $_JAVA_OPTIONS"

		python $(which encode_ataqc.py) \
			${if paired_end then "--paired-end" else ""} \
			${"--read-len-log " + read_len_log} \
			${"--flagstat-log " + flagstat_log} \
			${"--bowtie2-log " + bowtie2_log} \
			${"--bam " + bam} \
			${"--nodup-flagstat-log " + nodup_flagstat_log} \
			${"--mito-dup-log " + mito_dup_log} \
			${"--dup-log " + dup_log} \
			${"--pbc-log " + pbc_log} \
			${"--nodup-bam " + nodup_bam} \
			${"--ta " + ta} \
			${"--bigwig " + bigwig} \
			${"--peak " + peak} \
			${"--idr-peak " + idr_peak} \
			${"--overlap-peak " + overlap_peak} \
			${"--ref-fa " + ref_fa} \
			${"--blacklist " + blacklist} \
			${"--chrsz " + chrsz} \
			${"--dnase " + dnase} \
			${"--tss-enrich " + tss_enrich} \
			${"--prom " + prom} \
			${"--enh " + enh} \
			${"--reg2map-bed " + reg2map_bed} \
			${"--reg2map " + reg2map} \
			${"--roadmap-meta " + roadmap_meta} \
			${"--mito-chr-name " + mito_chr_name}

	}
	output {
		File html = glob("*_qc.html")[0]
		File txt = glob("*_qc.txt")[0]
	}
	runtime {
		cpu : 1
		memory : "${mem_mb} MB"
		time : time_hr
		disks : disks
		preemptible : 3
		docker : "${docker}"
	}
}

# gather all outputs and generate 
# - qc.html		: organized final HTML report
# - qc.json		: all QCs
task qc_report {
	# optional metadata
	String pipeline_ver
 	String title # name of sample
	String description # description for sample
	String? genome
	#String? encode_accession_id	# ENCODE accession ID of sample
	# workflow params
	Int multimapping
	Boolean paired_end
	String pipeline_type
	String peak_caller
	Int? macs2_cap_num_peak
	Int? spp_cap_num_peak
	Float idr_thresh
	# QCs
	Array[File]? flagstat_qcs
	Array[File]? nodup_flagstat_qcs
	Array[File]? dup_qcs
	Array[File]? pbc_qcs
	Array[File]? xcor_plots
	Array[File]? xcor_scores
	Array[File]? idr_plots
	Array[File]? idr_plots_pr
	File? idr_plot_ppr
	Array[File]? frip_macs2_qcs
	Array[File]? frip_macs2_qcs_pr1
	Array[File]? frip_macs2_qcs_pr2
	File? frip_macs2_qc_pooled
	File? frip_macs2_qc_ppr1 
	File? frip_macs2_qc_ppr2 
	Array[File]? frip_idr_qcs
	Array[File]? frip_idr_qcs_pr
	File? frip_idr_qc_ppr 
	Array[File]? frip_overlap_qcs
	Array[File]? frip_overlap_qcs_pr
	File? frip_overlap_qc_ppr
	File? idr_reproducibility_qc
	File? overlap_reproducibility_qc
	Array[File]? ataqc_txts
	Array[File]? ataqc_htmls

	File? qc_json_ref

	String docker

	command {
		python $(which encode_qc_report.py) \
			${"--pipeline-ver " + pipeline_ver} \
			${"--title '" + sub(title,"'","_") + "'"} \
			${"--desc '" + sub(description,"'","_") + "'"} \
			${"--genome " + genome} \
			${"--multimapping " + multimapping} \
			${if paired_end then "--paired-end" else ""} \
			--pipeline-type ${pipeline_type} \
			--peak-caller ${peak_caller} \
			${"--macs2-cap-num-peak " + macs2_cap_num_peak} \
			${"--spp-cap-num-peak " + spp_cap_num_peak} \
			--idr-thresh ${idr_thresh} \
			--flagstat-qcs ${sep=' ' flagstat_qcs} \
			--nodup-flagstat-qcs ${sep=' ' nodup_flagstat_qcs} \
			--dup-qcs ${sep=' ' dup_qcs} \
			--pbc-qcs ${sep=' ' pbc_qcs} \
			--xcor-plots ${sep=' ' xcor_plots} \
			--xcor-scores ${sep=' ' xcor_scores} \
			--idr-plots ${sep=' ' idr_plots} \
			--idr-plots-pr ${sep=' ' idr_plots_pr} \
			${"--idr-plot-ppr " + idr_plot_ppr} \
			--frip-macs2-qcs ${sep=' ' frip_macs2_qcs} \
			--frip-macs2-qcs-pr1 ${sep=' ' frip_macs2_qcs_pr1} \
			--frip-macs2-qcs-pr2 ${sep=' ' frip_macs2_qcs_pr2} \
			${"--frip-macs2-qc-pooled " + frip_macs2_qc_pooled} \
			${"--frip-macs2-qc-ppr1 " + frip_macs2_qc_ppr1} \
			${"--frip-macs2-qc-ppr2 " + frip_macs2_qc_ppr2} \
			--frip-idr-qcs ${sep=' ' frip_idr_qcs} \
			--frip-idr-qcs-pr ${sep=' ' frip_idr_qcs_pr} \
			${"--frip-idr-qc-ppr " + frip_idr_qc_ppr} \
			--frip-overlap-qcs ${sep=' ' frip_overlap_qcs} \
			--frip-overlap-qcs-pr ${sep=' ' frip_overlap_qcs_pr} \
			${"--frip-overlap-qc-ppr " + frip_overlap_qc_ppr} \
			${"--idr-reproducibility-qc " + idr_reproducibility_qc} \
			${"--overlap-reproducibility-qc " + overlap_reproducibility_qc} \
			--ataqc-txts ${sep=' ' ataqc_txts} \
			--ataqc-htmls ${sep=' ' ataqc_htmls} \
			--out-qc-html qc.html \
			--out-qc-json qc.json \
			${"--qc-json-ref " + qc_json_ref}		
	}
	output {
		File report = glob('*qc.html')[0]
		File qc_json = glob('*qc.json')[0]
		Boolean qc_json_ref_match = read_string("qc_json_ref_match.txt")=="True"
	}
	runtime {
		cpu : 1
		memory : "3700 MB"
		time : 1
		disks : "local-disk 50 HDD"
		preemptible : 3
		docker : "${docker}"
	}
}

task read_genome_tsv {
	File genome_tsv
	command {
		cat ${genome_tsv} > 'tmp.tsv'
	}
	output {
		Map[String,String] genome = read_map('tmp.tsv')
	}
	runtime {
		cpu : 1
		memory : "3700 MB"
		time : 1
		disks : "local-disk 50 HDD"
		preemptible : 3
		docker : "${docker}"
	}
}

task compare_md5sum {
	Array[String] labels
	Array[File] files
	Array[File] ref_files

	String docker

	command <<<
		python <<CODE	
		from collections import OrderedDict
		import os
		import json
		import hashlib

		def md5sum(filename, blocksize=65536):
		    hash = hashlib.md5()
		    with open(filename, 'rb') as f:
		        for block in iter(lambda: f.read(blocksize), b""):
		            hash.update(block)
		    return hash.hexdigest()

		with open('${write_lines(labels)}','r') as fp:
			labels = fp.read().splitlines()
		with open('${write_lines(files)}','r') as fp:
			files = fp.read().splitlines()
		with open('${write_lines(ref_files)}','r') as fp:
			ref_files = fp.read().splitlines()

		result = OrderedDict()
		match = OrderedDict()
		match_overall = True

		result['tasks'] = []
		result['failed_task_labels'] = []
		result['succeeded_task_labels'] = []
		for i, label in enumerate(labels):
			f = files[i]
			ref_f = ref_files[i]
			md5 = md5sum(f)
			ref_md5 = md5sum(ref_f)
			# if text file, read in contents
			if f.endswith('.qc') or f.endswith('.txt') or \
				f.endswith('.log') or f.endswith('.out'):
				with open(f,'r') as fp:
					contents = fp.read()
				with open(ref_f,'r') as fp:
					ref_contents = fp.read()
			else:
				contents = ''
				ref_contents = ''
			matched = md5==ref_md5
			result['tasks'].append(OrderedDict([
				('label', label),
				('match', matched),
				('md5sum', md5),
				('ref_md5sum', ref_md5),
				('basename', os.path.basename(f)),
				('ref_basename', os.path.basename(ref_f)),
				('contents', contents),
				('ref_contents', ref_contents),
				]))
			match[label] = matched
			match_overall &= matched
			if matched:
				result['succeeded_task_labels'].append(label)
			else:
				result['failed_task_labels'].append(label)		
		result['match_overall'] = match_overall

		with open('result.json','w') as fp:
			fp.write(json.dumps(result, indent=4))
		match_tmp = []
		for key in match:
			val = match[key]
			match_tmp.append('{}\t{}'.format(key, val))
		with open('match.tsv','w') as fp:
			fp.writelines('\n'.join(match_tmp))
		with open('match_overall.txt','w') as fp:
			fp.write(str(match_overall))
		CODE
	>>>
	output {
		Map[String,String] match = read_map('match.tsv') # key:label, val:match
		Boolean match_overall = read_boolean('match_overall.txt')
		File json = glob('result.json')[0] # details (json file)
		String json_str = read_string('result.json') # details (string)
	}
	runtime {
		cpu : 1
		memory : "4000 MB"
		time : 1
		disks : "local-disk 50 HDD"		
	}
}
