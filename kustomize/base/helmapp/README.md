# HelmApplication Composition

This directory contains the Crossplane Composition for HelmApplication resources, which creates ArgoCD Applications for Helm chart deployments.

## Variable Substitution

The composition supports automatic variable substitution in the `spec.source.helm.valuesObject` section. Variables use the format `${variableName}` and are replaced with values from the EnvironmentConfig context.

### Supported Variables

The following variables are currently supported:

- `${resourcePrefix}` - Resource prefix (e.g., environment name)
- `${clusterFqdn}` - Cluster fully qualified domain name
- `${accountId}` - AWS Account ID
- `${region}` - AWS Region
- `${partition}` - AWS Partition (e.g., "aws", "aws-cn", "aws-us-gov")

### Expanding the Variable List

To add support for additional variables, simply update the `$supportedEnvVars` list at the top of the Go template in `helmapp-composition.yaml`:

```yaml
{{- $supportedEnvVars := list "resourcePrefix" "clusterFqdn" "accountId" "region" "partition" "newVariable" -}}
```

Make sure the corresponding variable exists in your EnvironmentConfig resources.

### Usage Examples

#### Simple Variable Substitution

```yaml
apiVersion: dip.io/v1alpha1
kind: HelmApplication
metadata:
  name: my-app
spec:
  source:
    repoURL: "oci://registry.example.com/charts/my-app"
    targetRevision: "1.0.0"
    helm:
      valuesObject:
        nameOverride: "${resourcePrefix}-my-app"
        ingress:
          host: "my-app.${clusterFqdn}"
```

With an EnvironmentConfig containing:

```yaml
data:
  resourcePrefix: "prod"
  clusterFqdn: "example.com"
```

This will be rendered as:

```yaml
nameOverride: "prod-my-app"
ingress:
  host: "my-app.example.com"
```

#### Combining Multiple Variables

```yaml
apiVersion: dip.io/v1alpha1
kind: HelmApplication
metadata:
  name: my-app
spec:
  source:
    helm:
      valuesObject:
        config:
          s3BucketName: "${resourcePrefix}-app-data-${accountId}"
          arnPrefix: "arn:${partition}:s3:::${resourcePrefix}-bucket"
```

#### Using Variables in Lists and Nested Objects

Variables work in:

- Simple string values
- Nested objects
- Lists/arrays of strings
- Environment variables

See `examples/variable-substitution-example.yaml` for a comprehensive example.

## How It Works

The composition uses Go templates to:

1. Define a list of supported variable names in `$supportedEnvVars`
2. Recursively process the `valuesObject` structure
3. Replace `${variableName}` patterns in all string values with corresponding values from the EnvironmentConfig context
4. Preserve non-string values (numbers, booleans, etc.) as-is

Variables are only replaced if they exist in the EnvironmentConfig. If a variable is not found, the `${variableName}` pattern remains unchanged.
