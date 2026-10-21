# Imajev on Kubernetes

This repository packages and deploys the upstream [Imajev](https://github.com/mohit67890/imajev) inference server on Kubernetes. It is configured for the PyTorch/CUDA backend and the `imajev-9b` model on one NVIDIA `mig-2g.35gb` slice.

The application image deliberately does **not** contain model weights. In an air-gapped deployment, a separate weights image carries the base model and adapter into the cluster. An init container copies those files to a persistent volume claim (PVC), and the inference container loads them from that PVC.

## Repository files

- `imajev.dockerfile` builds the Imajev inference-server image. It clones the upstream source at `IMAJEV_REF` and installs the serving dependencies; it does not download model weights.
- `imajev-weights.dockerfile` builds a separate image containing the Hugging Face model snapshot and Imajev adapter. Its download stage needs internet access; the final image is a small file carrier for use inside the cluster.
- `deployment.yaml` defines the 40 Gi PVC, the Deployment with its weights-copy init container, and an internal Kubernetes Service.

## Build the images

Build these images on a machine or CI runner that can reach GitHub, Hugging Face, and the required package sources. Push them to a registry that the Kubernetes nodes can access. In a fully disconnected environment, transfer the built images through your approved image-import process instead.

Build and push the application image:

```sh
docker build -f imajev.dockerfile \
	--build-arg IMAJEV_REF=main \
	-t registry.example.com/base/imajev:1.0.0 .
docker push registry.example.com/base/imajev:1.0.0
```

Build and push the weights image:

```sh
docker build -f imajev-weights.dockerfile \
	--build-arg REV=c202236235762e1c871ad0ccb60c8ee5ba337b9a \
	--build-arg ADAPTER_REV=main \
	-t registry.example.com/base/imajev-weights:9b-v1 .
docker push registry.example.com/base/imajev-weights:9b-v1
```

Replace the example registry and image tags with values for your environment. The commands use `main` for the upstream source and adapter to stay directly runnable; replace those with immutable commits for reproducible builds. `REV` selects the Qwen base-model revision. `ADAPTER_REV` selects the adapter revision and defaults to `main` if omitted, so that public branch can change. Pin `IMAJEV_REF` as well if you need a reproducible application image. If your build environment uses a TLS-inspecting corporate proxy, place its CA certificates as `.crt` files in the Docker build context.

## Deploy

The cluster must have the NVIDIA device plugin configured to advertise `nvidia.com/mig-2g.35gb`, a suitable default StorageClass (or an explicit one added to the PVC), and enough memory for the model load. The PVC requests 40 Gi; the pod requests 24 Gi and has a 40 Gi memory limit.

```sh
kubectl apply -f deployment.yaml
kubectl get pods,pvc,service -l app=imajev
kubectl logs deployment/imajev -c copy-weights
kubectl logs deployment/imajev -c imajev
```

The Service listens on port 80 and forwards to the server on port 8765. It is a cluster-internal Service; no Ingress or external authentication is configured here. The server's readiness endpoint is `/v1/models`.

## Weights lifecycle and updates

The weights image is the portable, versioned package for the model files. Build it while public sources are available, record the Hugging Face revisions used, push or transfer the image into the isolated environment, and keep that exact image available in the internal registry. Do not depend on downloading public weights when a pod starts.

On first startup, the init container copies the image contents into the PVC and creates `/models/.complete-9b`. Later pod starts skip the copy when that marker exists, so changing the weights image tag alone does **not** update an already-populated PVC. When changing the base model or adapter, build and deploy a new weights image and use a new or deliberately refreshed PVC; ensure the model bundle, adapter, calibration file, and server configuration are compatible. Preserve the existing PVC until the replacement has been validated, since it contains the current working model files.

The base-model snapshot is pinned by the default `REV` in `imajev-weights.dockerfile`; change it with `--build-arg REV=...` when selecting another public revision. The adapter comes from the public `mohit67890/imajev-9b` repository and is independently selected with `ADAPTER_REV`. Public repositories, their default branches, and availability can change, so record and pin both revisions for repeatable releases. Validate the new weights image before promoting it to the air-gapped cluster.

## Configuration notes

- The deployment overrides the image command to run `artifacts/model-qwen9b.json` with the `imajev-9b` adapter and calibration file.
- The weights image layout must continue to match the paths expected by the server: the Hugging Face cache under `/app/.cache` and adapter files under `/app/adapters`.
- The `Recreate` deployment strategy avoids two pods mounting the `ReadWriteOnce` PVC during a rollout.
- The default application image and weights image tags in the manifest are examples for the current registry; update both when publishing a new release.
