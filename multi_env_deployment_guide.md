# GitOps Guide: Multi-Environment Deployments with Argo CD

This document provides a comprehensive guide to implementing a robust, multi-environment deployment workflow (`dev`, `staging`, `prod`) using GitOps principles with Argo CD and Kustomize.

## 1. The Core Philosophy: Git as the Source of Truth

The goal is to stop deploying applications by manually running `kubectl` commands. Instead, we will define the complete desired state of every environment in a Git repository. A controller (Argo CD) will then ensure the live state of our cluster always matches what is defined in Git. This creates an automated, auditable, and repeatable process.

---

## 2. Required Components

You need five key components to build this workflow:

1.  **Application Repository:** Your application's source code (e.g., your `springboot-backend` project). Its CI pipeline is responsible for building and testing a Docker image.
2.  **GitOps Config Repository:** A **new, separate repository** that contains only the Kubernetes YAML manifests. This is the single source of truth for your cluster's state, and it is the **only repository that Argo CD watches**.
3.  **Container Registry:** A service like Docker Hub, Google Container Registry (GCR), or GitHub Container Registry (ghcr.io) to store your versioned Docker images.
4.  **Kubernetes Cluster:** A single cluster where your environments will be deployed, isolated by **namespaces** (e.g., `dev`, `staging`, `prod`).
5.  **Argo CD:** The GitOps controller. You only need **one Argo CD server** running in your cluster (typically in its own `argocd` namespace). It acts as a central control plane for all environments.

---

## 3. Implementation Strategy: The `base` and `overlays` Pattern

The most effective way to manage environments without duplicating code is to use Kustomize. We structure our **GitOps Config Repo** as follows:

```
gitops-config-repo/
└── apps/
    └── my-springboot-app/
        ├── base/
        │   ├── deployment.yaml      # Generic deployment template
        │   ├── service.yaml         # Generic service template
        │   └── kustomization.yaml   # Declares the base resources
        │
        └── overlays/
            ├── dev/
            │   ├── config.yaml          # Dev-specific ConfigMap (e.g., DB URL)
            │   └── kustomization.yaml   # Sets the dev image tag
            │
            ├── staging/
            │   ├── config.yaml          # Staging-specific ConfigMap
            │   └── kustomization.yaml   # Sets the staging image tag
            │
            └── prod/
                ├── config.yaml          # Prod-specific ConfigMap
                └── kustomization.yaml   # Sets the prod image tag & replica count
```

#### `base/deployment.yaml` (Example)
This is a generic template. Note the placeholder image tag.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-springboot-app
spec:
  replicas: 1 # A default value
  selector:
    matchLabels:
      app: my-springboot-app
  template:
    metadata:
      labels:
        app: my-springboot-app
    spec:
      containers:
      - name: app
        image: ghcr.io/your-org/my-springboot-app:latest # Placeholder
        ports:
        - containerPort: 8080
```

#### `overlays/prod/kustomization.yaml` (Example)
This file inherits the `base` and applies production-specific changes.

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# 1. Inherit from the base
bases:
  - ../../base

# 2. Specify the exact image version for this environment
images:
  - name: ghcr.io/your-org/my-springboot-app
    newTag: "v1.2.0" # Stable production tag

# 3. Include environment-specific resources
resources:
  - config.yaml

# 4. Patch the base manifests for production needs
patches:
- target:
    kind: Deployment
    name: my-springboot-app
  patch: |-
    - op: replace
      path: /spec/replicas
      value: 5 # Scale up for production
```
The **image version for each environment is explicitly hardcoded** in its `kustomization.yaml` file.

---

## 4. Configuring Argo CD: The "App of Apps" Pattern

You configure your single Argo CD server by creating one `Application` resource for each environment. Each `Application` points to a different overlay path in your GitOps repo.

```yaml
# argo-applications.yaml

apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app-dev
  namespace: argocd
spec:
  project: default
  source:
    repoURL: 'https://github.com/your-org/gitops-config-repo.git'
    targetRevision: main # Track the latest commit for dev
    path: apps/my-springboot-app/overlays/dev # <-- Path to DEV overlay
  destination:
    server: 'https://kubernetes.default.svc' # The local cluster
    namespace: dev # <-- Deploy to the 'dev' namespace
  syncPolicy:
    automated: { prune: true, selfHeal: true }
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app-prod
  namespace: argocd
spec:
  project: default
  source:
    repoURL: 'https://github.com/your-org/gitops-config-repo.git'
    targetRevision: main # Or a specific Git tag for prod releases
    path: apps/my-springboot-app/overlays/prod # <-- Path to PROD overlay
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: prod # <-- Deploy to the 'prod' namespace
  syncPolicy:
    # Production deployments are often set to manual sync for safety
    automated: {}
```
You apply this file to your cluster once. Argo CD will then create and manage these three applications.

---

## 5. The End-to-End Workflow

#### A. Automated Deployment to `dev`
1.  **Code Push:** A developer pushes code to the `springboot-backend` (Application Repo).
2.  **CI Pipeline:** A GitHub Action or other CI tool runs:
    *   It builds and tests the code.
    *   It builds a Docker image (e.g., `my-app:1.2.4-dev-def456`).
    *   It pushes the image to your container registry.
3.  **GitOps Update:** The **final step** of the CI pipeline is to automatically:
    *   Check out the **GitOps Config Repo**.
    *   Edit `overlays/dev/kustomization.yaml` to update the `newTag` to `1.2.4-dev-def456`.
    *   Commit and push this change.
4.  **Argo CD Sync:** Argo CD detects the commit, calculates the new desired state for `dev`, and deploys the new image to the `dev` namespace.

#### B. Controlled Promotion to `prod`
1.  **Create Pull Request:** To promote a stable version, a developer opens a **Pull Request** in the **GitOps Config Repo**.
2.  **Update Config:** This PR changes the `newTag` in `overlays/prod/kustomization.yaml` to a stable, tested version (e.g., `v1.2.0`).
3.  **Review and Merge:** The team reviews the PR. This PR is a record of what is being changed in production.
4.  **Argo CD Sync:** Once the PR is merged, Argo CD detects the change and deploys the new version to the `prod` namespace. This step can be automated or require a manual "Sync" click in the Argo CD UI for final approval.
