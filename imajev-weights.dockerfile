# Weights-only image for air-gapped clusters.
# Build it on a machine WITH internet access, push it to the internal registry.
# It is only used by the init container to fill the PVC once; the app image stays small.
#
#   docker build -f imajev-weights.dockerfile -t registry.enerjisa.com.tr/base/imajev-weights:9b-v3 .
#   docker push registry.enerjisa.com.tr/base/imajev-weights:9b-v3

# ---- stage 1: download (needs internet) ----
FROM python:3.11-slim AS download

# Corporate CAs, in case the build machine goes out through a TLS-inspecting proxy.
COPY *.crt /usr/local/share/ca-certificates/
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
 && update-ca-certificates && rm -rf /var/lib/apt/lists/*
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt \
    PIP_CERT=/etc/ssl/certs/ca-certificates.crt

RUN pip install --no-cache-dir "huggingface_hub[cli]>=0.34"

# Same layout the imajev server expects (relative to /app):
#   .cache/huggingface/hub/models--Qwen--Qwen3.5-9B/snapshots/<revision>/   (artifacts/model-qwen9b.json)
#   adapters/imajev-9b/
# --local-dir writes real files (no symlinks into blobs/), so the copy survives any PVC filesystem.
ENV HF_HOME=/tmp/hf
ARG REV=c202236235762e1c871ad0ccb60c8ee5ba337b9a
ARG ADAPTER_REV=main
ARG SNAP=/weights/cache/huggingface/hub/models--Qwen--Qwen3.5-9B/snapshots/${REV}
RUN hf download Qwen/Qwen3.5-9B --revision ${REV} --local-dir ${SNAP} \
 && hf download mohit67890/imajev-9b --revision ${ADAPTER_REV} --local-dir /weights/adapters/imajev-9b \
 && rm -rf ${SNAP}/.cache /weights/adapters/imajev-9b/.cache /tmp/hf \
 && test -f ${SNAP}/tokenizer.json && test -f ${SNAP}/config.json \
 && test -f /weights/adapters/imajev-9b/calibration.json \
 && ! find /weights -type l | grep -q . \
 && test $(du -sm ${SNAP} | cut -f1) -gt 15000 \
 && ls -la ${SNAP} && du -sh /weights/*

# ---- stage 2: tiny runtime with just the files + sh/cp ----
FROM busybox:1.36
COPY --from=download /weights /weights