# Static Web App Pattern — Star Squad

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

Variables:

| Variable | Purpose |
|---|---|
| `TFSTATE_SA` | Storage account holding remote Terraform state |
| `TFSTATE_RG` | Resource group of the state storage account |

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

## Accounts + cross-device sync (added)

The pattern now optionally provisions a backend so data follows a signed-in user
across devices, instead of living only in the browser's `localStorage`.

New resources (in `main.tf`):

- **Static Web App upgraded to `Standard`** (`var.swa_sku`, default `Standard`) —
  required for custom authentication and the managed API. This was `Free` before.
- **Azure Cosmos DB (serverless, SQL API)** — `cosmos-<name_prefix>`, with a
  `starsquad` database and a `families` container partitioned by `/userId`.
  Serverless means pay-per-request (pennies at this scale), no provisioned RU/s.
- **SWA app settings** wired to the Cosmos endpoint/key/db/container so the API
  can reach it without any secrets in source control.

New app code:

```
api/                              # SWA managed Functions API (Node.js)
  GetData/   -> GET  /api/data    # returns the signed-in user's saved state
  SaveData/  -> POST /api/data    # upserts it (keyed by x-ms-client-principal)
  shared/store.js                 # Cosmos client + auth-header decode
apps/star-squad/staticwebapp.config.json  # Entra External ID OIDC + /api locked to authenticated
scripts/setup-auth.sh             # one-time: app registration, secret, SWA settings
```

### Auth: email sign-in via Microsoft Entra External ID

Sign-in uses **Entra External ID** (customer identity/CIAM) as a custom OpenID
Connect provider. Users **sign up with an email + password**, verify by email,
and can reset their password; MFA is available. Static Web Apps hosts the
sign-in pages and injects the user into the API via the `x-ms-client-principal`
header — the app never handles passwords.

Config lives in `staticwebapp.config.json`; the client id/secret are read from
SWA app settings **`AAD_CLIENT_ID`** / **`AAD_CLIENT_SECRET`**, set by
`scripts/setup-auth.sh` (not through Terraform, so the OIDC secret stays out of
state). The tenant subdomain is set once via `EXTERNAL_ID_TENANT` in
`scripts/setup-auth.sh` (currently `cjsazurelab`), and the script patches
`wellKnownOpenIdConfiguration` in that config to match when it runs.

### Behaviour

- **Guest mode is unchanged.** With no sign-in, everything works on
  `localStorage` exactly as before.
- **Signed in:** on load the app pulls the cloud copy from `/api/data`; every
  change is debounced and pushed back via `POST /api/data`. `localStorage` stays
  as an offline cache.

### Bootstrap order

1. `terraform apply` (provisions Standard SWA + Cosmos; sets Cosmos app settings).
2. `scripts/setup-oidc-and-secrets.sh` (Azure OIDC + `ARM_*` / `TFSTATE_*`).
3. `scripts/setup-auth.sh` (Entra External ID app registration + SWA auth settings).
4. `scripts/set-swa-token.sh` then push `apps/star-squad/**` to deploy app + API.

> On networking: the browser -> `/api` hop is public by design (kids open the
> site from anywhere) and is secured by HTTPS + the sign-in token + the
> `authenticated` role on `/api/*`. To keep the **API -> Cosmos** hop on Azure's
> backbone, add a Cosmos private endpoint + VNet-integrated backend (the "Tier B"
> option) — not included here to keep the Free-to-Standard step small.

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
- **State key** is `<environment>-<short_loc>-static-web-app.tfstate`, passed via
  `-backend-config` on `terraform init`, so it never collides with other
  patterns in the same storage account.
