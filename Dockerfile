# Customized Docker based on official ENCODE DCC image specified by docker_image/Dockerfile

FROM quay.io/encode-dcc/atac-seq-pipeline:v1.4.2

# replace source file with updated version
RUN cd /software/atac-seq-pipeline/src && \
    wget https://raw.githubusercontent.com/mengxiao/atac-seq-pipeline/v1.4.2_adapted/src/encode_trim_adapter.py -O encode_trim_adapter.py