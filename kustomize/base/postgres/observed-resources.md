# Postgres Observed Resources

This document describes the AWS and Kubernetes resources created and observed by the Postgres composition.

## Mode: Existing Database (`mode: existing`)

### Resources Observed (Not Managed)

#### 1. RDS Instance (`rds.aws.m.upbound.io/v1beta1/Instance`)
- **Name Pattern**: `{composite-name}-rds-instance`
- **External Name**: Database identifier from `spec.database.identifier`
- **Purpose**: Observe existing RDS PostgreSQL instance to retrieve metadata
- **Management Policy**: `Observe` (read-only, no modifications)
- **Data Retrieved**:
  - Database endpoint (hostname)
  - Database port
  - Database resource ID (for IAM policy)
  - Database name
  - Engine version
  - Status

**OR**

#### 1. Aurora Cluster (`rds.aws.m.upbound.io/v1beta1/Cluster`)
- **Name Pattern**: `{composite-name}-rds-cluster`
- **External Name**: Cluster identifier from `spec.database.identifier`
- **Purpose**: Observe existing Aurora PostgreSQL cluster to retrieve metadata
- **Management Policy**: `Observe` (read-only, no modifications)
- **Data Retrieved**:
  - Cluster endpoint (hostname)
  - Cluster port
  - Cluster resource ID (for IAM policy)
  - Database name
  - Engine version
  - Status

## Mode: Create Database (`mode: create`)

### Resources Created and Managed

#### 1. RDS Subnet Group (`rds.aws.m.upbound.io/v1beta1/SubnetGroup`)
- **Name Pattern**: `{composite-name}-subnet-group`
- **Purpose**: Define the subnets where the database will be deployed
- **Configuration**:
  - Subnet IDs from `spec.database.vpcConfig.subnetIds`
  - Must include at least 2 subnets in different availability zones
  - Tags applied from `spec.tags`

#### 2. RDS Instance (`rds.aws.m.upbound.io/v1beta1/Instance`) - For RDS PostgreSQL
- **Name Pattern**: `{composite-name}-rds-instance`
- **External Name**: `spec.database.identifier`
- **Purpose**: Create and manage new RDS PostgreSQL instance
- **Management Policy**: Full management (Create, Update, Delete)
- **Configuration**:
  - Engine: PostgreSQL
  - Engine Version: From `spec.database.engineVersion`
  - Instance Class: From `spec.database.instanceClass`
  - Storage: `allocatedStorage` GB with type from `storageType`
  - Encryption: Enabled by default (`storageEncrypted`)
  - IAM Authentication: Automatically enabled
  - Master Username: From `spec.database.masterUsername`
  - Master Password: From secret reference
  - VPC: Uses created subnet group and security groups
  - Backups: Retention period from `backupRetentionPeriod`
  - Multi-AZ: From `spec.database.multiAz`
  - Public Access: From `spec.database.publiclyAccessible`

**OR**

#### 2. Aurora Cluster (`rds.aws.m.upbound.io/v1beta1/Cluster`) - For Aurora PostgreSQL
- **Name Pattern**: `{composite-name}-rds-cluster`
- **External Name**: `spec.database.identifier`
- **Purpose**: Create and manage new Aurora PostgreSQL cluster
- **Management Policy**: Full management (Create, Update, Delete)
- **Configuration**:
  - Engine: aurora-postgresql
  - Engine Version: From `spec.database.engineVersion`
  - Master Username: From `spec.database.masterUsername`
  - Master Password: From secret reference
  - VPC: Uses created subnet group and security groups
  - Backups: Retention period from `backupRetentionPeriod`
  - Encryption: Enabled by default (`storageEncrypted`)
  - IAM Authentication: Automatically enabled

**Note**: Aurora cluster instances must be created separately

## Resources Created and Managed

### 2. IAM Role (`iam.aws.m.upbound.io/v1beta1/Role`)
- **Name Pattern**: `{composite-name}-irsa-role`
- **Purpose**: Provide AWS credentials to Kubernetes ServiceAccount via IRSA
- **Trust Policy**: Configured for IRSA with:
  - EKS OIDC provider ARN
  - Specific ServiceAccount in specific namespace
  - Audience: `sts.amazonaws.com`
- **Trust Policy Format**:
  ```json
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/oidc.eks.REGION.amazonaws.com/id/OIDC_ID"
        },
        "Action": "sts:AssumeRoleWithWebIdentity",
        "Condition": {
          "StringEquals": {
            "oidc.eks.REGION.amazonaws.com/id/OIDC_ID:sub": "system:serviceaccount:NAMESPACE:SERVICE_ACCOUNT_NAME",
            "oidc.eks.REGION.amazonaws.com/id/OIDC_ID:aud": "sts.amazonaws.com"
          }
        }
      }
    ]
  }
  ```

