# Azure Deployment Status

> **Status: Not Yet Implemented**
>
> Azure support is aspirational. The files listed below exist as reference
> material for a future Azure deployment path, but no end-to-end Azure
> workflow is available today.

## What Exists

| File | Purpose | Status |
|------|---------|--------|
| `values-azure.yaml` | Azure instance types (`Standard_D8s_v5`) and storage classes (`managed-premium`) | Reference only |
| `ztp/siteconfigs/sno-azure-template.yaml` | Azure SNO SiteConfig template for ZTP | Reference only |
| `bootstrap.sh` config prompt | Accepts `azure` as `cloud_provider` | Config accepted but no deploy path |

## What Is Missing

To fully support Azure, the following would need to be created:

### AgnosticD Configuration
- `agnosticd/azure/vars.yml` — Azure-specific deployment variables
  (equivalent of `agnosticd/gcp/vars.yml`)
- Azure credential management (equivalent of GCP service account key)

### Scripts
- `scripts/generate-secrets.sh` is GCP-specific (reads
  `gcp-key*.json` service account key structure). An Azure equivalent
  would need to handle Azure service principal credentials.
- `scripts/deploy.sh` does not have Azure code paths

### Documentation
- Azure deployment guide (equivalent of `docs/gcp-deployment.md`)
- Azure-specific `onboard.yml` quota checks

## Current Recommendation

Use **GCP** as the cloud provider. The entire deployment pipeline —
AgnosticD vars, secret generation, deploy scripts, and documentation —
is tested and supported on GCP.

If you need Azure support, contributions are welcome. Start with:

1. Create `agnosticd/azure/vars.yml` based on the GCP vars
2. Add Azure credential handling to `scripts/generate-secrets.sh`
3. Test the bootstrap → deploy → validate pipeline on Azure
4. Add `docs/azure-deployment.md`

## Related Files

- [`values-azure.yaml`](../values-azure.yaml) — Azure overlay values
- [`ztp/siteconfigs/sno-azure-template.yaml`](../ztp/siteconfigs/sno-azure-template.yaml) — Azure SNO template
- [`docs/gcp-deployment.md`](gcp-deployment.md) — GCP deployment guide (working reference)
