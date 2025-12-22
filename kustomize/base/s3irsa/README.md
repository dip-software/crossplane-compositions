# S3IRSA Crossplane Composition

This Crossplane v2 composition provides a complete solution for setting up **AWS S3 access with IAM Roles for Service Accounts (IRSA)** in Kubernetes. It creates or configures S3 buckets with proper IRSA setup, allowing pods to securely access S3 using Kubernetes ServiceAccounts.

## Features

- ✅ **Namespace-scoped** composite resources (no claims required)
- ✅ **Create new S3 bucket** or **use existing bucket**
- ✅ **IRSA setup** with automatic IAM role and policy creation
- ✅ **Kubernetes ServiceAccount** created with proper annotations
- ✅ **Configurable permissions** (read/write with granular control)
- ✅ **Efficient KMS encryption**:
  - Uses AWS managed key (aws/s3) by default for cost efficiency
  - Optional custom KMS key support for specific compliance requirements
- ✅ **S3 bucket versioning** (optional)
- ✅ **Public access blocking** (automatically enabled)
- ✅ **Resource tagging** support

## Architecture

The composition creates/configures the following resources:

### When creating a new bucket:
1. **S3 Bucket** - With configurable name, versioning, and encryption
2. **S3 Bucket Encryption** - Uses AES256 (AWS managed key) or custom KMS key
3. **S3 Bucket Public Access Block** - Blocks all public access
4. **S3 Bucket Versioning** - Optional versioning support

### Always created:
5. **IAM Role** - With IRSA trust policy for the specified ServiceAccount
6. **IAM Policy** - With granular S3 and KMS permissions
7. **IAM Role Policy Attachment** - Links the policy to the role

**Note:** The Kubernetes ServiceAccount must be created and managed separately. The IAM role ARN can be retrieved from the S3IRSA status and used to annotate your ServiceAccount.

## Prerequisites

The composition requires the following Crossplane providers and functions:

- `function-environment-configs` v0.2.0
- `function-go-templating` v0.7.0
- `function-auto-ready` v0.3.0
- `provider-aws-s3` v2.2.0
- `provider-aws-iam` v2.2.0

Install these using:

```bash
kubectl apply -f functions.yaml
```

## Environment Configuration

The composition expects an `EnvironmentConfig` with the following fields:

```yaml
apiVersion: apiextensions.crossplane.io/v1alpha1
kind: EnvironmentConfig
metadata:
  name: custom-config
  labels:
    config: dip-software
data:
  awsAccountId: "123456789012"
  awsRegion: "us-east-1"
  eksClusterName: "my-cluster"
  eksOidcProvider: "oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
  eksOidcProviderArn: "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
```

## Usage Examples

### Example 1: Create a New S3 Bucket with Default Encryption

```yaml
apiVersion: dip.io/v1alpha1
kind: S3IRSA
metadata:
  name: my-app-storage
  namespace: my-app
spec:
  serviceAccountName: my-app-sa
  parameters:
    name: my-app-data-bucket
    versioning: true
    encryption:
      enabled: true  # Uses AWS managed key (aws/s3) for efficiency
  permissions:
    allowRead: true
    allowWrite: true
  tags:
    Application: my-app
    Environment: production
```

### Example 2: Use an Existing S3 Bucket

```yaml
apiVersion: dip.io/v1alpha1
kind: S3IRSA
metadata:
  name: my-app-existing-storage
  namespace: my-app
spec:
  serviceAccountName: my-app-sa
  existingBucketName: existing-company-bucket
  permissions:
    allowRead: true
    allowWrite: true
```

### Example 3: Custom KMS Encryption (for compliance requirements)

```yaml
apiVersion: dip.io/v1alpha1
kind: S3IRSA
metadata:
  name: backup-storage
  namespace: backup-system
spec:
  serviceAccountName: backup-writer-sa
  parameters:
    name: backup-archives-encrypted
    versioning: true
    encryption:
      enabled: true
      existingKmsKeyId: "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
  permissions:
    allowRead: false
    allowWrite: true
    additionalActions:
      - "s3:ListBucketVersions"
  tags:
    Compliance: required
    DataClassification: sensitive
```

