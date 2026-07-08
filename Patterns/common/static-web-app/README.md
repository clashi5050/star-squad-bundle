# Static Web App Pattern — Star Squad

Updated: 7/8/2026

Provisions an Azure Static Web App (Free tier) in its own resource group using
the same conventions as the `resource-group` pattern (OIDC auth, pinned action
SHAs, JSON-input matrix, remote state). Unlike `resource-group`, `main.tf` here
is static rather than eval-templated (see Notes).

Infrastructure and application content are kept separate:

```
Patterns/common/static-web-app/   # Terraform (infra only)
apps/star-squad/                  # App content only (index.html + SWA config)
.github/workflows/
  static-web-app.yml              # Provisions the SWA (manual, workflow_dispatch)
  static-web-app-deploy.yml       # Deploys app content (on push to apps/star-squad/**)
.github/inputs/main/use2/
  staticwebapp.json               # Environment/region matrix input
```

## Two-step flow (by design)

Terraform provisions the **resource**; content is deployed separately with a
**deployment token** that only exists after the resource is created. So:

1. Run **Add Static Web App** (`static-web-app.yml`) from the Actions UI.
   Pick `short_loc` + `environment`. This creates the RG and SWA.
2. Grab the deployment token. Either read the Terraform output `api_key`
   (`terraform output -raw api_key`) or copy it from the SWA in the Azure
   portal (Overview → Manage deployment token).
3. Save it as the GitHub Actions secret **`AZURE_STATIC_WEB_APPS_API_TOKEN`**.
4. Push any change under `apps/star-squad/**` (or run the deploy workflow
   manually). The app goes live at the SWA's `default_host_name`.

## Required GitHub configuration

This repo is **public**, so identifiers that carry no access on their own are
kept as GitHub **variables** (visible in the UI/logs); only things that are
themselves a usable credential are **secrets**.

Variables (per environment, e.g. `main`) — set by `setup-oidc-and-secrets.sh`:

| Variable | Purpose |
|---|---|
| `ARM_CLIENT_ID` | OIDC app registration (client) ID |
| `ARM_SUBSCRIPTION_ID` | Target subscription |
| `ARM_TENANT_ID` | Azure AD tenant |

These are safe as plain variables under OIDC: there's no password/secret
behind them, and minting a token still requires a matching federated-credential
subject on the Azure AD app (scoped to this exact repo + environment).

Secrets (per environment):

| Secret | Purpose |
|---|---|
| `GH_PAT` | Read access to the private `iac-modules` repo (module downloads) |
| `AZURE_STATIC_WEB_APPS_API_TOKEN` | SWA content deployment token (set after step 1, via `set-swa-token.sh`) |

The remote state storage account/container/resource group are fixed in the
committed [`backend.hcl`](backend.hcl) — no GitHub variables needed for these.

## Creating the `GH_PAT` (fine-grained)

`GH_PAT` gives the workflow read access to the private `iac-modules` repo so
`terraform init` can download modules over HTTPS (wired up by the
"Configure git for module access" step, which rewrites
`https://github.com` to `https://oauth2:<GH_PAT>@github.com`).

Create a **fine-grained** PAT scoped to exactly one repo:

1. GitHub → **Settings → Developer settings → Personal access tokens →
   Fine-grained tokens → Generate new token**.
2. **Resource owner:** the account/org that owns `iac-modules` (`clashi5050`).
3. **Repository access:** *Only select repositories* → **`iac-modules`**.
   Do **not** grant "All repositories".
4. **Repository permissions** (least privilege — these two only):
   - **Contents: Read-only** — required to fetch module source.
   - **Metadata: Read-only** — mandatory; GitHub selects it automatically.
   Leave everything else *No access*.
5. **Expiration:** pick a bounded lifetime (e.g. 90 days) and calendar a
   rotation. Re-run the `gh secret set` below when you rotate.
6. Generate, copy the token, then store it as the environment secret:

   ```bash
   gh secret set GH_PAT --env main --repo clashi5050/star-squad-bundle --body '<pat>'
   ```

Notes:
- Set it at the **environment** level (`main`, etc.) so it lines up with the
  workflow's `environment: ${{ github.event.inputs.environment }}`, exactly like
  the `ARM_*` variables set by `setup-oidc-and-secrets.sh`.
- If `iac-modules` lives under a different owner than `star-squad-bundle`, create the
  token under that owner; fine-grained PATs are scoped per resource owner.

## Notes

- **Pin the deploy action SHA.** `static-web-app-deploy.yml` currently uses
  `Azure/static-web-apps-deploy@v1` with a `TODO`. Replace it with a full commit
  SHA from the action's releases page to match the repo's pinning convention.
- **Region support.** The SWA Free tier is only available in some regions. If
  `location` in the JSON isn't supported, the apply will fail — pick a supported
  region for the SWA (it does not have to match other resources).
- **`main.tf` is static.** Unlike the resource-group pattern's `eval`/`echo`
  templating (which breaks on quoted strings and `${...}` interpolations),
  `main.tf` here reads everything as Terraform variables. Only
  `nonsecret.auto.tfvars` is rendered from its template. This is intentional and
  more robust — consider back-porting it to the resource-group pattern.
- **Remote state backend.** Storage account, container, and resource group are
  fixed in the committed [`backend.hcl`](backend.hcl) (currently
  `tfstatestoragelab2` / `tfstate` / `tfstatelab`). This storage account lives
  in a *different* subscription (`cjsazurelab`) than the one resources are
  deployed into (`arm_subscription_id`), so `backend.hcl` also pins an explicit
  `subscription_id` — the deploy service principal needs `Storage Account
  Contributor` on the `tfstatelab` resource group in that subscription for
  backend init to read the storage account's keys. Only the state **key** —
  `<environment>-<short_loc>-static-web-app.tfstate` — still varies per
  deployment and is passed via `-backend-config` on `terraform init`, so it
  never collides with other patterns in the same storage account.
