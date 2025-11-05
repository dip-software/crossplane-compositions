# Crossplane Compositions

This repository contains Crossplane v2 compositions for deploying applications via Argo CD. 

## Overview

The `HelmApplication` is a namespace-scoped Crossplane resource that creates an Argo CD `Application` resource to deploy Helm charts with dynamic configuration. 

### Features

- **Namespace Scoped**: The composition operates within specific namespaces, not cluster-wide
- **Helm Chart Deployment**: Deploys any Helm chart from a specified repository
- **Environment Configuration**: Integrates with Crossplane `EnvironmentConfig` to inject environment-specific values
- **Dynamic Values**: Supports flexible value injection through `helm.valuesObject` and `environmentConfig`
- **Crossplane v2**: Uses modern Crossplane v2 APIs without claim/composite separation

## Components

### 1. CompositeResourceDefinition (XRD) - `helmapp-xrd.yaml`

Defines the `HelmApplication` resource with the following inputs:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `chartName` | string | No | Name of the Helm chart (not needed for OCI registries) |
| `repoURL` | string | Yes | URL of the Helm chart repository (supports `https://` and `oci://`) |
| `targetRevision` | string | Yes | Chart version/revision to deploy |
| `path` | string | No | Optional path to the chart within the repository |
| `helm.valuesObject` | object | No | Helm chart values as key-value pairs |
| `withConfigKeys` | array | No | Optional array of string prefixes to filter which environmentConfigs to include |
| `project` | string | No | Argo CD project name (defaults to "default") |

### 2. Composition - `helmapp-composition.yaml`

Implements the XRD by creating an Argo CD `Application` resource. The composition:

- Maps all XRD inputs to the Argo CD Application spec
- References an `EnvironmentConfig` to inject environment-specific values
- Merges `helm.valuesObject` with `environmentConfig` in the Helm values
- Sets up automated sync policies for Argo CD
- Supports both traditional Helm repositories and OCI registries
- Conditionally sets `spec.chart` only for non-OCI repositories

### 3. Argo CD RBAC - `argocd-rbac.yaml`

Provides necessary RBAC permissions for Crossplane to manage Argo CD resources:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: argocd:aggregate-to-crossplane
  labels:
    rbac.crossplane.io/aggregate-to-crossplane: "true"
rules:
- apiGroups:
  - argoproj.io
  resources:
  - applications
  - applicationsets
  - appprojects
  verbs:
  - "*"
```

### 4. EnvironmentConfig

The composition references an `EnvironmentConfig` (e.g., `hsp-addons`) to inject environment-specific values. All fields from the EnvironmentConfig are automatically included in the `environmentConfig` section of the Helm values.

## Usage

### Deploy the Composition

```bash
kubectl apply -k kustomize/base/helmapp
```

This deploys:
- The XRD for `HelmApplication`
- The composition
- Argo CD RBAC permissions

### Create a HelmApplication Resource

Create a namespace-scoped resource to deploy an application.

**Example 1: Traditional Helm Repository**

```yaml
apiVersion: dip.io/v1alpha1
kind: HelmApplication
metadata:
  name: my-app
  namespace: default
spec:
  chartName: "myapp"
  repoURL: "https://charts.example.com"
  targetRevision: "1.0.0"
  project: "default"
  
  helm:
    valuesObject:
      replicas: 3
      image:
        tag: "latest"
```

**Example 2: OCI Registry (no chartName needed)**

```yaml
apiVersion: dip.io/v1alpha1
kind: HelmApplication
metadata:
  name: go-hello-world
  namespace: starlift-observability
spec:
  repoURL: "oci://ghcr.io/loafoe/helm-charts/go-hello-world"
  targetRevision: "0.12.0"
  project: "starlift-observability"
  
  helm:
    valuesObject:
      replicaCount: 2
      serviceType: "LoadBalancer"
```

### Verify the Argo CD Application

```bash
# List all HelmApplication resources
kubectl get helmapplication -A

# Describe a specific resource
kubectl describe helmapplication my-app -n default

# Check the created Argo CD Application
kubectl get applications -n <namespace>
```

## Architecture

```
HelmApplication (namespace-scoped)
    ↓
Composition (Pipeline Mode)
    ↓
  1. Load EnvironmentConfig
  2. Render Argo CD Application (Go Template)
  3. Auto-ready check
    ↓
Argo CD Application
    ↓
Helm Chart Deployment
```

## EnvironmentConfig Integration

The composition automatically merges environment-specific values:

```yaml
# Input helm.valuesObject
helm:
  valuesObject:
    replicas: 3
    image: myimage:1.0.0

# EnvironmentConfig data
resourcePrefix: "dip"

# Resulting Helm values (merged in Argo CD Application)
environmentConfig:
  resourcePrefix: "dip"
replicas: 3
image: myimage:1.0.0
```

## Repository Types Supported

### Traditional Helm Repositories

For standard Helm repositories (HTTP/HTTPS), specify both `repoURL` and `chartName`:

```yaml
spec:
  repoURL: "https://charts.example.com"
  chartName: "my-chart"
  targetRevision: "1.0.0"
  helm:
    valuesObject:
      key: value
```

### OCI Registries

For OCI registries, the chart reference is included in the `repoURL`. Do not specify `chartName`:

```yaml
spec:
  repoURL: "oci://ghcr.io/owner/charts/chart-name"
  targetRevision: "1.0.0"
  helm:
    valuesObject:
      key: value
```

## Group Reference

- **Group**: `dip.io`
- **Kind**: `HelmApplication`
- **Scope**: Namespaced
- **API Version**: `v1alpha1`

## Resources Created

When a `HelmApplication` resource is created, the composition automatically creates:

1. **Argo CD Application** (in the same namespace as the `HelmApplication`)
   - Syncs the Helm chart
   - Applies automated sync policies (prune, selfHeal)
   - Targets the cluster's Kubernetes service endpoint
   - Creates namespace if it doesn't exist

## Notes

- The Argo CD controller must be installed and running in the cluster
- Helm charts must be accessible from the specified `repoURL`
- Argo CD Applications are created in the same namespace as the `HelmApplication` resource
- EnvironmentConfig references are resolved by Crossplane at composition time
- The composition uses Crossplane Pipeline mode with function-go-templating
- For OCI registries, omit the `chartName` field as the chart is specified in the `repoURL`
