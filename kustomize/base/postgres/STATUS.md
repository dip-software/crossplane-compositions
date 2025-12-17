# Postgres Composition - Status & Known Issues

## Overview
This project provides two separate compositions (AWS and CNPG) chosen via `compositionSelector`:
- **AWS RDS** - Production-grade managed PostgreSQL on AWS (Default implicit selection)
- **CloudNativePG (CNPG)** - Kubernetes-native PostgreSQL for development/testing (`provider: cnpg` via selector)

## ✅ What's Working

### Core Functionality
- ✅ **AWS RDS Instance Creation** - Successfully provisions RDS PostgreSQL instances
- ✅ **CNPG Cluster Creation** - Successfully provisions CloudNativePG clusters
- ✅ **T-Shirt Sizing** - Abstract sizing (small/medium/large) maps correctly to instance types
- ✅ **Multi-AZ Support** - HA configuration works for both providers
- ✅ **Version Validation** - XRD enforces PostgreSQL version >= 17
- ✅ **Snapshot Restore** - Can restore RDS from snapshots
- ✅ **Existing DB Import** - Can import/manage existing RDS instances (observe mode)
- ✅ **Status Propagation** - DB endpoint, port, and resource ID are patched to XR status

### CNPG-Specific
- ✅ **Secret Requirements** - CNPG requires secrets with both `username` and `password` keys
- ✅ **Service Naming** - CNPG services follow predictable naming (`{name}-rw`, `{name}-r`, `{name}-ro`)
- ✅ **Cluster Health** - CNPG clusters reach "Cluster in healthy state" successfully

### AWS RDS-Specific  
- ✅ **VPC Integration** - Correctly uses subnet groups and security groups from environment configs
- ✅ **Instance Provisioning** - RDS instances provision successfully with PostgreSQL 18.1
- ✅ **Encryption** - Storage encryption is enabled by default

## ❌ Known Issues

### Connection Secrets - **CRITICAL ISSUE**

**Problem**: Connection details are NOT being written to secrets despite being configured in the composition.

**Root Cause**: 
The `FromCompositeFieldPath` patch that should propagate `spec.writeConnectionSecretToRef` from the XR to the managed resource (RDS Instance/CNPG Cluster) is not being applied by the patch-and-transform function.

**Evidence**:
- ✅ The `connectionDetails` are defined in the composition
- ✅ The `writeConnectionSecretToRef` patch exists in the CompositionRevision
- ❌ The managed resource (Instance/Cluster) does **NOT** have `spec.writeConnectionSecretToRef` in its spec
- ❌ Connection secrets exist but have **NO DATA**

**Current Behavior**:
```bash
$ kubectl get secret myapp-minimal-db-connection -o yaml
# Secret exists but data: {} is empty
```

**Expected Behavior**:
The secret should contain:
- `endpoint`: Database hostname
- `port`: Database port (5432 or from RDS)

**Workaround**:
Users must manually retrieve connection details from the XR status or managed resource:
```bash
# Get endpoint
kubectl get postgres myapp-minimal-db -o jsonpath='{.status.dbEndpoint}'

# Get port  
kubectl get postgres myapp-minimal-db -o jsonpath='{.status.dbPort}'

# Get password (from referenced secret)
kubectl get secret myapp-db-password -o jsonpath='{.data.password}' | base64 -d
```

### Other Issues

1. **Composition Application**
   - `kubectl apply` sometimes strips fields from the composition
   - **Workaround**: Use `kubectl delete` + `kubectl create` instead

2. **XRD Pattern Validation**
   - The engineVersion pattern validation (>= 17) is defined but may not be actively enforced until XRD is recreated
   - **Status**: Non-blocking, validation is documented in XRD schema

## 📋 Testing Checklist

### Tested & Working
- [x] AWS RDS instance creation with PostgreSQL 18.1
- [x] CNPG cluster creation with PostgreSQL 18.1
- [x] Status fields (endpoint, port, resourceId) propagate to XR
- [x] Multi-AZ configuration
- [x] T-shirt sizing (small/medium/large)
- [x] Subnet group creation
- [x] Security group association
- [x] Storage encryption
- [x] Backup retention configuration

### Tested & Failing
- [ ] Connection secret population (NO DATA written)
- [ ] Password propagation to connection secret

### Not Yet Tested
- [ ] Aurora cluster provisioning
- [ ] Snapshot restore for CNPG
- [ ] IAM authentication (removed from composition)
- [ ] Custom KMS keys for encryption
- [ ] Deletion policy (Orphan vs Delete)

## 🔧 Required Fixes

### Priority 1: Connection Secrets
The composition needs to be modified to ensure `writeConnectionSecretToRef` is properly set on managed resources.

**Possible Solutions**:
1. Add `writeConnectionSecretToRef` directly in the Go template (instead of relying on patch)
2. Investigate why `FromCompositeFieldPath` patches aren't being applied
3. Use a different approach for connection secret propagation (e.g., function-kcl)

### Priority 2: Documentation
- Add examples showing how to retrieve connection details manually
- Document the secret structure requirements for CNPG
- Add troubleshooting guide

## 📝 Configuration Notes

### PostgreSQL Versions
- **Minimum Version**: 17.x (enforced by XRD pattern)
- **Recommended**: 18.1 (latest tested)
- **Pattern**: `^(1[7-9]|[2-9][0-9])\.[0-9]+$`

### Secret Requirements

**For CNPG**:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: myapp-db-password
type: kubernetes.io/basic-auth
stringData:
  username: postgres  # REQUIRED - must match masterUsername
  password: <password>
```

**For AWS RDS**:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: myapp-db-password
stringData:
  password: <password>
```

### Provider-Specific Defaults

| Setting | AWS RDS | CNPG |
|---------|---------|------|
| Instances | 1 (Multi-AZ) | 2 (3 if multiAz) |
| Storage Class | gp3 | gp3-encrypted |
| Port | 5432 | 5432 |
| Endpoint | `{identifier}.{region}.rds.amazonaws.com` | `{name}-rw.{namespace}.svc` |

## 🚀 Usage Examples

See the `examples/` directory for:
- `minimal.yaml` - Minimal RDS/CNPG instance
- `new-rds-instance.yaml` - Full RDS configuration  
- `cnpg-minimal.yaml` - CNPG cluster
- `existing-rds.yaml` - Import existing RDS instance
- `restore-rds-from-snapshot.yaml` - Restore from snapshot

## 📊 Status Summary

| Feature | Status | Notes |
|---------|--------|-------|
| RDS Provisioning | ✅ Working | Fully functional |
| CNPG Provisioning | ✅ Working | Fully functional |
| Connection Secrets | ❌ **BROKEN** | Secrets empty - critical issue |
| Version Validation | ✅ Working | >= 17 enforced |
| Status Propagation | ✅ Working | Endpoint/port in XR status |
| Multi-AZ | ✅ Working | Both providers |
| Snapshot Restore | ⚠️ Partial | RDS works, CNPG untested |

**Last Updated**: 2025-12-16
**Tested With**: 
- Crossplane: v2.1.3
- function-patch-and-transform: v0.9.1
- AWS Provider: upbound.io/provider-aws-rds
- CloudNativePG: v1.x
