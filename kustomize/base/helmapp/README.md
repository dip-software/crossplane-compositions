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
- `${oidcProvider}` - OIDC provider URL
- `${oidcProviderArn}` - OIDC provider ARN

### Expanding the Variable List

To add support for additional variables, simply update the `$supportedEnvVars` list at the top of the Go template in `helmapp-composition.yaml`:

```yaml
{{- $supportedEnvVars := list "resourcePrefix" "clusterFqdn" "accountId" "region" "partition" "oidcProvider" "oidcProviderArn" "newVariable" -}}
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

## Testing Variable Substitution

### Test Case: Nested Config Object

The `examples/test-nested-config.yaml` file provides a test case specifically for nested configuration objects with variable substitution:

```yaml
spec:
  source:
    helm:
      valuesObject:
        config:
          awsAccountId: ${accountId}
          awsRegion: ${region}
          clusterName: ${resourcePrefix}
```

This test case verifies that:

1. Nested objects (like `config`) are properly preserved in the output
2. Variable substitution works within nested structures
3. The `valuesObject` is not rendered as an empty object (`config: {}`)

### Bug Fix: Empty valuesObject Output

**Issue**: Prior to the fix, when using nested objects with variable substitution, the resulting manifest would show empty objects (e.g., `config: {}`).

**Root Cause**: The Go template was outputting `valuesObject:` before checking if there was content to output. The whitespace-stripping template directives (`{{-`) were preventing any content from being generated, resulting in an empty object.

**Fix**: The template structure was reorganized to:

1. Process the `valuesObject` and perform variable substitution first
2. Only output the `valuesObject:` key after processing is complete
3. Ensure the output directives preserve the actual content

This ensures that nested structures with variables are properly rendered in the final ArgoCD Application manifest.
