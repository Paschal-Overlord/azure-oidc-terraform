# Azure OIDC Federation — Multi-Repo GitHub Actions Auth

Terraform that configures GitHub Actions → Azure authentication via OIDC for an entire organisation, without a single stored credential. Every workflow authenticates using short-lived tokens exchanged at runtime — no client secrets, no expiry dates, nothing to rotate.

Built to manage OIDC across 15+ repositories spanning two deployment branches, while staying within Azure AD's hard limit of 20 federated credentials per App Registration.

---

## The problem

The standard approach — create a service principal, generate a client secret, paste it into GitHub Secrets — has three failure modes:

1. Secrets expire. Someone has to notice and rotate them.
2. Secrets get committed to repos or shared insecurely.
3. There's no audit trail for which workflow used which credential.

OIDC removes the secret entirely. GitHub presents a signed JWT to Azure at runtime. Azure validates it against a pre-configured trust relationship and issues a scoped access token. Nothing is stored anywhere.

---

## The scale problem and how this solves it

Azure AD has a hard limit of **20 federated credentials per App Registration**. Each `repo × branch` combination requires one credential. With 15 repos deploying from `main` and `development`, that's 30 credentials — over the limit.

The solution: split repos into named groups. Each group gets its own App Registration and `client_id`. Everything else — tenant, subscription, Key Vault — is shared.

```
GitHub Org
├── frontend group  →  App Registration A  →  client_id_A
│   ├── repo: customer-frontend    (main + development = 2 credentials)
│   ├── repo: admin-frontend       (main + development = 2 credentials)
│   └── ...                        (6 repos × 2 branches = 12 credentials ✓)
│
└── backend group   →  App Registration B  →  client_id_B
    ├── repo: property-api         (main + development = 2 credentials)
    ├── repo: invoice-api          (main + development = 2 credentials)
    └── ...                        (9 repos × 2 branches = 18 credentials ✓)
```

Adding a new repo is a one-line change in `terraform.tfvars` + `terraform apply`.

---

## What it provisions

```
For each group in app_registrations:
├── azuread_application           — App Registration
├── azuread_service_principal     — Service Principal attached to the App Reg
├── azurerm_role_assignment       — Key Vault Secrets User on the shared vault
│
└── For each repo × branch in the group:
    └── azuread_application_federated_identity_credential
        subject: repo:<org>/<repo>:ref:refs/heads/<branch>
```

Each service principal gets `Key Vault Secrets User` on the shared vault — workflows can pull secrets at runtime without any secrets being stored in GitHub.

---

## File structure

```
terraform/oidc/
├── versions.tf              # Provider version pins (azurerm ~>3.100, azuread ~>2.48)
├── variables.tf             # All input declarations with inline docs
├── main.tf                  # App Registrations, federated creds, KV role assignments
├── outputs.tf               # client_ids per group, tenant_id, subscription_id
├── terraform.tfvars.example # Template — copy and fill in your values
└── .gitignore               # Excludes *.tfvars and state files
```

---

## How a workflow uses this

Each workflow only needs three GitHub secrets: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`.

```yaml
permissions:
  id-token: write   # Required — allows GitHub to mint the OIDC token
  contents: read

steps:
  - name: Azure login (OIDC — no stored credentials)
    uses: azure/login@v2
    with:
      client-id: ${{ secrets.AZURE_CLIENT_ID }}
      tenant-id: ${{ secrets.AZURE_TENANT_ID }}
      subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

  - name: Pull secrets from Key Vault at runtime
    uses: Azure/get-keyvault-secrets@v1
    with:
      keyvault: ${{ inputs.keyvault_name }}
      secrets: "DB-PASSWORD, ACR-NAME, VM-SSH-KEY"
    id: kv
```

No secrets in GitHub beyond the three OIDC identifiers. Everything else — database passwords, SSH keys, storage credentials — lives in Key Vault and is fetched at deploy time.

---

## Setting GitHub secrets after apply

```bash
terraform output tenant_id        # → AZURE_TENANT_ID   (one org-level secret)
terraform output subscription_id  # → AZURE_SUBSCRIPTION_ID (one org-level secret)
terraform output client_ids       # → one per group
```

**Option A — Org-level secrets with group suffix** (cleaner for many repos)
```
AZURE_CLIENT_ID_FRONTEND  →  client_ids["frontend"]
AZURE_CLIENT_ID_BACKEND   →  client_ids["backend"]
```

Each workflow receives the right one via a workflow input:
```yaml
azure_client_id: ${{ secrets.AZURE_CLIENT_ID_BACKEND }}
```

**Option B — Repo-level secret** (simpler for smaller setups)
In each repo, add a single `AZURE_CLIENT_ID` secret with that group's value.

---

## Setup

### Prerequisites
- Terraform >= 1.5.0
- `az login` with permissions to create App Registrations and role assignments
- An existing Azure Key Vault (created separately — see the infrastructure repo)

### First-time deploy

```bash
git clone <this-repo>
cd terraform/oidc

cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — fill in your org, vault name, and repo names

terraform init
terraform apply
```

### Adding a repo to an existing group

```hcl
# terraform.tfvars
app_registrations = {
  "backend" = {
    repos = [
      "existing-repo-1",
      "existing-repo-2",
      "new-repo-name",   # ← add here
    ]
    branches = ["main", "development"]
  }
}
```

```bash
terraform apply  # Only the new federated credential is created
```

### Adding a new group

```hcl
app_registrations = {
  "backend"  = { ... }
  "frontend" = { ... }
  "data"     = {              # ← new group
    repos    = ["analytics-service", "reporting-service"]
    branches = ["main"]
  }
}
```

```bash
terraform apply
terraform output client_ids  # copy the new group's client_id to GitHub
```

---

## Checking credential usage

```bash
# Verify no group is approaching the 20-credential limit
terraform output credential_count_per_group
```

```
{
  "backend"  = 18   # 9 repos × 2 branches
  "frontend" = 12   # 6 repos × 2 branches
}
```

---

## Security notes

**Principle of least privilege.** Each service principal only gets `Key Vault Secrets User` — it can read secrets, not create, update, or delete them. Infrastructure provisioning (which needs `Key Vault Secrets Officer`) is done separately under a different identity.

**Subject claim scoping.** Federated credentials are scoped to a specific `repo:org/repo:ref:refs/heads/branch`. A workflow running on a different repo or branch cannot assume this identity — Azure will reject the token.

**No secrets in state.** The Terraform state for this module contains only App Registration IDs and object IDs — nothing sensitive.

---

## What I'd improve for production

- Enable remote state with a storage backend (commented out in `versions.tf` — fill in and uncomment)
- Add `environment`-scoped federated credentials in addition to branch-scoped ones, to support GitHub Environment protection rules
- Output a `credential_count_per_group` warning if any group exceeds 16 (leaving headroom before the 20 limit)
- Tag App Registrations with team ownership for easier auditing

---

## Stack

- Terraform >= 1.5  ·  AzureRM `~>3.100`  ·  AzureAD `~>2.48`
- GitHub Actions OIDC
- Azure AD (App Registrations, Federated Identity Credentials)
- Azure Key Vault (RBAC)
