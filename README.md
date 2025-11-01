# Crossplane BootstrapApp Composition

This repository contains a Crossplane v2 composition called **BootstrapApp** that automates the deployment of Helm charts via Argo CD.

## Overview

The `BootstrapApp` is a namespace-scoped Crossplane resource that creates an Argo CD `Application` resource to deploy Helm charts with dynamic configuration. In Crossplane v2, there is no separate "claim" concept—`BootstrapApp` is used directly as a composite resource.

### Features

- **Namespace Scoped**: The composition operates within specific namespaces, not cluster-wide
- **Helm Chart Deployment**: Deploys any Helm chart from a specified repository
- **Environment Configuration**: Integrates with Crossplane `EnvironmentConfig` to inject environment-specific values
- **Dynamic Values**: Supports flexible value injection through `valuesObject` and `environmentConfig`
- **Crossplane v2**: Uses modern Crossplane v2 APIs without claim/composite separation

## Components

### 1. CompositeResourceDefinition (XRD) - `bootstrapapp-xrd.yaml`

Defines the `BootstrapApp` resource with the following inputs:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `chartName` | string | Yes | Name of the Helm chart (e.g., "nginx-ingress") |
| `repoURL` | string | Yes | URL of the Helm chart repository |
| `targetRevision` | string | Yes | Chart version/revision to deploy |
| `valuesObject` | object | No | Helm chart values as key-value pairs |
| `environment` | string | Yes | Reference to a Crossplane `EnvironmentConfig` |

### 2. Composition - `bootstrapapp-composition.yaml`

Implements the XRD by creating an Argo CD `Application` resource. The composition:

- Maps all XRD inputs to the Argo CD Application spec
- References an `EnvironmentConfig` to inject environment-specific values
- Merges `valuesObject` with `environmentConfig` in the Helm values
- Sets up automated sync policies for Argo CD

### 3. EnvironmentConfig Example - `environment-config-example.yaml`

Demonstrates how to define environment-specific configurations:

```yaml
data:
  resourcePrefix: "dip"
  environment: "production"
  clusterRegion: "eu-west-1"
```

The `resourcePrefix` field is automatically included in the `environmentConfig` section of the Helm values.

## Usage

### Deploy the Composition

```bash
kubectl apply -k kustomize/base
```

This deploys:
- The XRD for `BootstrapApp`
- The composition
- Example `EnvironmentConfig`

### Create a BootstrapApp Resource

Create a namespace-scoped resource to deploy an application:

```yaml
apiVersion: dip.io/v1alpha1
kind: BootstrapApp
metadata:
  name: my-app
  namespace: default
spec:
  chartName: "myapp"
  repoURL: "https://charts.example.com"
  targetRevision: "1.0.0"
  
  valuesObject:
    replicas: 3
    image:
      tag: "latest"
  
  environment: "env-config-example"
```

### Verify the Argo CD Application

```bash
# List all BootstrapApp resources
kubectl get bootstrapapp -A

# Describe a specific resource
kubectl describe bootstrapapp my-app -n default

# Check the created Argo CD Application
kubectl get applications -n argocd
```

## Architecture

```
BootstrapApp (namespace-scoped)
    ↓
Composition (creates)
    ↓
Argo CD Application
    ↓
Helm Chart Deployment
```

## EnvironmentConfig Integration

The composition automatically merges environment-specific values:

```yaml
# Input valuesObject
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

## Group Reference

- **Group**: `dip.io`
- **Kind**: `BootstrapApp`
- **Scope**: Namespaced

## Resources Created

When a `BootstrapApp` resource is created, the composition automatically creates:

1. **Argo CD Application** (in `argocd` namespace)
   - Syncs the Helm chart
   - Applies automated sync policies
   - Targets the cluster's Kubernetes service endpoint

## Notes

- The Argo CD controller must be installed and running in the cluster
- Helm charts must be accessible from the specified `repoURL`
- The `argocd` namespace must exist where Applications are created
- EnvironmentConfig references are resolved by Crossplane at composition time
