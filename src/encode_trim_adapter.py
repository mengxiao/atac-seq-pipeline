#!/usr/bin/env python

# ENCODE DCC adapter trimmer wrapper
# Author: Jin Lee (leepc12@gmail.com)

import sys
import os
import argparse
import multiprocessing
import copy
from detect_adapter import detect_most_likely_adapter
from encode_common import *

def parse_arguments(debug=False):
    parser = argparse.ArgumentParser(prog='ENCODE DCC adapter trimmer.',
                                        description='')
    parser.add_argument('fastqs', nargs='+', type=str,
                        help='TSV file path or list of FASTQs. \
                            FASTQs must be compressed with gzip (with .gz). \
                            Use TSV for multiple fastqs to be merged later. \
                            row=merge_id, col=end_id).')
    parser.add_argument('--auto-detect-adapter', action='store_true',
                        help='Automatically detect/trim adapters \
                            (supported system: Illumina, Nextera and smallRNA).')
    parser.add_argument('--cutadapt-param', type=str, default='-e 0.1 -m 5',
                        help='Parameters for cutadapt \
                            (default: -e 0.1 -m 5; err_rate=0.1, min_trim_len=5).')
    parser.add_argument('--adapter', type=str,
                        help='One adapter to use for all fastqs. '
                            'This will override individual adapters defined in --adapters.')
    parser.add_argument('--adapters', nargs='+', type=str,
                        help='TSV file path or list of adapter strings. \
                            Use TSV for multiple fastqs to be merged later. \
                            row=merge_id, col=end_id).')
    parser.add_argument('--paired-end', action="store_true",
                        help='Paired-end FASTQs.')
    parser.add_argument('--nth', type=int, default=1,
                        help='Number of threads to parallelize.')
    parser.add_argument('--out-dir', default='', type=str,
                            help='Output directory.')
    parser.add_argument('--log-level', default='INFO', 
                        choices=['NOTSET','DEBUG','INFO',
                            'WARNING','CRITICAL','ERROR','CRITICAL'],
                        help='Log level')
    args = parser.parse_args()

    # parse fastqs command line
    if args.fastqs[0].endswith('.gz') or args.fastqs[0].endswith('.fastq') or \
        args.fastqs[0].endswith('.fq'): # it's fastq
        args.fastqs = [[f] for f in args.fastqs] # make it a matrix
    else: # it's TSV
        args.fastqs = read_tsv(args.fastqs[0])

    # parse --adapters command line
    if args.adapters:
        if os.path.exists(args.adapters[0]): # it's TSV
            args.adapters = read_tsv(args.adapters[0])
        else:
            args.adapters = [[a] for a in args.adapters] # make it a matrix

    # if adapter not given
    if not args.adapters: # fill empty string in adapter list
        args.adapters = copy.deepcopy(args.fastqs)
        for i, adapters in enumerate(args.adapters):
            for j, adapter in enumerate(adapters):
                args.adapters[i][j] = ''

    # check if fastqs, adapers have same/correct dimension
    if len(args.adapters)!=len(args.fastqs):
        raise argparse.ArgumentTypeError(
            'fastqs and adapters dimension mismatch.')
    for i, fastqs in enumerate(args.fastqs):
        if args.paired_end and len(fastqs)!=2:
            raise argparse.ArgumentTypeError(
                'Need 2 fastqs per replicate for paired end.')
        if not args.paired_end and len(fastqs)!=1:
            raise argparse.ArgumentTypeError(
                'Need 1 fastq per replicate for single end.')
        if len(fastqs)!=len(args.adapters[i]):
            raise argparse.ArgumentTypeError(
                'fastqs and adapters dimension mismatch.')
            
    log.setLevel(args.log_level)
    log.info(sys.argv)
    return args

def trim_adapter_se(fastq, adapter, adapter_for_all, cutadapt_param, out_dir):
    if adapter:
        prefix = os.path.join(out_dir,
            os.path.basename(strip_ext_fastq(fastq)))
        trimmed = '{}.trim.fastq.gz'.format(prefix)

        cmd = 'cutadapt {} -a {} {} | gzip -nc > {}'.format(
            cutadapt_param,
            adapter_for_all if adapter_for_all else adapter,
            fastq,
            trimmed)     
        run_shell_cmd(cmd)
        return trimmed
    else:
        # make hard link
        linked = os.path.join(out_dir,
            os.path.basename(fastq))
        os.link(fastq, linked)
        return linked        

def trim_adapter_pe(fastq1, fastq2, adapter1, adapter2, adapter_for_all,
        cutadapt_param, out_dir):
    if adapter1 and adapter2:
        prefix1 = os.path.join(out_dir,
            os.path.basename(strip_ext_fastq(fastq1)))
        prefix2 = os.path.join(out_dir,
            os.path.basename(strip_ext_fastq(fastq2)))
        trimmed1 = '{}.trim.fastq.gz'.format(prefix1)
        trimmed2 = '{}.trim.fastq.gz'.format(prefix2)

        cmd = 'cutadapt {} -a {} -A {} {} {} -o {} -p {}'.format(
            cutadapt_param,
            adapter_for_all if adapter_for_all else adapter1,
            adapter_for_all if adapter_for_all else adapter2,
            fastq1, fastq2,
            trimmed1, trimmed2)
        run_shell_cmd(cmd)
        return [trimmed1, trimmed2]
    else:
        # make hard link
        linked1 = os.path.join(out_dir,
            os.path.basename(fastq1))
        linked2 = os.path.join(out_dir,
            os.path.basename(fastq2))
        os.link(fastq1, linked1)
        os.link(fastq2, linked2)
        return [linked1, linked2]

