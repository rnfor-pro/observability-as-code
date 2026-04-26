# observability-as-code


Below is the workflow I would use for your first team: **Connect**.

The big idea is:

```text id="6iqijv"
dashboards/connect/... = dashboard JSON lives here
envs/nonprod/connect-dashboards.tf = tells Terraform which Connect dashboards to create in non-prod
envs/prod/connect-dashboards.tf = tells Terraform which Connect dashboards to create in prod
modules/... = reusable building blocks so you do not repeat code
```

Observe’s Terraform provider supports `observe_dashboard`, and the dashboard body is managed through JSON fields like `stages`, `layout`, `parameters`, and `parameter_values`. The provider also supports importing an existing dashboard by ID. ([GitHub][1])

---

# 1. Create the GitHub repo locally

From your Mac terminal:

```bash id="x62diu"
mkdir observe-oac
cd observe-oac

git init -b main
```

Create the folders:

```bash id="yk7j92"
mkdir -p .github
mkdir -p envs/nonprod
mkdir -p envs/prod
mkdir -p modules/connect_rbac
mkdir -p modules/observe_dashboard
mkdir -p dashboards/connect
mkdir -p tools/export-dashboard
mkdir -p docs
```

Create basic files:

```bash id="xwd2bh"
touch README.md
touch .gitignore
touch versions.tf
touch .github/CODEOWNERS
touch envs/nonprod/providers.tf
touch envs/nonprod/main.tf
touch envs/nonprod/locals.tf
touch envs/nonprod/connect-rbac.tf
touch envs/nonprod/connect-dashboards.tf

touch envs/prod/providers.tf
touch envs/prod/main.tf
touch envs/prod/locals.tf
touch envs/prod/connect-rbac.tf
touch envs/prod/connect-dashboards.tf
```

Your repo should now look like this:

```text id="bpy6d8"
observe-oac/
├── README.md
├── .gitignore
├── versions.tf
├── .github/
│   └── CODEOWNERS
├── envs/
│   ├── nonprod/
│   │   ├── providers.tf
│   │   ├── main.tf
│   │   ├── locals.tf
│   │   ├── connect-rbac.tf
│   │   └── connect-dashboards.tf
│   └── prod/
│       ├── providers.tf
│       ├── main.tf
│       ├── locals.tf
│       ├── connect-rbac.tf
│       └── connect-dashboards.tf
├── modules/
│   ├── connect_rbac/
│   └── observe_dashboard/
├── dashboards/
│   └── connect/
├── tools/
│   └── export-dashboard/
└── docs/
```

---

# 2. Add `.gitignore`

```bash id="vl93em"
cat > .gitignore <<'EOF'
.terraform/
*.tfstate
*.tfstate.*
*.tfvars
crash.log
crash.*.log
override.tf
override.tf.json
*_override.tf
*_override.tf.json
.DS_Store
EOF
```

Do **not** commit `.tfvars` files because they usually contain secrets.

---

# 3. Add the provider version

## `versions.tf`

```bash id="7p5wq8"
cat > versions.tf <<'EOF'
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    observe = {
      source  = "observeinc/observe"
      version = "~> 0.14"
    }
  }
}
EOF
```

The current Observe provider docs show `source = "observeinc/observe"` and version `~> 0.14`. ([GitHub][2])

Commit this first:

```bash id="iwoxd3"
git add .
git commit -m "Initial Observe OaC repo structure"
```

---

# 4. Provider files for non-prod and prod

## `envs/nonprod/providers.tf`

```bash id="39pa4e"
cat > envs/nonprod/providers.tf <<'EOF'
provider "observe" {
  # Values come from Terraform Cloud environment variables:
  # OBSERVE_CUSTOMER
  # OBSERVE_DOMAIN
  # OBSERVE_API_TOKEN
}
EOF
```

## `envs/prod/providers.tf`

```bash id="x0n7zt"
cat > envs/prod/providers.tf <<'EOF'
provider "observe" {
  # Values come from Terraform Cloud environment variables:
  # OBSERVE_CUSTOMER
  # OBSERVE_DOMAIN
  # OBSERVE_API_TOKEN
}
EOF
```

