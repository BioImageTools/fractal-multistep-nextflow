# Container for the fractal-tasks-core v2 tasks used by this pipeline.
#   docker build -t quay.io/bioinfotongli/fractal-tasks-core:2.1.0 containers/
FROM python:3.12-slim

ARG FRACTAL_TASKS_CORE_VERSION=2.1.0

# procps provides `ps`, which Nextflow uses to collect task metrics
RUN apt-get update && \
    apt-get install -y --no-install-recommends procps && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN pip install --no-cache-dir "fractal-tasks-core==${FRACTAL_TASKS_CORE_VERSION}"

# Avoid numba/matplotlib cache writes into read-only locations
ENV NUMBA_CACHE_DIR=/tmp MPLCONFIGDIR=/tmp