### Example 4: Read-Only Access

```yaml
apiVersion: dip.io/v1alpha1
kind: S3IRSA
metadata:
  name: data-reader
  namespace: analytics
spec:
  serviceAccountName: analytics-reader-sa
  existingBucketName: analytics-data-lake
  permissions:
    allowRead: true
    allowWrite: false
```

## Creating and Using the ServiceAccount

After creating the S3IRSA resource, you need to create a ServiceAccount with the IAM role annotation. First, get the role ARN from the S3IRSA status:

```bash
kubectl get s3irsa my-app-storage -n my-app -o jsonpath='{.status.roleArn}'
```

Then create the ServiceAccount with the annotation:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-app-sa
  namespace: my-app
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/crossplane-system-my-app-storage-irsa-role
```

Use the ServiceAccount in your pod specification:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
  namespace: my-app
spec:
  serviceAccountName: my-app-sa
  containers:
  - name: app
    image: my-app:latest
    env:
    - name: AWS_REGION
      value: us-east-1
    - name: S3_BUCKET
      value: my-app-data-bucket
```

The AWS SDK will automatically use the IRSA credentials from the ServiceAccount.

## Parameters Reference

### Required Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `serviceAccountName` | string | Name of the Kubernetes ServiceAccount to create and bind with IAM role |

### Optional Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `existingBucketName` | string | - | Name of existing S3 bucket (if not provided, new bucket is created) |
| `parameters.name` | string | auto-generated | S3 bucket name (only for new buckets) |
| `parameters.versioning` | boolean | false | Enable S3 bucket versioning |
| `parameters.encryption.enabled` | boolean | true | Enable bucket encryption |
| `parameters.encryption.existingKmsKeyId` | string | - | Custom KMS key ARN (uses AWS managed key if not specified) |
| `permissions.allowRead` | boolean | true | Allow read operations (GetObject, ListBucket) |
| `permissions.allowWrite` | boolean | true | Allow write operations (PutObject, DeleteObject) |
| `permissions.additionalActions` | array | [] | Additional S3 actions to grant |
| `tags` | object | {} | Tags to apply to AWS resources |

## Status Fields

The composition populates the following status fields:

| Field | Description |
|-------|-------------|
| `bucketName` | Name of the S3 bucket (created or existing) |
| `bucketArn` | ARN of the S3 bucket |
| `roleArn` | ARN of the IAM role created for IRSA |

## KMS Encryption Strategy

The composition uses an efficient KMS encryption approach:

- **Default**: Uses AWS managed key (`aws/s3`) - No additional cost, automatic key rotation
- **Custom KMS**: Specify `existingKmsKeyId` when you need:
  - Specific compliance requirements
  - Custom key policies
  - Cross-account access
  - Audit trail requirements

**Cost Consideration**: AWS managed keys are free, while customer managed KMS keys cost $1/month + API call charges.

## Testing

Run the composition tests:

```bash
# Test all examples
make test

# Just validate the composition
make validate

# Render examples without validation
make render
```

## Troubleshooting

### ServiceAccount not getting IAM role annotation

1. Check that the `provider-kubernetes` is installed and configured
2. Verify the ProviderConfig named "default" exists
3. Check the Object resource status

### Pods cannot assume the IAM role

1. Verify the OIDC provider ARN and URL are correct in the EnvironmentConfig
2. Check that the ServiceAccount namespace matches the trust policy
3. Ensure the EKS cluster has IRSA enabled

### Bucket creation fails

1. Verify the bucket name is globally unique and follows S3 naming rules
2. Check AWS provider credentials and permissions
3. Ensure the region in EnvironmentConfig matches your deployment

## Security Considerations

- Public access to buckets is automatically blocked
- IAM policies follow the principle of least privilege
- ServiceAccount is scoped to a specific namespace
- KMS encryption is enabled by default
- IRSA provides temporary credentials (no long-lived access keys)

## Contributing

To add new features or modify the composition:

1. Update the XRD in `s3irsa-xrd.yaml`
2. Modify the composition logic in `s3irsa-composition.yaml`
3. Add test examples in `examples/`
4. Run `make test` to validate changes
5. Update this README with new parameters or features