Observe supports provider configuration through environment variables such as `OBSERVE_CUSTOMER`, `OBSERVE_API_TOKEN`, and `OBSERVE_DOMAIN`. ([GitHub][2])

---

# 5. Add environment locals

## `envs/nonprod/locals.tf`

```bash id="q8oiyf"
cat > envs/nonprod/locals.tf <<'EOF'
locals {
  environment = "nonprod"
  team_name   = "connect"

  default_tags = {
    managed_by  = "terraform"
    environment = "nonprod"
    team        = "connect"
  }
}
EOF
```

## `envs/prod/locals.tf`

```bash id="4nlsxp"
cat > envs/prod/locals.tf <<'EOF'
locals {
  environment = "prod"
  team_name   = "connect"

  default_tags = {
    managed_by  = "terraform"
    environment = "prod"
    team        = "connect"
  }
}
EOF
```

---

# 6. Add default workspace lookup

## `envs/nonprod/main.tf`

```bash id="bf783l"
cat > envs/nonprod/main.tf <<'EOF'
data "observe_workspace" "default" {
  name = "Default"
}
EOF
```

## `envs/prod/main.tf`

```bash id="y4wlic"
cat > envs/prod/main.tf <<'EOF'
data "observe_workspace" "default" {
  name = "Default"
}
EOF
```

---

# 7. Create the Connect RBAC module

This module creates two groups:

```text id="vgfjwm"
nonprod-connect-dashboard-viewers
nonprod-connect-dashboard-editors
prod-connect-dashboard-viewers
prod-connect-dashboard-editors
```

Observe supports managing RBAC groups in Terraform with `observe_rbac_group`. ([GitHub][3])

## `modules/connect_rbac/variables.tf`

```bash id="sc4gxy"
cat > modules/connect_rbac/variables.tf <<'EOF'
variable "environment" {
  type = string
}

variable "team_name" {
  type = string
}
EOF
```

## `modules/connect_rbac/main.tf`

```bash id="03jwzm"
cat > modules/connect_rbac/main.tf <<'EOF'
resource "observe_rbac_group" "dashboard_viewers" {
  name        = "${var.environment}-${var.team_name}-dashboard-viewers"
  description = "View-only access to ${var.team_name} dashboards in ${var.environment}."
}

resource "observe_rbac_group" "dashboard_editors" {
  name        = "${var.environment}-${var.team_name}-dashboard-editors"
  description = "Editor access to ${var.team_name} dashboards in ${var.environment}."
}
EOF
```

## `modules/connect_rbac/outputs.tf`

```bash id="n0v2rn"
cat > modules/connect_rbac/outputs.tf <<'EOF'
output "viewer_group_oid" {
  value = observe_rbac_group.dashboard_viewers.oid
}

output "editor_group_oid" {
  value = observe_rbac_group.dashboard_editors.oid
}
EOF
```

---

# 8. Call the RBAC module in non-prod and prod

## `envs/nonprod/connect-rbac.tf`

```bash id="b6dt2p"
cat > envs/nonprod/connect-rbac.tf <<'EOF'
module "connect_rbac" {
  source = "../../modules/connect_rbac"

  environment = local.environment
  team_name   = local.team_name
}
EOF
```

## `envs/prod/connect-rbac.tf`

```bash id="htz5wa"
cat > envs/prod/connect-rbac.tf <<'EOF'
module "connect_rbac" {
  source = "../../modules/connect_rbac"

  environment = local.environment
  team_name   = local.team_name
}
EOF
```

Think of this module call like a function call:

```hcl id="m4tgd1"
module "connect_rbac" {
  source = "../../modules/connect_rbac"

  environment = "nonprod"
  team_name   = "connect"
}
```

Terraform goes into `modules/connect_rbac`, uses those files, and creates the groups.

---

# 9. Create the dashboard module

This module creates one Observe dashboard and assigns permissions to the Connect groups.

Observe’s `observe_dashboard` resource requires a dashboard `name` and `stages`, while `layout`, `parameters`, and `parameter_values` are optional JSON fields. ([GitHub][1])

## `modules/observe_dashboard/variables.tf`

