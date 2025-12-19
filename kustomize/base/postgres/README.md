# Postgres Crossplane Composition

This Crossplane v2 composition provides a complete solution for **PostgreSQL** databases, supporting both **AWS RDS** (with IAM Roles for Service Accounts) and **CloudNativePG** on Kubernetes. It abstracts the underlying provider details, allowing for seamless switching between cloud-managed and Kubernetes-native databases.

## Features

- ✅ **Namespace-scoped** composite resources (no claims required)
- ✅ **Multi-Provider Support**: Switch between `aws` and `cnpg` backends
- ✅ **T-Shirt Sizing**: Simple `small`, `medium`, `large` abstraction
- ✅ **Create new AWS RDS/Aurora** instances with full configuration
- ✅ **Deploy CloudNativePG Clusters** on Kubernetes
- ✅ **Use existing RDS instances** or **Aurora clusters** (observe-only mode)
- ✅ **IRSA setup** with automatic IAM role and policy creation (AWS)
- ✅ **IAM database authentication** for password-less connections (AWS)
- ✅ **Multi-AZ deployment** support (AWS Multi-AZ / CNPG Replicas)
- ✅ **Automatic backups** with configurable retention
- ✅ **Encryption at rest** enforced by default
- ✅ **Connection secret output** with endpoint, port, and username
- ✅ **Resource tagging** support

## Usage Modes

The composition supports two modes determined by which identifier field you use:

### Mode 1: **Use Existing Database** (specify `existingIdentifier`)
- Observes existing RDS instance or Aurora cluster
- Creates only IAM resources (role, policy)
- Database must have IAM authentication already enabled
- Ideal for production databases managed outside Crossplane

### Mode 2: **Create New Database** (specify `identifier`)
- Provisions new RDS instance or Aurora cluster
- Configures IAM authentication automatically
- Creates DB subnet group and manages networking
- Ideal for development, testing, or new applications

## Architecture

### For Existing Databases (with `existingIdentifier`):

**Observed Resources (Read-Only):**
1. **RDS Instance** or **Aurora Cluster** - Existing database (metadata retrieval only)

**Created Resources:**
2. **IAM Role** - With IRSA trust policy for the specified ServiceAccount
3. **IAM Policy** - With RDS IAM authentication permissions (`rds-db:connect`)
4. **IAM Role Policy Attachment** - Links the policy to the role

### For New Databases (with `identifier`):

**Created and Managed Resources:**
1. **RDS Subnet Group** - Defines subnets for the database
2. **RDS Instance** or **Aurora Cluster** - New PostgreSQL database with IAM auth enabled
3. **IAM Role** - With IRSA trust policy for the specified ServiceAccount
4. **IAM Policy** - With RDS IAM authentication permissions (`rds-db:connect`)
5. **IAM Role Policy Attachment** - Links the policy to the role

