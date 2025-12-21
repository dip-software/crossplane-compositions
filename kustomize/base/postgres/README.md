# Postgres Crossplane Composition

This Crossplane v2 composition provides a complete solution for **PostgreSQL** databases, supporting both **AWS RDS** (with IAM Roles for Service Accounts) and **CloudNativePG** on Kubernetes. It abstracts the underlying provider details, allowing for seamless switching between cloud-managed and Kubernetes-native databases.

## Features

- ✅ **Namespace-scoped** composite resources (no claims required)
- ✅ **Multi-Provider Support**: Switch between `aws` and `cnpg` backends
- ✅ **T-Shirt Sizing**: Simple `small`, `medium`, `large` abstraction
- ✅ **Create new AWS RDS/Aurora** instances with full configuration
- ✅ **Deploy CloudNativePG Clusters** on Kubernetes
- ✅ **Use existing RDS instances** or **Aurora clusters** (observe-only mode)
- ✅ **Multi-AZ deployment** support (AWS Multi-AZ / CNPG Replicas)
- ✅ **Automatic backups** with configurable retention
- ✅ **Encryption at rest** enforced by default
- ✅ **Connection secret output** with endpoint, port, and username
- ✅ **Resource tagging** support

## Usage Modes

The composition supports two modes determined by which identifier field you use:

### Mode 1: **Use Existing Database** (specify `existingIdentifier`)
- Observes existing RDS instance or Aurora cluster
- Creates connection secret with provided credentials
- Ideal for production databases managed outside Crossplane

### Mode 2: **Create New Database** (specify `identifier`)
- Provisions new RDS instance or Aurora cluster
- Creates DB subnet group and manages networking
- Ideal for development, testing, or new applications

## Architecture

### For Existing Databases (with `existingIdentifier`):

**Observed Resources (Read-Only):**
1. **RDS Instance** or **Aurora Cluster** - Existing database (metadata retrieval only)

### For New Databases (with `identifier`):

**Created and Managed Resources:**
1. **RDS Subnet Group** - Defines subnets for the database
2. **RDS Instance** or **Aurora Cluster** - New PostgreSQL database


## Prerequisites

### 1. Crossplane Providers and Functions

The composition requires the following Crossplane providers and functions:

- `function-environment-configs` v0.4.0
- `function-go-templating` v0.11.0
- `function-patch-and-transform` v0.9.1
- `function-auto-ready` v0.5.1
- `provider-aws-rds` v2.2.0

Install these using:

```bash
kubectl apply -f functions.yaml
```

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

### 3. RDS Database Setup

Your RDS instance or Aurora cluster must have:
- Database accessible from your EKS cluster
- Security groups configured to allow connections


## Usage Examples

### Example 1: Basic RDS Instance Access

```yaml
apiVersion: dip.io/v1alpha1
kind: Postgres
metadata:
  name: myapp-db-access
  namespace: myapp
spec:
  database:
    existingIdentifier: myapp-production-db
    type: rds-instance
    engine: postgres
    databaseName: application

  tags:
    Application: myapp
    Environment: production
```

### Example 2: Aurora PostgreSQL Cluster

```yaml
apiVersion: dip.io/v1alpha1
kind: Postgres
metadata:
  name: myapp-aurora-access
  namespace: myapp
spec:
  database:
    existingIdentifier: myapp-aurora-cluster
    type: aurora-cluster
    engine: postgres
    databaseName: application

  

```

### Example 3: With Connection Secret

```yaml
apiVersion: dip.io/v1alpha1
kind: Postgres
metadata:
  name: myapp-db-with-secret
  namespace: myapp
spec:
  database:
    existingIdentifier: myapp-production-db
    type: rds-instance

    resourceId: db-ABCDEFGHIJKLMNOP123456  # Optional: provide if known
  
  writeConnectionSecretToRef:
    name: myapp-db-credentials
  

```

### Connection Secret Schema

Both `aws` and `cnpg` providers verify and populate the same connection secret schema, ensuring application portability.

| Key | Description | Example |
|-----|-------------|---------|
| `host` | Database hostname | `myapp-db.cluster-ro.abcdef.us-east-1.rds.amazonaws.com` |
| `port` | Database port | `5432` |
| `username` | Connection username | `postgres` or `app_user` |
| `password` | Connection password | `secure_random_string` |
| `database` | Database name | `app` |
| `sslmode` | SSL connection mode | `require` |
| `endpoint` | Hostname + Port | `myapp-db...:5432` |

### Example 4: Unified Application Deployment