```bash id="payp9u"
cat > modules/observe_dashboard/variables.tf <<'EOF'
variable "name" {
  type = string
}

variable "description" {
  type    = string
  default = null
}

variable "workspace_oid" {
  type = string
}

variable "stages_file" {
  type = string
}

variable "layout_file" {
  type    = string
  default = null
}

variable "parameters_file" {
  type    = string
  default = null
}

variable "parameter_values_file" {
  type    = string
  default = null
}

variable "entity_tags" {
  type    = map(string)
  default = {}
}

variable "viewer_group_oid" {
  type = string
}

variable "editor_group_oid" {
  type = string
}
EOF
```

## `modules/observe_dashboard/main.tf`

```bash id="jc8i7i"
cat > modules/observe_dashboard/main.tf <<'EOF'
resource "observe_dashboard" "this" {
  name        = var.name
  description = var.description
  workspace   = var.workspace_oid

  stages = file(var.stages_file)

  layout = var.layout_file == null ? null : file(var.layout_file)

  parameters = var.parameters_file == null ? null : file(var.parameters_file)

  parameter_values = var.parameter_values_file == null ? null : file(var.parameter_values_file)

  entity_tags = var.entity_tags
}

resource "observe_resource_grants" "this" {
  oid = observe_dashboard.this.oid

  grant {
    subject = var.viewer_group_oid
    role    = "dashboard_viewer"
  }

  grant {
    subject = var.editor_group_oid
    role    = "dashboard_editor"
  }
}
EOF
```

Observe’s `observe_resource_grants` is authoritative, meaning Terraform manages the complete set of grants for that resource. If you use it, review plans carefully because Terraform will replace dashboard grants with exactly what your code says. ([GitHub][4])

## `modules/observe_dashboard/outputs.tf`

```bash id="469brc"
cat > modules/observe_dashboard/outputs.tf <<'EOF'
output "dashboard_oid" {
  value = observe_dashboard.this.oid
}

output "dashboard_id" {
  value = observe_dashboard.this.id
}
EOF
```

Commit the module work:

```bash id="7whdkl"
git add .
git commit -m "Add Connect RBAC and dashboard modules"
```

---

# 10. Create Terraform Cloud workspaces

Create two HCP Terraform/Terraform Cloud workspaces:

```text id="i7mfxe"
observe-oac-nonprod
observe-oac-prod
```

Use this setup:

| Workspace             | Working Directory | Branch | Auto Apply   |
| --------------------- | ----------------- | ------ | ------------ |
| `observe-oac-nonprod` | `envs/nonprod`    | `main` | Optional yes |
| `observe-oac-prod`    | `envs/prod`       | `main` | No at first  |

HCP Terraform can run speculative plans for pull requests and can also trigger runs from VCS changes. Workspaces can be configured to trigger only when certain directories change. ([HashiCorp Developer][5])

Set these as **sensitive environment variables** in each Terraform Cloud workspace.

## Non-prod workspace

```text id="tpm0gg"
OBSERVE_CUSTOMER=your_nonprod_customer_id
OBSERVE_DOMAIN=observeinc.com
OBSERVE_API_TOKEN=your_nonprod_api_token
```

## Prod workspace

```text id="oacddo"
OBSERVE_CUSTOMER=your_prod_customer_id
OBSERVE_DOMAIN=observeinc.com
OBSERVE_API_TOKEN=your_prod_api_token
```

---

# 11. First local validation

From your repo root:

```bash id="oozr1e"
cd envs/nonprod
terraform init
terraform validate
```

Then:

```bash id="yyb1sd"
cd ../prod
terraform init
terraform validate
```

Go back to repo root:

```bash id="sjaolk"
cd ../..
```

Commit:

```bash id="8jmk1h"
git add .
git commit -m "Add nonprod and prod Observe environment configuration"
```

Push to GitHub:

```bash id="qq4r6r"
git remote add origin git@github.com:YOUR_ORG/observe-oac.git
git push -u origin main
```

---

# 12. Dashboard workflow: new dashboard for Connect

This is the part your team needs to understand clearly.

There are **two safe ways** to onboard a new dashboard.

---

## Option A — Recommended for your first dashboard

Use this when someone manually created a dashboard in **Observe non-prod** and you want Terraform to manage that exact dashboard.

Workflow:

