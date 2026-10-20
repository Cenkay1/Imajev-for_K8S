# imajev (torch / CUDA backend) — model weights are NOT baked in; they live on a PVC.
# Put your CA certificates (PEM format, .crt extension) in ./certs/ next to this Dockerfile.
FROM pytorch/pytorch:2.6.0-cuda12.4-cudnn9-runtime

# 1. Trust the corporate CAs first, so git clone, pip install and the HF downloads below all work behind the proxy.
COPY *.crt /usr/local/share/ca-certificates/
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates git \
 && update-ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Python tools bundle their own CA list (certifi) and ignore the system store unless told otherwise.
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt \
    CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt \
    PIP_CERT=/etc/ssl/certs/ca-certificates.crt

WORKDIR /app
ARG IMAJEV_REF=main
RUN git clone --depth 1 --branch ${IMAJEV_REF} https://github.com/mohit67890/imajev . \
 && pip install --no-cache-dir -e ".[serve,torch]"

ENV PYTHONPATH=/app/src:/app/scripts \
    PYTHONUNBUFFERED=1

EXPOSE 8765

# Default: serve imajev-4b. deployment.yaml overrides this for the 9B.
CMD ["python", "scripts/playground/server.py", \
     "--backend", "torch", \
     "--model-bundle", "artifacts/model-qwen9b.json", \
     "--adapter", "adapters/imajev-9b", \
     "--calibration", "adapters/imajev-9b/calibration.json", \
     "--rotations", "4", \
     "--model-name", "imajev-9b", \
     "--host", "0.0.0.0", "--port", "8765"]