Since the secret structure is identical for both providers, you can use the same application manifest for both.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: myapp
spec:
  containers:
  - name: app
    image: my-app:latest
    env:
    - name: PGHOST
      valueFrom:
        secretKeyRef:
          name: myapp-db-connection
          key: host
    - name: PGPORT
      valueFrom:
        secretKeyRef:
          name: myapp-db-connection
          key: port
    - name: PGUSER
      valueFrom:
        secretKeyRef:
          name: myapp-db-connection
          key: username
    - name: PGPASSWORD
      valueFrom:
        secretKeyRef:
          name: myapp-db-connection
          key: password
    - name: PGDATABASE
      valueFrom:
        secretKeyRef:
          name: myapp-db-connection
          key: database
    - name: PGSSLMODE
      valueFrom:
        secretKeyRef:
          name: myapp-db-connection
          key: sslmode
```

### Example 5: Read-Only Access

```yaml
apiVersion: dip.io/v1alpha1
kind: Postgres
metadata:
  name: analytics-readonly-db
  namespace: analytics
spec:
  database:
    existingIdentifier: production-main-db
    type: rds-instance

  

```

## Creating New Databases

The composition can provision new RDS PostgreSQL instances or Aurora clusters by specifying the `identifier` field (without `existingIdentifier`).

### Prerequisites for Create Mode

Before creating a new database, you need:

1. **Environment Configuration**: An `EnvironmentConfig` resource with VPC and security group details (automatically provided by the platform)
2. **Master Password Secret**: A Kubernetes secret containing the master password

The composition automatically extracts VPC configuration from the `EnvironmentConfig`:
- Database subnet IDs from `servicesVpc.subnetGroups.database.subnet_ids`
- Database security group from `servicesVpc.securityGroups.database.id`

#### Create Master Password Secret

```bash
# Create a strong password
kubectl create secret generic myapp-db-master-password \
  --from-literal=password='YourSecurePassword123!' \
  --namespace=myapp

# Or use a file
echo -n 'YourSecurePassword123!' > password.txt
kubectl create secret generic myapp-db-master-password \
  --from-file=password=password.txt \
  --namespace=myapp
rm password.txt
```

**IMPORTANT**: In production, use secure secret management:
- AWS Secrets Manager with External Secrets Operator
- HashiCorp Vault
- Sealed Secrets
- SOPS (Secrets OPerationS)

### Example 6: Create Development Database

```yaml
apiVersion: dip.io/v1alpha1
kind: Postgres
metadata:
  name: myapp-dev-db
  namespace: myapp
spec:
  database:
    identifier: myapp-development-db
    engineVersion: "18.1"
    databaseName: myapp_dev
    
    # Instance configuration
    size: small
    allocatedStorage: 20
    storageType: gp3
    
    # Master credentials
    masterUsername: postgres
    masterPasswordSecretRef:
      name: myapp-db-master-password
      key: password
    
    # Backup and HA
    backupRetentionPeriod: 7
    multiAz: false

  

  
  tags:
    Environment: development
    Team: platform
```

### Example 7: Create Production Database

```yaml
apiVersion: dip.io/v1alpha1
kind: Postgres
metadata:
  name: myapp-prod-db
  namespace: myapp
spec:
  database:
    identifier: myapp-prod-db
    type: rds-instance
    engine: postgres
    engineVersion: "18.1"
    databaseName: myapp_production
    
    # Production instance
    provider: aws
    size: large
    allocatedStorage: 100
    storageType: gp3
    
    # Master credentials
    masterUsername: postgres
    masterPasswordSecretRef:
      name: myapp-prod-db-master-password
    
    # Production settings
    backupRetentionPeriod: 30
    multiAz: true

  
  writeConnectionSecretToRef:
    name: myapp-prod-db-connection
  

  
  tags:
    Environment: production
    CostCenter: engineering
```

### Example 8: Create Aurora PostgreSQL Cluster

```yaml
apiVersion: dip.io/v1alpha1
kind: Postgres
metadata:
  name: myapp-aurora
  namespace: myapp
spec:
  database:
    identifier: myapp-aurora-prod
    type: aurora-cluster
    engine: postgres
    engineVersion: "18.1"
    databaseName: myapp_data

    
    # Master credentials
    masterUsername: postgres
    masterPasswordSecretRef:
      name: myapp-aurora-master-password
    
    # Backup settings
    backupRetentionPeriod: 14
  
  writeConnectionSecretToRef:
    name: myapp-aurora-connection
  

