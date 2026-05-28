# baro-terraform

Terraform for deploying `baro-server` to AWS ECS on Fargate.

## Dev stack

The initial dev environment creates:

- VPC with public/private subnets
- NAT Gateway for private ECS tasks
- ECR repositories for four Spring Boot services
- ECS cluster and Fargate services
- Single private RDS PostgreSQL instance
- Public ALB with path-based routing
- CloudWatch log groups
- Secrets Manager entries for service secrets

The dev environment runs `user-service` and prepares `dispatch-service` infrastructure with desired count `0` until its image and secrets are ready.

Available services:

| Key | Module | Port | ALB paths |
| --- | --- | ---: | --- |
| `control` | `control-service` | 8081 | `/control*` |
| `dispatch` | `dispatch-service` | 8082 | `/dispatch*` |
| `relocation` | `relocation-service` | 8083 | `/relocation*` |
| `user` | `user-service` | 8084 | `/auth*`, `/users*`, `/swagger-ui*`, `/api-docs*` |

## Usage

Dev Swagger URLs:

- User: `http://baro-dev-1701378146.ap-northeast-2.elb.amazonaws.com/swagger-ui.html`
- Dispatch: `http://baro-dev-1701378146.ap-northeast-2.elb.amazonaws.com/dispatch/swagger-ui.html`

```bash
cd envs/dev
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

Bootstrap note: when adding a new service, keep its desired count at `0`, apply the infrastructure, push the image and populate secrets, then set its desired count to `1` and apply again.

## User and dispatch bootstrap path

Keep this in `envs/dev/terraform.tfvars`:

```hcl
enabled_services = ["user", "dispatch"]

service_desired_counts = {
  user     = 1
  dispatch = 0
}
```

Then run:

```bash
terraform apply
```

Terraform automatically fills these user-service DB secrets from the RDS instance:

- `baro-dev/user/USER_DB_URL`
- `baro-dev/user/USER_DB_USERNAME`
- `baro-dev/user/USER_DB_PASSWORD`

You only need to populate the user JWT secret manually:

```bash
aws secretsmanager put-secret-value --secret-id baro-dev/user/JWT_SECRET --secret-string 'at-least-32-bytes-secret-value'
```

Terraform also fills these dispatch-service DB secrets from the same RDS instance:

- `baro-dev/dispatch/DISPATCH_DB_URL`
- `baro-dev/dispatch/DISPATCH_DB_USERNAME`
- `baro-dev/dispatch/DISPATCH_DB_PASSWORD`

Dispatch-service reuses `baro-dev/user/JWT_SECRET`, so you do not need a separate dispatch JWT secret.
Populate the Kakao Mobility API key manually in AWS Secrets Manager before setting dispatch desired count to `1`:

```bash
aws secretsmanager put-secret-value --secret-id baro-dev/dispatch/KAKAO_MOBILITY_API_KEY --secret-string '...'
```

Create the four PostgreSQL schemas by running the one-off ECS task after `terraform apply`:

```bash
aws ecs run-task \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --task-definition $(terraform output -raw db_init_task_definition_arn) \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$(terraform output -json private_subnet_ids | jq -r 'join(\",\")')],securityGroups=[$(terraform output -raw ecs_tasks_security_group_id)],assignPublicIp=DISABLED}" \
  --no-cli-pager
```

The task creates:

```sql
CREATE SCHEMA IF NOT EXISTS user_service;
CREATE SCHEMA IF NOT EXISTS dispatch_service;
CREATE SCHEMA IF NOT EXISTS relocation_service;
CREATE SCHEMA IF NOT EXISTS control_service;
```

## RDS layout

This project starts with one private PostgreSQL RDS instance, not four DB instances.

Recommended logical split inside the single DB:

```sql
CREATE SCHEMA user_service;
CREATE SCHEMA dispatch_service;
CREATE SCHEMA relocation_service;
CREATE SCHEMA control_service;
```

Then each service can use the same RDS endpoint with a different schema:

```text
jdbc:postgresql://RDS_ENDPOINT:5432/baro?currentSchema=user_service
jdbc:postgresql://RDS_ENDPOINT:5432/baro?currentSchema=dispatch_service
```

This is different from an Aurora/RDS cluster with multiple DB instances. A multi-instance DB cluster is mainly for high availability/read scaling and costs more. For dev and early deployment, one RDS instance with schemas is simpler.

After the dispatch image is pushed and secrets are populated, set:

```hcl
service_desired_counts = {
  user     = 1
  dispatch = 1
}
```

and apply again.

Local validation before apply:

```bash
terraform fmt -recursive
terraform init -backend=false
terraform validate
terraform plan
```

For remote state, create the S3 bucket/DynamoDB table first and initialize with:

```bash
terraform init -backend-config=backend.hcl
```

Dev currently uses this remote backend:

```hcl
bucket         = "baro-dev-terraform-state-379992420279"
key            = "baro/dev/terraform.tfstate"
region         = "ap-northeast-2"
dynamodb_table = "baro-dev-terraform-locks"
encrypt        = true
```

## Required secret values

For user-service and dispatch-service, Terraform fills the DB secrets from RDS.
Populate app-level secrets manually:

```bash
aws secretsmanager put-secret-value --secret-id baro-dev/user/JWT_SECRET --secret-string '...'
aws secretsmanager put-secret-value --secret-id baro-dev/dispatch/KAKAO_MOBILITY_API_KEY --secret-string '...'
```

If you do not want to use local AWS CLI, put these values in AWS Console:

```text
AWS Console → Secrets Manager → Secrets → secret name → Retrieve/Update secret value
```

See `terraform output secret_names` for the created service secrets.

## CI/CD prerequisites

The `baro-server` repository contains `.github/workflows/deploy-dev-ecs.yml`.
For now it deploys `user-service` and `dispatch-service`.
It expects this GitHub Actions secret:

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

The IAM user needs permissions for:

- ECR login/push for `baro-dev-*-service` repositories
- ECS `UpdateService`/`DescribeServices` on the `baro-dev` cluster

GitHub OIDC is recommended later, but access keys are simpler for the first dev deployment.

## Terraform GitHub Actions

This repository contains `.github/workflows/terraform-dev.yml`.

- Pull requests run `terraform fmt`, `init`, `validate`, and `plan`.
- Pushes to `main` run the same checks and `terraform plan`.
- Manual runs are available via `workflow_dispatch` with `plan`, `apply`, and `destroy` actions.
- Manual runs can set `user_desired_count` and `dispatch_desired_count` without local Terraform commands.
- Manual `destroy` requires `confirm_destroy=destroy-dev`.

Configure these repository secrets in `baro-terraform`:

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

The workflow uses the dev S3 backend configured in `envs/dev/backend.hcl.example`.