### 3. IAM Policy (`iam.aws.m.upbound.io/v1beta1/Policy`)
- **Name Pattern**: `{composite-name}-rds-policy`
- **Purpose**: Define RDS IAM authentication permissions
- **Permissions**:
  - `rds-db:connect` - Connect to database using IAM authentication
  - Additional actions from `spec.permissions.additionalActions` (optional)
- **Resource Scope**: Limited to specific database user ARN
- **Policy Format**:
  ```json
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "rds-db:connect"
        ],
        "Resource": [
          "arn:aws:rds-db:REGION:ACCOUNT_ID:dbuser:DB_RESOURCE_ID/IAM_USERNAME"
        ]
      }
    ]
  }
  ```
- **Note**: If `spec.database.resourceId` is not provided, the policy uses a wildcard resource (`*/*`) and relies on observing the RDS instance to get the actual resource ID.

### 4. IAM Role Policy Attachment (`iam.aws.m.upbound.io/v1beta1/RolePolicyAttachment`)
- **Name Pattern**: `{composite-name}-role-policy-attachment`
- **Purpose**: Attach the IAM policy to the IAM role
- **Links**: IAM Role + IAM Policy

## External Resources (Not Managed by Composition)

### Existing RDS Database
- **Created by**: User or infrastructure team (outside Crossplane)
- **Requirements**:
  - IAM authentication must be enabled on the RDS instance/cluster
  - Database must exist and be accessible
  - Database user for IAM authentication must be created in PostgreSQL

### PostgreSQL IAM Database User
- **Created by**: Database administrator (manual SQL command)
- **Creation Command**:
  ```sql
  CREATE USER myapp_user;
  GRANT rds_iam TO myapp_user;
  -- Grant necessary database permissions
  GRANT CONNECT ON DATABASE application TO myapp_user;
  GRANT USAGE ON SCHEMA public TO myapp_user;
  GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO myapp_user;
  ```

### Kubernetes ServiceAccount
- **Must be created separately** by the user or another system
- **Required Annotation**: `eks.amazonaws.com/role-arn` with the IAM role ARN from the Postgres status
- **Namespace**: Must match the Postgres resource namespace
- **Name**: Must match `spec.serviceAccount.name` in the Postgres spec
- **Example**:
  ```yaml
  apiVersion: v1
  kind: ServiceAccount
  metadata:
    name: myapp-sa
    namespace: myapp
    annotations:
      eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/crossplane-postgres-myapp-db-access
  ```

## Resource Dependencies

```
Postgres Composite Resource
│
├─> RDS Instance or Aurora Cluster (observed, not managed)
│   └─> Provides: endpoint, port, resource ID, database name
│
├─> IAM Role (with IRSA trust policy)
│
├─> IAM Policy (RDS IAM auth permissions)
│   └─> Depends on: Database resource ID from observed RDS resource
│
└─> IAM Role Policy Attachment
    ├─> Requires: IAM Role
    └─> Requires: IAM Policy

External (user-managed):
├─> RDS Database Instance/Cluster
│   └─> IAM authentication enabled
│
├─> PostgreSQL Database User
│   └─> Created with IAM authentication enabled (GRANT rds_iam)
│
└─> Kubernetes ServiceAccount
    └─> Annotation requires: IAM Role ARN (from Postgres status)
```

## Composition Annotations

All resources include the following annotation for tracking:
- `gotemplating.fn.crossplane.io/composition-resource-name`: Internal resource name

## External Name Handling

- **RDS Instance/Cluster**: Uses `crossplane.io/external-name` annotation to reference existing database
- **IAM Resources**: Auto-generated by AWS based on Crossplane resource name
- **ServiceAccount**: Name set via `spec.serviceAccount.name` parameter

## Connection Details

The composition outputs connection details that can be written to a Kubernetes secret:

- `endpoint`: Database endpoint hostname
- `port`: Database port
- `database`: Database name
- `username`: IAM database username
- `password-note`: Reminder to use IAM authentication token (not a static password)

### Generating IAM Authentication Token

Applications must generate a temporary authentication token using AWS SDK:

**Python example**:
```python
import boto3

rds_client = boto3.client('rds')
token = rds_client.generate_db_auth_token(
    DBHostname='mydb.abc123.us-east-1.rds.amazonaws.com',
    Port=5432,
    DBUsername='myapp_user',
    Region='us-east-1'
)
# Use token as password in PostgreSQL connection
```

**AWS CLI example**:
```bash
aws rds generate-db-auth-token \
  --hostname mydb.abc123.us-east-1.rds.amazonaws.com \
  --port 5432 \
  --username myapp_user \
  --region us-east-1
```

## Status Fields

The composition populates the following status fields:

- `dbInstanceIdentifier`: RDS instance or Aurora cluster identifier
- `dbResourceId`: RDS resource ID used in IAM policy ARN
- `dbEndpoint`: Database endpoint hostname
- `dbPort`: Database port
- `databaseName`: Database name

- `roleArn`: ARN of the created IAM role
- `accountId`: AWS account ID
- `connectionString`: PostgreSQL connection string template (without password)