# make merged fastqs on $out_dir/R1, $out_dir/R2
def merge_fastqs(fastqs, end, out_dir):
    out_dir = os.path.join(out_dir, end)
    mkdir_p(out_dir)
    prefix = os.path.join(out_dir,
        os.path.basename(strip_ext_fastq(fastqs[0])))
    merged = '{}.merged.fastq.gz'.format(prefix)

    if len(fastqs)>1:
        cmd = 'cat {} > {}'.format(
            ' '.join(fastqs),
            merged)
        run_shell_cmd(cmd)
        return merged
    else:
        return hard_link(fastqs[0], merged)

def main():
    # read params
    args = parse_arguments()

    log.info('Initializing and making output directory...')
    mkdir_p(args.out_dir)

    # declare temp arrays
    temp_files = [] # files to deleted later at the end

    log.info('Initializing multi-threading...')
    if args.paired_end:
        num_process = min(2*len(args.fastqs),args.nth)
    else:
        num_process = min(len(args.fastqs),args.nth)
    log.info('Number of threads={}.'.format(num_process))
    pool = multiprocessing.Pool(num_process)

    log.info('Detecting adapters...')
    ret_vals = []
    for i in range(len(args.fastqs)):
        # for each fastq to be merged later
        log.info('Detecting adapters for merge_id={}...'.format(
                i+1))
        fastqs = args.fastqs[i] # R1 and R2
        adapters = args.adapters[i]
        if args.paired_end:
            if not args.adapter and args.auto_detect_adapter and \
                not (adapters[0] and adapters[1]):                
                ret_val1 = pool.apply_async(
                    detect_most_likely_adapter,(fastqs[0],))
                ret_val2 = pool.apply_async(
                    detect_most_likely_adapter,(fastqs[1],))
                ret_vals.append([ret_val1,ret_val2])
        else:
            if not args.adapter and args.auto_detect_adapter and \
                not adapters[0]:
                ret_val1 = pool.apply_async(
                    detect_most_likely_adapter,(fastqs[0],))
                ret_vals.append([ret_val1])

    # update array with detected adapters
    for i, ret_vals_ in enumerate(ret_vals):
        for j, ret_val in enumerate(ret_vals_):
            args.adapters[i][j] = str(ret_val.get(BIG_INT))
            log.info('Detected adapters for merge_id={}, R{}: {}'.format(
                    i+1, j+1, args.adapters[i][j]))

    log.info('Trimming adapters...')
    ret_vals = []
    for i in range(len(args.fastqs)):
        # for each fastq to be merged later
        fastqs = args.fastqs[i] # R1 and R2
        adapters = args.adapters[i]
        if args.paired_end:
            ret_val = pool.apply_async(
                trim_adapter_pe,(
                    fastqs[0], fastqs[1], 
                    adapters[0], adapters[1],
                    args.adapter,
                    args.cutadapt_param,
                    args.out_dir))
        else:
            ret_val = pool.apply_async(
                trim_adapter_se,(
                    fastqs[0],
                    adapters[0],
                    args.adapter,
                    args.cutadapt_param,
                    args.out_dir))
        ret_vals.append(ret_val)

    # update array with trimmed fastqs
    trimmed_fastqs_R1 = []
    trimmed_fastqs_R2 = []
    for i, ret_val in enumerate(ret_vals):
        if args.paired_end:
            fastqs = ret_val.get(BIG_INT)
            trimmed_fastqs_R1.append(fastqs[0])
            trimmed_fastqs_R2.append(fastqs[1])
        else:
            fastq = ret_val.get(BIG_INT)
            trimmed_fastqs_R1.append(fastq)

    log.info('Merging fastqs...')
    log.info('R1 to be merged: {}'.format(trimmed_fastqs_R1))
    ret_val1 = pool.apply_async(merge_fastqs,
                    (trimmed_fastqs_R1, 'R1', args.out_dir,))
    if args.paired_end:
        log.info('R2 to be merged: {}'.format(trimmed_fastqs_R2))
        ret_val2 = pool.apply_async(merge_fastqs,
                        (trimmed_fastqs_R2, 'R2', args.out_dir,))
    # gather
    R1_merged = ret_val1.get(BIG_INT)
    if args.paired_end:
        R2_merged = ret_val2.get(BIG_INT)

    temp_files.extend(trimmed_fastqs_R1)
    temp_files.extend(trimmed_fastqs_R2)

    log.info('Closing multi-threading...')
    pool.close()
    pool.join()

    log.info('Removing temporary files...')
    rm_f(temp_files)

    log.info('List all files in output directory...')
    ls_l(args.out_dir)

    log.info('All done.')

if __name__=='__main__':
    main()