```text id="ys9sjs"
1. Build dashboard manually in Observe non-prod.
2. Get the dashboard ID.
3. Export/read dashboard JSON using Terraform data source.
4. Save JSON into dashboards/connect/<dashboard-name>/.
5. Add one module block in envs/nonprod/connect-dashboards.tf.
6. Add one import block in envs/nonprod/imports.tf.
7. Open PR.
8. Terraform Cloud plan shows import + permission changes.
9. Merge PR.
10. Terraform Cloud imports dashboard into state.
11. Remove the import block in a cleanup PR.
12. Promote same dashboard to prod by adding same module block in envs/prod/connect-dashboards.tf.
```

---

# 13. Create export helper

Because Observe dashboards in Terraform are made of JSON fields, the cleanest way is to use the `observe_dashboard` data source to read an existing dashboard. The provider data source exposes `stages`, `layout`, `parameters`, and `parameter_values`. ([GitHub][6])

Create helper files.

## `tools/export-dashboard/versions.tf`

```bash id="mwryy9"
cat > tools/export-dashboard/versions.tf <<'EOF'
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    observe = {
      source  = "observeinc/observe"
      version = "~> 0.14"
    }
  }
}
EOF
```

## `tools/export-dashboard/main.tf`

```bash id="1f99ui"
cat > tools/export-dashboard/main.tf <<'EOF'
variable "dashboard_id" {
  type = string
}

provider "observe" {}

data "observe_dashboard" "selected" {
  id = var.dashboard_id
}

output "name" {
  value = data.observe_dashboard.selected.name
}

output "description" {
  value = data.observe_dashboard.selected.description
}

output "stages" {
  value = data.observe_dashboard.selected.stages
}

output "layout" {
  value = data.observe_dashboard.selected.layout
}

output "parameters" {
  value = data.observe_dashboard.selected.parameters
}

output "parameter_values" {
  value = data.observe_dashboard.selected.parameter_values
}
EOF
```

Commit:

```bash id="c0t2kn"
git add .
git commit -m "Add Observe dashboard export helper"
```

---

# 14. Export a manually created dashboard

Assume you manually created this dashboard in Observe non-prod:

```text id="0c2m4k"
Connect - Application Health
```

Create the dashboard folder:

```bash id="tf4t99"
mkdir -p dashboards/connect/application-health
```

Export credentials locally for non-prod:

```bash id="u8c4n1"
export OBSERVE_CUSTOMER="your_nonprod_customer_id"
export OBSERVE_DOMAIN="observeinc.com"
export OBSERVE_API_TOKEN="your_nonprod_api_token"
```

Go into the helper:

```bash id="8weqdm"
cd tools/export-dashboard
terraform init
```

Run the helper. Replace `123456789` with the actual Observe dashboard ID:

```bash id="r85k05"
terraform apply -auto-approve -var="dashboard_id=123456789"
```

Now write the dashboard fields into your repo:

```bash id="xa2p4x"
terraform output -raw stages | jq . > ../../dashboards/connect/application-health/stages.json
terraform output -raw layout | jq . > ../../dashboards/connect/application-health/layout.json
terraform output -raw parameters | jq . > ../../dashboards/connect/application-health/parameters.json
terraform output -raw parameter_values | jq . > ../../dashboards/connect/application-health/parameter_values.json
```

Go back to repo root:

```bash id="ntnoif"
cd ../..
```

Check the files:

```bash id="umw3n8"
ls -la dashboards/connect/application-health
```

You should see:

```text id="j0y7pq"
stages.json
layout.json
parameters.json
parameter_values.json
```

---

# 15. Add the dashboard to non-prod Terraform

Open:

```text id="ym2obp"
envs/nonprod/connect-dashboards.tf
```

Add this:

```bash id="cyg2a3"
cat > envs/nonprod/connect-dashboards.tf <<'EOF'
module "connect_application_health_dashboard" {
  source = "../../modules/observe_dashboard"

  name        = "[NONPROD] Connect - Application Health"
  description = "Application health dashboard for the Connect team."

  workspace_oid = data.observe_workspace.default.oid

  stages_file           = "${path.root}/../../dashboards/connect/application-health/stages.json"
  layout_file           = "${path.root}/../../dashboards/connect/application-health/layout.json"
  parameters_file       = "${path.root}/../../dashboards/connect/application-health/parameters.json"
  parameter_values_file = "${path.root}/../../dashboards/connect/application-health/parameter_values.json"

  viewer_group_oid = module.connect_rbac.viewer_group_oid
  editor_group_oid = module.connect_rbac.editor_group_oid

  entity_tags = merge(local.default_tags, {
    dashboard = "application-health"
    service   = "connect"
  })
}
EOF
```

