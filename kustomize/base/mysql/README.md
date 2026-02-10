# MySQL Crossplane Composition

This Crossplane v2 composition provides a complete solution for **MySQL** databases on **AWS RDS** and **Aurora MySQL**. It abstracts the underlying provider details while keeping configuration simple and consistent across environments.

## Features

- ✅ **Namespace-scoped** composite resources (no claims required)
- ✅ **AWS RDS / Aurora MySQL** support
- ✅ **T-Shirt Sizing**: `small`, `medium`, `large`
- ✅ **Multi-AZ deployment** support
- ✅ **Automatic backups** with configurable retention
- ✅ **Encryption at rest** enforced by default
- ✅ **Connection secret output** with endpoint, port, username and password
- ✅ **Resource tagging** support

## Prerequisites

### 1. Crossplane Providers and Functions

The composition requires the following Crossplane providers and functions:

- `function-environment-configs` v0.4.0+
- `function-go-templating` v0.11.0+
- `function-patch-and-transform` v0.9.1+
- `function-auto-ready` v0.5.1+
- `provider-aws-rds` v2.2.0+

### 2. Environment Configuration

The composition expects an `EnvironmentConfig` with the following fields:

```yaml
apiVersion: apiextensions.crossplane.io/v1beta1
kind: EnvironmentConfig
metadata:
  name: hsp-addons
  labels:
    config: hsp-addons
data:
  accountId: "123456789012"
  region: "us-east-1"
  clusterName: "my-cluster"
  eks:
    oidcProvider: "oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
    oidcProviderArn: "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
```

## Connection Secret Schema

| Key | Description | Example |
|-----|-------------|---------|
| `host` | Database hostname | `myapp-db.abcdef.us-east-1.rds.amazonaws.com` |
| `port` | Database port | `3306` |
| `username` | Connection username | `admin` |
| `password` | Connection password | `secure_random_string` |
| `database` | Database name | `app` |
| `sslmode` | SSL connection mode | `require` |
| `endpoint` | Hostname + Port | `myapp-db...:3306` |

## Usage Examples

### Example 1: Create Development Database

```yaml
apiVersion: dip.io/v1alpha1
kind: MySQL
metadata:
  name: myapp-dev-db
  namespace: myapp
spec:
  parameters:
    identifier: myapp-development-db
    engineVersion: "8.4.7"
    databaseName: myapp_dev
    size: small
    allocatedStorage: 20
    storageType: gp3
    masterUsername: admin
    backupRetentionPeriod: 7
    multiAz: false
  tags:
    Environment: development
    Team: platform
```

### Example 2: Create Aurora MySQL Cluster

```yaml
apiVersion: dip.io/v1alpha1
kind: MySQL
metadata:
  name: myapp-aurora
  namespace: myapp
spec:
  parameters:
    identifier: myapp-aurora-prod
    type: aurora-cluster
    engineVersion: "8.0.mysql_aurora.3.10.3"
    databaseName: myapp_data
    masterUsername: admin
    backupRetentionPeriod: 14
  writeConnectionSecretToRef:
    name: myapp-aurora-connection
```

## Testing

Run tests using the Makefile:

```bash
# Run all tests (validate + render)
make test

# Validate XRD and composition
make validate

# Render all examples
make render
```
