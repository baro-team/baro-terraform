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

The dev environment starts with `user-service` only. Add the other services later by changing `enabled_services`.

Available services:

| Key | Module | Port | ALB paths |
| --- | --- | ---: | --- |
| `control` | `control-service` | 8081 | `/control*` |
| `dispatch` | `dispatch-service` | 8082 | `/dispatch*` |
| `relocation` | `relocation-service` | 8083 | `/relocation*` |
| `user` | `user-service` | 8084 | `/auth*`, `/users*`, `/swagger-ui*`, `/api-docs*` |

## Usage

```bash
cd envs/dev
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

Bootstrap note: on the very first apply, ECR images and secret values may not exist yet.
If you want to avoid failing ECS tasks during bootstrap, set `service_desired_count = 0`,
apply the infrastructure, push images and populate secrets, then set it back to `1` and apply again.

## User-service first path

Keep this in `envs/dev/terraform.tfvars`:

```hcl
enabled_services      = ["user"]
service_desired_count = 0
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

After the image is pushed, set:

```hcl
service_desired_count = 1
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

For the initial user-service deployment, Terraform fills the DB secrets from RDS.
Populate only the JWT secret manually:

```bash
aws secretsmanager put-secret-value --secret-id baro-dev/user/JWT_SECRET --secret-string '...'
```

See `terraform output secret_names` for the created service secrets.

## CI/CD prerequisites

The `baro-server` repository contains `.github/workflows/deploy-dev-ecs.yml`.
For now it deploys `user-service` only.
It expects this GitHub Actions secret:

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

The IAM user needs permissions for:

- ECR login/push for `baro-dev-*-service` repositories
- ECS `UpdateService`/`DescribeServices` on the `baro-dev` cluster

GitHub OIDC is recommended later, but access keys are simpler for the first dev deployment.