**Note:** The Kubernetes ServiceAccount and PostgreSQL database user must be created and managed separately. See [Setup Instructions](#setup-instructions) below.

## Prerequisites

### 1. Crossplane Providers and Functions

The composition requires the following Crossplane providers and functions:

- `function-environment-configs` v0.4.0
- `function-go-templating` v0.11.0
- `function-patch-and-transform` v0.9.1
- `function-auto-ready` v0.5.1
- `provider-aws-rds` v2.2.0
- `provider-aws-iam` v2.2.0

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
- **IAM authentication enabled** (see [Enable IAM Authentication](#enable-iam-authentication))
- Database accessible from your EKS cluster
- Security groups configured to allow connections

## Setup Instructions

### Enable IAM Authentication

#### For RDS Instance:
```bash
aws rds modify-db-instance \
  --db-instance-identifier myapp-production-db \
  --enable-iam-database-authentication \
  --apply-immediately
```

#### For Aurora Cluster:
```bash
aws rds modify-db-cluster \
  --db-cluster-identifier myapp-aurora-cluster \
  --enable-iam-database-authentication \
  --apply-immediately
```

### Create Database User with IAM Authentication

Connect to your PostgreSQL database and create a user for IAM authentication:

```sql
-- Create the IAM user
CREATE USER myapp_user;

-- Grant rds_iam role (required for IAM authentication)
GRANT rds_iam TO myapp_user;

-- Grant database access
GRANT CONNECT ON DATABASE application TO myapp_user;

-- Grant schema usage
GRANT USAGE ON SCHEMA public TO myapp_user;

-- Grant table permissions (adjust as needed)
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO myapp_user;
GRANT SELECT, USAGE ON ALL SEQUENCES IN SCHEMA public TO myapp_user;

-- Grant default privileges for future tables
ALTER DEFAULT PRIVILEGES IN SCHEMA public 
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO myapp_user;
```

### Create Kubernetes ServiceAccount

After creating the Postgres resource, retrieve the IAM role ARN from the status and create a ServiceAccount:

```bash
# Get the IAM role ARN
kubectl get postgres myapp-db-access -n myapp -o jsonpath='{.status.roleArn}'
```

Create the ServiceAccount with the annotation:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: myapp-sa
  namespace: myapp
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/crossplane-postgres-myapp-db-access
```

## Usage Examples

### Example 1: Basic RDS Instance Access

```yaml
apiVersion: dip.io/v1alpha1
kind: Postgres
metadata:
  name: myapp-db-access
  namespace: myapp
spec:
  serviceAccount:
    name: myapp-sa
  
  database:
    existingIdentifier: myapp-production-db
    type: rds-instance
    engine: postgres
    databaseName: application

  
  permissions:
    allowConnect: true
  
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
  serviceAccount:
    name: myapp-sa
  
  database:
    existingIdentifier: myapp-aurora-cluster
    type: aurora-cluster
    engine: postgres
    databaseName: application

  
  permissions:
    allowConnect: true
```

### Example 3: With Connection Secret

```yaml
apiVersion: dip.io/v1alpha1
kind: Postgres
metadata:
  name: myapp-db-with-secret
  namespace: myapp
spec:
  serviceAccount:
    name: myapp-sa
  
  database:
    existingIdentifier: myapp-production-db
    type: rds-instance

    resourceId: db-ABCDEFGHIJKLMNOP123456  # Optional: provide if known
  
  writeConnectionSecretToRef:
    name: myapp-db-credentials
  
  permissions:
    allowConnect: true
```

The connection secret will contain:
- `endpoint`: Database endpoint hostname
- `port`: Database port
- `database`: Database name
- `username`: IAM database username
- `password-note`: Reminder to use IAM authentication

### Example 4: Read-Only Access

```yaml
apiVersion: dip.io/v1alpha1
kind: Postgres
metadata:
  name: analytics-readonly-db
  namespace: analytics
spec:
  serviceAccount:
    name: analytics-reader-sa
  
  database:
    existingIdentifier: production-main-db
    type: rds-instance

  
  permissions:
    allowConnect: true
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

### Example 5: Create Development Database

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

  
  permissions:
    allowConnect: true
  
  tags:
    Environment: development
    Team: platform
```

### Example 6: Create Production Database

```yaml
apiVersion: dip.io/v1alpha1
kind: Postgres
metadata:
  name: myapp-prod-db
  namespace: myapp
spec:
  serviceAccount:
    name: myapp-prod-sa
  
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
  
  permissions:
    allowConnect: true
  
  tags:
    Environment: production
    CostCenter: engineering
```

### Example 7: Create Aurora PostgreSQL Cluster

```yaml
apiVersion: dip.io/v1alpha1
kind: Postgres
metadata:
  name: myapp-aurora
  namespace: myapp
spec:
  serviceAccount:
    name: myapp-aurora-sa
  
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
  
  permissions:
    allowConnect: true
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

### Using Python (psycopg2 or psycopg3)

```python
import boto3
import psycopg2

# Generate IAM authentication token
rds_client = boto3.client('rds', region_name='us-east-1')
token = rds_client.generate_db_auth_token(
    DBHostname='myapp-db.abc123.us-east-1.rds.amazonaws.com',
    Port=5432,
    DBUsername='myapp_user',
    Region='us-east-1'
)

# Connect using the token as password
conn = psycopg2.connect(
    host='myapp-db.abc123.us-east-1.rds.amazonaws.com',
    port=5432,
    database='application',
    user='myapp_user',
    password=token,
    sslmode='require'
)
```

### Using Python (SQLAlchemy)

```python
import boto3
from sqlalchemy import create_engine, event
from sqlalchemy.engine.url import URL

def get_iam_token():
    rds_client = boto3.client('rds', region_name='us-east-1')
    return rds_client.generate_db_auth_token(
        DBHostname='myapp-db.abc123.us-east-1.rds.amazonaws.com',
        Port=5432,
        DBUsername='myapp_user',
        Region='us-east-1'
    )

# Create engine
url = URL.create(
    drivername='postgresql+psycopg2',
    username='myapp_user',
    password=get_iam_token(),
    host='myapp-db.abc123.us-east-1.rds.amazonaws.com',
    port=5432,
    database='application',
    query={'sslmode': 'require'}
)

engine = create_engine(url)

# Optionally: refresh token before each connection
@event.listens_for(engine, "do_connect")
def receive_do_connect(dialect, conn_rec, cargs, cparams):
    cparams['password'] = get_iam_token()
```

### Using Node.js (pg library)

```javascript
const AWS = require('aws-sdk');
const { Client } = require('pg');

// Create RDS signer
const signer = new AWS.RDS.Signer({
  region: 'us-east-1',
  hostname: 'myapp-db.abc123.us-east-1.rds.amazonaws.com',
  port: 5432,
  username: 'myapp_user'
});

// Get authentication token
signer.getAuthToken({}, (err, token) => {
  if (err) {
    console.error('Could not get auth token:', err);
    return;
  }

  // Connect to database
  const client = new Client({
    host: 'myapp-db.abc123.us-east-1.rds.amazonaws.com',
    port: 5432,
    user: 'myapp_user',
    password: token,
    database: 'application',
    ssl: { rejectUnauthorized: false }
  });

  client.connect();
});
```

### Using AWS CLI (for testing)

```bash
# Generate authentication token
TOKEN=$(aws rds generate-db-auth-token \
  --hostname myapp-db.abc123.us-east-1.rds.amazonaws.com \
  --port 5432 \
  --username myapp_user \
  --region us-east-1)

# Connect using psql
psql "host=myapp-db.abc123.us-east-1.rds.amazonaws.com port=5432 dbname=application user=myapp_user password=$TOKEN sslmode=require"
```

## Status Fields

After creating a Postgres resource, you can check its status:

```bash
kubectl get postgres myapp-db-access -n myapp -o yaml
```

Status fields include:
- `dbInstanceIdentifier`: RDS instance or Aurora cluster identifier
- `dbResourceId`: RDS resource ID used in IAM policy
- `dbEndpoint`: Database endpoint hostname
- `dbPort`: Database port
- `databaseName`: Database name

- `roleArn`: ARN of the created IAM role (use this for ServiceAccount annotation)
- `accountId`: AWS account ID
- `connectionString`: PostgreSQL connection string template

## Troubleshooting

### Connection Refused

**Problem**: Can't connect to the database

**Solutions**:
1. Check security groups allow traffic from EKS nodes
2. Verify database is in same VPC or has proper networking
3. Check RDS instance status: `aws rds describe-db-instances --db-instance-identifier <name>`

### Authentication Failed

**Problem**: IAM authentication fails

**Solutions**:
1. Verify IAM authentication is enabled on RDS instance
2. Check database user was created with `GRANT rds_iam`
3. Verify IAM role ARN is correctly annotated on ServiceAccount
4. Check token generation is working: test with AWS CLI
5. Verify pod has IRSA configured correctly (check AWS_ROLE_ARN env var)

### IAM Policy Issues

**Problem**: IAM policy doesn't allow connection

**Solutions**:
1. Check database resource ID is correct in status
2. Verify IAM policy resource ARN matches: `arn:aws:rds-db:REGION:ACCOUNT:dbuser:RESOURCE_ID/USERNAME`
3. If resource ID not auto-detected, provide it explicitly in spec: `spec.database.resourceId`

### Token Expiration

**Problem**: Connection works but fails after 15 minutes

**Solution**: IAM authentication tokens expire after 15 minutes. Your application must:
1. Generate a new token before each connection, OR
2. Use a connection pool with token refresh logic

### ServiceAccount Not Working

**Problem**: Pod can't assume IAM role

**Solutions**:
1. Verify ServiceAccount has the annotation: `eks.amazonaws.com/role-arn`
2. Check pod is using the correct ServiceAccount
3. Verify OIDC provider is configured correctly in EKS
4. Check IAM role trust policy matches the ServiceAccount namespace and name

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

### Custom IAM Permissions

Add additional IAM actions beyond basic connect:

```yaml
spec:
  permissions:
    allowConnect: true
    additionalActions:
      - "rds:DescribeDBInstances"
      - "rds:DescribeDBClusters"
```

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

### VPC Security Group Example

```yaml
# Example security group rules for RDS
# Allow PostgreSQL access only from EKS nodes
Type: ingress
Protocol: TCP
Port: 5432
Source: <EKS-Node-Security-Group-ID>
```

## Current Limitations

- Does not automatically create PostgreSQL IAM users (must be done manually after DB creation)
- Aurora cluster instance provisioning not included (cluster only, add instances separately)
- No automated schema migration or user provisioning

## Future Roadmap

Planned enhancements:
- **CloudNativePG Integration**: Support for Kubernetes-native PostgreSQL operators
- **Automatic User Provisioning**: Create IAM database users automatically
- **Schema Migration**: Integrate with Flyway or Liquibase for migrations
- **Connection Pooling**: PgBouncer sidecar integration
- **Read Replicas**: Automated read replica provisioning
- **Monitoring Integration**: CloudWatch and Prometheus metrics
- **Automated Failover**: Enhanced HA configuration

## References

- [AWS RDS IAM Authentication](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.IAMDBAuth.html)
- [EKS IRSA Documentation](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [Crossplane Documentation](https://docs.crossplane.io/)
- [PostgreSQL IAM Authentication Setup](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.IAMDBAuth.Connecting.html)

## Support

For issues or questions:
1. Check the [Troubleshooting](#troubleshooting) section
2. Review the [observed-resources.md](observed-resources.md) documentation
3. Validate your configuration using `make validate`
4. Test rendering using `make render`