```

### Create Mode Configuration Options

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `identifier` | No** | - | Name for new database (use this to create) |
| `existingIdentifier` | No** | - | Existing database name (use this to observe) |
| `provider` | No | `aws` | Backend provider: `aws` or `cnpg` |
| `size` | No | `small` | T-shirt size: `small`, `medium`, `large` |
| `engineVersion` | Yes* | - | PostgreSQL engine version (e.g., '18.1', '16.1') |
| `allocatedStorage` | Yes* | - | Storage in GB (minimum 20) |
| `storageType` | No | `gp3` | Storage type: gp2, gp3, io1 |
| `masterUsername` | Yes* | - | Master database username |
| `masterPasswordSecretRef` | Yes* | - | Reference to password secret |
| `backupRetentionPeriod` | No | `7` | Backup retention days (0-35) |
| `multiAz` | No | `false` | Enable Multi-AZ deployment |


*Required only when creating a new database (using `identifier`)  
**Either `identifier` or `existingIdentifier` must be provided (not both)

**Note:** VPC configuration (subnets and security groups) is automatically extracted from the `environmentConfig` resource. The composition uses the database subnet group and database security group defined in the environment configuration.

## Connecting to the Database

### Using Golang (pgx)

#### Standard Connection (Unified)
If you rely on the connection secret (as shown in the [Unified Application Deployment](#example-4-unified-application-deployment) example), `pgx` will automatically use the standard environment variables (`PGHOST`, `PGUSER`, `PGPASSWORD`, etc.).

```go
package main

import (
	"context"
	"fmt"
	"os"

	"github.com/jackc/pgx/v5"
)

func main() {
    // Connect using environment variables (PGHOST, PGUSER, PGPASSWORD, etc.)
    conn, err := pgx.Connect(context.Background(), "") // Empty string = use env vars
    if err != nil {
        fmt.Fprintf(os.Stderr, "Unable to connect to database: %v\n", err)
        os.Exit(1)
    }
    defer conn.Close(context.Background())

    var version string
    err = conn.QueryRow(context.Background(), "SELECT version()").Scan(&version)
    if err != nil {
        fmt.Fprintf(os.Stderr, "QueryRow failed: %v\n", err)
        os.Exit(1)
    }

    fmt.Println(version)
}
```

### Status Fields

After creating a Postgres resource, you can check its status:

```bash
kubectl get postgres myapp-db-access -n myapp -o yaml
```

Status fields include:
- `dbInstanceIdentifier`: RDS instance or Aurora cluster identifier
- `dbResourceId`: RDS resource ID
The connection secret will contain:
- `endpoint`: Database endpoint hostname
- `port`: Database port
- `database`: Database name
- `username`: Database username
- `password`: Database password

## Troubleshooting

### Connection Refused

**Problem**: Can't connect to the database

**Solutions**:
1. Check security groups allow traffic from EKS nodes
2. Verify database is in same VPC or has proper networking
3. Check RDS instance status: `aws rds describe-db-instances --db-instance-identifier <name>`

## Testing

Run tests using the Makefile:

```bash
# Run all tests (validate + render)
make test

# Validate XRD and composition
make validate

# Render all examples
make render

# Clean up test artifacts
make clean
```

## Advanced Configuration

### Explicit Resource ID

If you know the RDS resource ID, provide it to avoid lookup:

```yaml
spec:
  database:
    identifier: myapp-db
    resourceId: db-ABCDEFGHIJKLMNOP123456  # Get from AWS console or CLI
```

To find resource ID:
```bash
aws rds describe-db-instances --db-instance-identifier myapp-db \
  --query 'DBInstances[0].DbiResourceId' --output text
```

### Custom Provider Config

Use a different Crossplane provider config:

```yaml
spec:
  providerConfigRef:
    name: custom-aws-config
    kind: ProviderConfig
```

## Security Best Practices

### For All Databases

1. **Least Privilege**: Create database users with only necessary permissions
2. **Read-Only Users**: Use separate IAM users for read-only access
3. **Network Security**: Use security groups to restrict database access
4. **SSL/TLS**: Always use `sslmode=require` in connections
5. **Token Rotation**: Generate fresh tokens for each connection
6. **Audit Logging**: Enable RDS audit logging for compliance
7. **Resource Tags**: Use tags for cost tracking and access control

### For Created Databases (using `identifier`)

8. **Strong Master Passwords**: Use long, random passwords stored securely
9. **Secret Management**: Never commit secrets to Git; use secret managers
10. **Private Subnets**: Place databases in private subnets (not publicly accessible)
11. **Multi-AZ**: Enable Multi-AZ for production databases
12. **Backup Retention**: Set appropriate backup retention (30 days for production)
13. **Encryption**: Keep `storageEncrypted: true` (default)
14. **Security Groups**: Restrict ingress to only necessary CIDR blocks
15. **Instance Sizing**: Choose appropriate instance class for workload