This module block means:

```text id="f43u24"
Create or manage one Observe dashboard.
Use the JSON files from dashboards/connect/application-health.
Give Connect viewers view access.
Give Connect editors edit access.
Tag the dashboard as team=connect and environment=nonprod.
```

---

# 16. Import the manually created non-prod dashboard

Because you already created the dashboard manually in Observe non-prod, Terraform must import it into state. If you skip this, Terraform may try to create a second dashboard.

Create:

```bash id="ji79ed"
cat > envs/nonprod/imports.tf <<'EOF'
import {
  to = module.connect_application_health_dashboard.observe_dashboard.this
  id = "123456789"
}
EOF
```

Replace `123456789` with the real dashboard ID.

Terraform supports import blocks for bringing existing infrastructure under Terraform management, and the destination address in the import block must match a real resource block. ([HashiCorp Developer][7])

Validate:

```bash id="dvd485"
cd envs/nonprod
terraform init
terraform validate
terraform plan
cd ../..
```

Commit and push:

```bash id="0e8xye"
git checkout -b feature/connect-application-health-dashboard
git add .
git commit -m "Add Connect application health dashboard"
git push -u origin feature/connect-application-health-dashboard
```

Open a PR to `main`.

Terraform Cloud should run a speculative plan. HCP Terraform posts PR plan links/statuses when configured for VCS-driven PR plans. ([HashiCorp Developer][5])

The plan should show something like:

```text id="s7aozr"
module.connect_application_health_dashboard.observe_dashboard.this will be imported
module.connect_application_health_dashboard.observe_resource_grants.this will be created
```

Review carefully because `observe_resource_grants` will set permissions exactly to what your code says. ([GitHub][4])

After approval, merge the PR.

---

# 17. Cleanup after successful import

After Terraform Cloud successfully applies non-prod, remove the import block.

```bash id="17o57w"
git checkout main
git pull

git checkout -b cleanup/remove-connect-dashboard-import
rm envs/nonprod/imports.tf

git add .
git commit -m "Remove completed Connect dashboard import block"
git push -u origin cleanup/remove-connect-dashboard-import
```

Open PR, let Terraform Cloud plan.

The plan should show:

```text id="h3r2q1"
No changes
```

Merge it.

---

# 18. Promote the same dashboard to prod

Now you want Terraform to create the prod version.

Open:

```text id="3yawdm"
envs/prod/connect-dashboards.tf
```

Add:

```bash id="34fhq6"
cat > envs/prod/connect-dashboards.tf <<'EOF'
module "connect_application_health_dashboard" {
  source = "../../modules/observe_dashboard"

  name        = "[PROD] Connect - Application Health"
  description = "Application health dashboard for the Connect team."

  workspace_oid = data.observe_workspace.default.oid

  stages_file           = "${path.root}/../../dashboards/connect/application-health/stages.json"
  layout_file           = "${path.root}/../../dashboards/connect/application-health/layout.json"
  parameters_file       = "${path.root}/../../dashboards/connect/application-health/parameters.json"
  parameter_values_file = "${path.root}/../../dashboards/connect/application-health/parameter_values.json"

  viewer_group_oid = module.connect_rbac.viewer_group_oid
  editor_group_oid = module.connect_rbac.editor_group_oid

  entity_tags = merge(local.default_tags, {
    dashboard = "application-health"
    service   = "connect"
  })
}
EOF
```

Create branch:

```bash id="lbbdx7"
git checkout main
git pull

git checkout -b promote/connect-application-health-dashboard-prod
git add .
git commit -m "Promote Connect application health dashboard to prod"
git push -u origin promote/connect-application-health-dashboard-prod
```

Open PR.

For prod, I recommend manual approval in Terraform Cloud. The prod plan should show:

```text id="c5wgjg"
module.connect_application_health_dashboard.observe_dashboard.this will be created
module.connect_application_health_dashboard.observe_resource_grants.this will be created
```

Merge after approval.

---

# 19. Workflow for modifying an existing dashboard

This is the day-to-day workflow.

Example: You want to modify:

```text id="c37n9m"
[NONPROD] Connect - Application Health
```

## Step 1: Make the change manually in Observe non-prod

Go into Observe non-prod, edit the dashboard, add/remove cards, update queries, update parameters, and save.

## Step 2: Export the latest dashboard JSON again

```bash id="xvqrnh"
export OBSERVE_CUSTOMER="your_nonprod_customer_id"
export OBSERVE_DOMAIN="observeinc.com"
export OBSERVE_API_TOKEN="your_nonprod_api_token"

cd tools/export-dashboard
terraform apply -auto-approve -var="dashboard_id=123456789"

terraform output -raw stages | jq . > ../../dashboards/connect/application-health/stages.json
terraform output -raw layout | jq . > ../../dashboards/connect/application-health/layout.json
terraform output -raw parameters | jq . > ../../dashboards/connect/application-health/parameters.json
terraform output -raw parameter_values | jq . > ../../dashboards/connect/application-health/parameter_values.json

cd ../..
```

## Step 3: Review what changed

```bash id="zcc3my"
git diff dashboards/connect/application-health
```

## Step 4: Create branch and commit

```bash id="lqazw6"
git checkout -b update/connect-application-health-dashboard

git add dashboards/connect/application-health
git commit -m "Update Connect application health dashboard"
git push -u origin update/connect-application-health-dashboard
```

## Step 5: Open PR

Terraform Cloud should plan against non-prod first.

The plan should show an update to:

```text id="kr6xm3"
module.connect_application_health_dashboard.observe_dashboard.this
```

## Step 6: Merge to non-prod

After merge, Terraform applies the change to non-prod.

## Step 7: Promote to prod

If the same dashboard JSON is already used by prod, then prod may also plan a change because the shared JSON files changed.

That is important.

Because both environments reference:

```text id="5kn6mq"
dashboards/connect/application-health/stages.json
dashboards/connect/application-health/layout.json
dashboards/connect/application-health/parameters.json
dashboards/connect/application-health/parameter_values.json
```

A change to those files can affect both non-prod and prod.

For stronger control, you can separate environment dashboard definitions like this:

```text id="9ggjbd"
dashboards/
└── connect/
    ├── nonprod/
    │   └── application-health/
    └── prod/
        └── application-health/
```

But for now, I would keep one shared dashboard definition and use Terraform Cloud approval to control prod.

---

# 20. Workflow for creating a second Connect dashboard

Example new dashboard:

```text id="y6nhd4"
Connect - API Latency
```

## Step 1: Create dashboard in Observe non-prod manually

Build and test it.

## Step 2: Create folder

```bash id="2ac0yy"
mkdir -p dashboards/connect/api-latency
```

## Step 3: Export it

```bash id="hw5h7p"
export OBSERVE_CUSTOMER="your_nonprod_customer_id"
export OBSERVE_DOMAIN="observeinc.com"
export OBSERVE_API_TOKEN="your_nonprod_api_token"

cd tools/export-dashboard
terraform apply -auto-approve -var="dashboard_id=987654321"

terraform output -raw stages | jq . > ../../dashboards/connect/api-latency/stages.json
terraform output -raw layout | jq . > ../../dashboards/connect/api-latency/layout.json
terraform output -raw parameters | jq . > ../../dashboards/connect/api-latency/parameters.json
terraform output -raw parameter_values | jq . > ../../dashboards/connect/api-latency/parameter_values.json

cd ../..
```

## Step 4: Add a second module block to non-prod

Open:

```text id="089k7l"
envs/nonprod/connect-dashboards.tf
```

Add this **below** the first dashboard:

```hcl id="q61dka"
module "connect_api_latency_dashboard" {
  source = "../../modules/observe_dashboard"

  name        = "[NONPROD] Connect - API Latency"
  description = "API latency dashboard for the Connect team."

  workspace_oid = data.observe_workspace.default.oid

  stages_file           = "${path.root}/../../dashboards/connect/api-latency/stages.json"
  layout_file           = "${path.root}/../../dashboards/connect/api-latency/layout.json"
  parameters_file       = "${path.root}/../../dashboards/connect/api-latency/parameters.json"
  parameter_values_file = "${path.root}/../../dashboards/connect/api-latency/parameter_values.json"

  viewer_group_oid = module.connect_rbac.viewer_group_oid
  editor_group_oid = module.connect_rbac.editor_group_oid

  entity_tags = merge(local.default_tags, {
    dashboard = "api-latency"
    service   = "connect"
  })
}
```

## Step 5: Add import block for the manual dashboard

```bash id="9u9c67"
cat > envs/nonprod/imports.tf <<'EOF'
import {
  to = module.connect_api_latency_dashboard.observe_dashboard.this
  id = "987654321"
}
EOF
```

## Step 6: Validate and plan

```bash id="psx6c2"
cd envs/nonprod
terraform init
terraform validate
terraform plan
cd ../..
```

## Step 7: Commit and PR

```bash id="0a2y51"
git checkout -b feature/connect-api-latency-dashboard

git add .
git commit -m "Add Connect API latency dashboard"
git push -u origin feature/connect-api-latency-dashboard
```

Open PR.

After successful apply, remove `envs/nonprod/imports.tf` in a cleanup PR.

## Step 8: Promote to prod

Add the same module block in:

```text id="3xipsc"
envs/prod/connect-dashboards.tf
```

But change the name:

```hcl id="qxk0tk"
name = "[PROD] Connect - API Latency"
```

Then:

```bash id="yiirf7"
git checkout main
git pull

git checkout -b promote/connect-api-latency-dashboard-prod
git add .
git commit -m "Promote Connect API latency dashboard to prod"
git push -u origin promote/connect-api-latency-dashboard-prod
```

---

# 21. What exactly changes after manually creating/exporting a dashboard?

For a **new dashboard**, you change these files:

```text id="1i6sx8"
1. Add a new dashboard folder:
   dashboards/connect/<dashboard-slug>/

2. Add exported JSON files:
   dashboards/connect/<dashboard-slug>/stages.json
   dashboards/connect/<dashboard-slug>/layout.json
   dashboards/connect/<dashboard-slug>/parameters.json
   dashboards/connect/<dashboard-slug>/parameter_values.json

3. Add one module block:
   envs/nonprod/connect-dashboards.tf

4. Add one temporary import block:
   envs/nonprod/imports.tf

5. Later, add one prod module block:
   envs/prod/connect-dashboards.tf
```

For an **existing dashboard modification**, usually you only change:

```text id="isail8"
dashboards/connect/<dashboard-slug>/stages.json
dashboards/connect/<dashboard-slug>/layout.json
dashboards/connect/<dashboard-slug>/parameters.json
dashboards/connect/<dashboard-slug>/parameter_values.json
```

You do **not** add a new module block if the dashboard already exists in Terraform.

---

# 22. Simple module rule

Tell your team this:

```text id="bpm5rv"
A module is just a reusable template.
A module block is how we create one real dashboard from that template.
One dashboard = one module block.
The JSON files define the dashboard body.
The module block defines the dashboard name, team, environment, permissions, and tags.
```

Example:

```hcl id="c1d8f2"
module "connect_application_health_dashboard" {
  source = "../../modules/observe_dashboard"

  name = "[NONPROD] Connect - Application Health"

  stages_file = "${path.root}/../../dashboards/connect/application-health/stages.json"

  viewer_group_oid = module.connect_rbac.viewer_group_oid
  editor_group_oid = module.connect_rbac.editor_group_oid
}
```

That is basically saying:

```text id="r6hq4n"
Use the dashboard module.
Call this dashboard Connect Application Health.
Use this exported JSON file.
Give Connect viewers view access.
Give Connect editors edit access.
```

---

# 23. Recommended dashboard naming convention

Use this:

```text id="gbwweg"
[NONPROD] Connect - Application Health
[NONPROD] Connect - API Latency
[NONPROD] Connect - Error Analysis

[PROD] Connect - Application Health
[PROD] Connect - API Latency
[PROD] Connect - Error Analysis
```

Folder slugs:

```text id="t1fwyk"
application-health
api-latency
error-analysis
```

Module names:

```text id="bfycnm"
connect_application_health_dashboard
connect_api_latency_dashboard
connect_error_analysis_dashboard
```

---

# 24. Suggested first Connect dashboards

Start with these three:

```text id="yo5ux3"
Connect - Application Health
Connect - API Latency
Connect - Error Analysis
```

## Connect - Application Health

Good for managers and application owners.

Cards:

```text id="ckam4b"
Request volume
Successful requests
Failed requests
Error rate
Top failing routes
Top failing services
Recent critical errors
```

## Connect - API Latency

Good for troubleshooting performance.

Cards:

```text id="x5u6sq"
p50 latency
p95 latency
p99 latency
Slowest endpoints
Latency by service
Latency trend over time
```

## Connect - Error Analysis

Good for developers.

Cards:

```text id="qkxhxo"
Error count by service
Error count by route
Error message breakdown
Recent error logs
Trace or request correlation fields
Top exception types
```

---

# 25. CODEOWNERS

## `.github/CODEOWNERS`

```bash id="hos9wk"
cat > .github/CODEOWNERS <<'EOF'
/modules/ @observe-admins
/envs/prod/ @observe-admins
/envs/nonprod/ @observe-admins
/dashboards/connect/ @connect-team @observe-admins
EOF
```

Commit:

```bash id="kvok9d"
git add .
git commit -m "Add CODEOWNERS for Observe OaC"
```

---

# 26. Daily commands cheat sheet

## Create a feature branch

```bash id="fx1k3e"
git checkout main
git pull
git checkout -b feature/connect-new-dashboard
```

## Check changes

```bash id="v888qi"
git status
git diff
```

## Validate non-prod

```bash id="1v9uoz"
cd envs/nonprod
terraform init
terraform validate
terraform plan
cd ../..
```

## Commit

```bash id="tagotn"
git add .
git commit -m "Add Connect dashboard"
git push -u origin feature/connect-new-dashboard
```

## Update an existing dashboard JSON

```bash id="5l0vrk"
git checkout main
git pull
git checkout -b update/connect-application-health-dashboard

cd tools/export-dashboard
terraform apply -auto-approve -var="dashboard_id=123456789"

terraform output -raw stages | jq . > ../../dashboards/connect/application-health/stages.json
terraform output -raw layout | jq . > ../../dashboards/connect/application-health/layout.json
terraform output -raw parameters | jq . > ../../dashboards/connect/application-health/parameters.json
terraform output -raw parameter_values | jq . > ../../dashboards/connect/application-health/parameter_values.json

cd ../..

git diff
git add dashboards/connect/application-health
git commit -m "Update Connect application health dashboard"
git push -u origin update/connect-application-health-dashboard
```

---

# 27. Very important operating rule

Use this rule from day one:

```text id="92fiue"
Manual dashboard changes are allowed in Observe non-prod only.
Production dashboards must be created or updated only by Terraform.
```

Also:

```text id="4kfdn7"
If someone manually changes a Terraform-managed dashboard in Observe, Terraform will eventually overwrite that change unless the dashboard JSON is exported and committed back to Git.
```

That one sentence will save your team a lot of confusion.

[1]: https://raw.githubusercontent.com/observeinc/terraform-provider-observe/master/docs/resources/dashboard.md "raw.githubusercontent.com"
[2]: https://raw.githubusercontent.com/observeinc/terraform-provider-observe/master/docs/index.md "raw.githubusercontent.com"
[3]: https://raw.githubusercontent.com/observeinc/terraform-provider-observe/master/docs/resources/rbac_group.md "raw.githubusercontent.com"
[4]: https://raw.githubusercontent.com/observeinc/terraform-provider-observe/master/docs/resources/resource_grants.md "raw.githubusercontent.com"
[5]: https://developer.hashicorp.com/terraform/cloud-docs/workspaces/run/ui "UI and VCS-driven run workflow in HCP Terraform | Terraform | HashiCorp Developer"
[6]: https://raw.githubusercontent.com/observeinc/terraform-provider-observe/master/docs/data-sources/dashboard.md "raw.githubusercontent.com"
[7]: https://developer.hashicorp.com/terraform/language/import?utm_source=chatgpt.com "Import resources overview | Terraform"

