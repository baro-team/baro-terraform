# baro-terraform

`baro-server`를 AWS ECS on Fargate로 배포하기 위한 Terraform 저장소입니다.

## Dev stack

dev 환경은 lifecycle에 따라 `shared`와 `runtime` 두 Terraform root module/state로 분리되어 있습니다.

```text
baro-terraform/
├── envs/
│   ├── dev-shared/          # 오래 유지할 기반 리소스
│   │   ├── network.tf       # VPC, public/private subnets, IGW, public route table
│   │   ├── ecr.tf           # ECR repositories and lifecycle policies
│   │   ├── secrets.tf       # service-level Secrets Manager placeholders
│   │   ├── outputs.tf       # runtime에서 참조하는 shared outputs
│   │   └── backend.hcl.example
│   └── dev-runtime/         # 비용 절감을 위해 자주 올리고 내리는 실행 리소스
│       ├── remote_state.tf  # dev-shared state 참조
│       ├── network.tf       # NAT Gateway, EIP, private route table
│       ├── alb.tf           # ALB, listener, target groups, listener rules
│       ├── ecs.tf           # ECS cluster, task definitions, services, logs
│       ├── rds.tf           # RDS, DB secrets, db-init task
│       ├── iam.tf           # ECS task roles
│       ├── security_groups.tf
│       └── backend.hcl.example
└── .github/workflows/terraform-dev.yml
```

`dev-shared`가 관리합니다.

- VPC with public/private subnets
- Internet Gateway and public route table
- ECR repositories
- ECR lifecycle policies
- Secrets Manager service placeholders

`dev-runtime`이 관리합니다.

- NAT Gateway for private ECS tasks
- ECS cluster and Fargate services
- Single private RDS PostgreSQL instance
- Public ALB with path-based routing
- CloudWatch log groups
- ECS task IAM roles
- DB-related Secrets Manager values

이 구조에서는 비용 절감용 destroy가 `envs/dev-runtime` state만 대상으로 실행되므로, ECR 이미지와 네트워크 기반 리소스가 삭제 대상에서 구조적으로 제외됩니다.

현재 실행 중인 서비스:

- `user-service`
- `dispatch-service`

아직 준비만 되어 있거나 추후 추가할 서비스:

- `relocation-service`
- `control-service`

## Services

| Key | Module | Port | ALB paths |
| --- | --- | ---: | --- |
| `control` | `control-service` | 8081 | `/control*` |
| `dispatch` | `dispatch-service` | 8082 | `/dispatch*` |
| `relocation` | `relocation-service` | 8083 | `/relocation*` |
| `user` | `user-service` | 8084 | `/auth*`, `/users*`, `/swagger-ui*`, `/api-docs*` |

## Dev URLs

Swagger URLs:

- User: `http://baro-dev-1701378146.ap-northeast-2.elb.amazonaws.com/swagger-ui.html`
- Dispatch: `http://baro-dev-1701378146.ap-northeast-2.elb.amazonaws.com/dispatch/swagger-ui.html`

Service base URLs:

- User auth: `http://baro-dev-1701378146.ap-northeast-2.elb.amazonaws.com/auth`
- User: `http://baro-dev-1701378146.ap-northeast-2.elb.amazonaws.com/users`
- Dispatch: `http://baro-dev-1701378146.ap-northeast-2.elb.amazonaws.com/dispatch`

## 운영 방식

Terraform은 GitHub Actions로 실행합니다.

- PR branch push: `dev-shared`, `dev-runtime` 각각 `fmt`, `init`, `validate`, `plan`
- `main` push/merge: `dev-shared`, `dev-runtime` plan까지 실행
- 수동 실행: `workflow_dispatch`로 `plan`, `apply`, `destroy`와 `stack` 선택 가능

즉 일반적인 변경 흐름은 아래와 같습니다.

```text
branch에서 Terraform 코드 수정
→ PR 생성
→ GitHub Actions plan 확인
→ PR merge
→ 필요 시 workflow_dispatch로 수동 apply
```

가능하면 `main` 직접 push는 피하고 PR merge로 반영합니다.

## Terraform GitHub Actions

Workflow 파일:

```text
.github/workflows/terraform-dev.yml
```

`baro-terraform` repository secrets에 아래 값이 필요합니다.

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

수동 `destroy`는 안전장치가 있습니다. 기본 destroy 범위는 비용이 큰 실행 리소스만 내리는 `runtime`입니다.

```text
action = destroy
stack = runtime
confirm_destroy = destroy-dev-runtime
```

`runtime` destroy는 `envs/dev-runtime` state만 삭제합니다.

- NAT Gateway/EIP/private route table
- ECS cluster/services/task definitions
- ALB/listener/rules/target groups
- RDS instance/DB subnet group/RDS security group/DB secret values managed by runtime
- ECS task IAM roles
- CloudWatch log groups

`envs/dev-shared` state의 VPC/Subnets/IGW/ECR/서비스 Secret placeholder는 남습니다.

전체 dev stack을 삭제해야 할 때만 `all` 범위를 사용합니다.

```text
action = destroy
stack = all
confirm_destroy = destroy-dev-all
```

`all` destroy는 의존성 순서 때문에 `runtime`을 먼저 삭제하고, 그 다음 `shared`를 삭제합니다. `confirm_destroy` 값이 stack과 정확히 맞지 않으면 destroy 전에 실패합니다.

`stack = shared` 단독 destroy는 막아두었습니다. runtime이 살아있는 상태에서 shared만 지우면 ECR/Secrets/VPC 의존성이 깨질 수 있기 때문입니다.

## Remote state

dev 환경은 S3 backend를 사용하며 stack별 state key가 분리되어 있습니다.

```hcl
bucket         = "baro-dev-terraform-state-379992420279"
region         = "ap-northeast-2"
dynamodb_table = "baro-dev-terraform-locks"
encrypt        = true
```

State keys:

```text
dev-shared  = baro/dev-shared/terraform.tfstate
dev-runtime = baro/dev-runtime/terraform.tfstate
```

State locking은 DynamoDB를 사용합니다.

## 로컬에서 Terraform을 실행해야 할 때

대부분의 작업은 GitHub Actions에서 처리합니다. 그래도 로컬 확인이 필요하면 아래처럼 실행합니다.

```bash
cd envs/dev-shared
AWS_PROFILE=baro-dev AWS_REGION=ap-northeast-2 terraform init -backend-config=backend.hcl.example
AWS_PROFILE=baro-dev AWS_REGION=ap-northeast-2 terraform plan

cd ../dev-runtime
AWS_PROFILE=baro-dev AWS_REGION=ap-northeast-2 terraform init -backend-config=backend.hcl.example
AWS_PROFILE=baro-dev AWS_REGION=ap-northeast-2 terraform plan
```

로컬에서 `terraform apply`는 가급적 사용하지 않습니다.

### 로컬 runtime destroy plan이 필요할 때

GitHub Actions의 `stack = runtime`과 같은 범위를 로컬에서 미리 확인하려면 `envs/dev-runtime`에서 destroy plan을 봅니다. `-target`을 나열하지 않아도 runtime state에 속한 리소스만 삭제 대상으로 잡힙니다.

```bash
cd envs/dev-runtime
terraform plan -destroy
```

### 기존 단일 dev state에서 분리할 때

기존 `baro/dev/terraform.tfstate`에 리소스가 남아있는 상태에서 이 구조로 전환할 경우, 바로 apply하면 중복 생성/이름 충돌이 날 수 있습니다. 이때는 먼저 기존 state를 `dev-shared`, `dev-runtime` state로 이동하거나, 기존 dev 리소스를 완전히 destroy한 뒤 `dev-shared` → `dev-runtime` 순서로 새로 apply합니다.

이 전환 작업 때문에 `main` push/merge에서는 자동 apply하지 않고 plan까지만 실행합니다. state 분리/bootstrap이 끝난 뒤 필요하면 자동 apply 정책을 다시 검토합니다.

새로 생성하는 경우 순서:

```text
1. envs/dev-shared apply
2. envs/dev-runtime apply
```

비용 절감용 destroy:

```text
1. envs/dev-runtime destroy
2. envs/dev-shared 유지
```

## RDS layout

dev 환경은 PostgreSQL RDS instance 1개를 사용합니다.

```text
RDS PostgreSQL instance
└─ database: baro
   ├─ schema: user_service
   ├─ schema: dispatch_service
   ├─ schema: relocation_service
   └─ schema: control_service
```

서비스별로 다른 RDS instance를 만들지 않고, 같은 database 안에서 schema로 논리 분리합니다.

예시 JDBC URL:

```text
jdbc:postgresql://RDS_ENDPOINT:5432/baro?currentSchema=user_service
jdbc:postgresql://RDS_ENDPOINT:5432/baro?currentSchema=dispatch_service
```

Aurora/RDS cluster에 여러 DB instance를 두는 구조는 고가용성 또는 read scaling이 필요할 때 고려합니다. dev/초기 운영에서는 단일 RDS instance + schema 분리가 단순하고 비용도 낮습니다.

## Secrets

DB 관련 secret은 Terraform이 RDS 값으로 자동 생성/주입합니다.

User DB secrets:

- `baro-dev/user/USER_DB_URL`
- `baro-dev/user/USER_DB_USERNAME`
- `baro-dev/user/USER_DB_PASSWORD`

Dispatch DB secrets:

- `baro-dev/dispatch/DISPATCH_DB_URL`
- `baro-dev/dispatch/DISPATCH_DB_USERNAME`
- `baro-dev/dispatch/DISPATCH_DB_PASSWORD`

직접 관리해야 하는 app-level secrets:

- `baro-dev/user/JWT_SECRET`
- `baro-dev/dispatch/KAKAO_MOBILITY_API_KEY`

`dispatch-service`는 별도 JWT secret을 갖지 않고 `baro-dev/user/JWT_SECRET`을 같이 사용합니다.

AWS Console에서 secret 값을 넣으려면:

```text
AWS Console → Secrets Manager → Secrets → secret name → Retrieve/Update secret value
```

AWS CLI로 넣으려면:

```bash
aws secretsmanager put-secret-value --secret-id baro-dev/user/JWT_SECRET --secret-string '...'
aws secretsmanager put-secret-value --secret-id baro-dev/dispatch/KAKAO_MOBILITY_API_KEY --secret-string '...'
```

## ECS desired count

현재 dev 기본값은 아래와 같습니다.

```hcl
service_desired_counts = {
  user     = 1
  dispatch = 1
}
```

새 서비스를 추가할 때는 처음에 desired count를 `0`으로 두고 아래 순서로 진행하는 것을 권장합니다.

```text
1. Terraform으로 ECR/ECS/ALB/Secrets 생성
2. 필요한 Secrets Manager 값 입력
3. baro-server deploy workflow로 Docker image push
4. desired count를 1로 변경
5. PR merge로 Terraform apply
```

## baro-server 배포 workflow

`baro-server` repository에는 dev ECS 배포 workflow가 있습니다.

```text
.github/workflows/deploy-dev-ecs.yml
```

현재 배포 대상:

- `user-service`
- `dispatch-service`

이 workflow는 아래 작업을 수행합니다.

```text
Gradle build
→ Docker image build
→ ECR push
→ ECS force new deployment
```

`baro-server` repository secrets에도 아래 값이 필요합니다.

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

## Terraform과 application deploy의 역할 분리

Terraform이 관리하는 것:

- VPC/Subnets/NAT Gateway
- ALB/listener rules/target groups
- ECR repositories
- ECS cluster/services/task definitions
- RDS
- Secrets Manager secret entries
- IAM roles
- CloudWatch log groups

`baro-server` deploy workflow가 관리하는 것:

- Docker image build
- ECR image push
- ECS force new deployment

Task definition의 environment variables나 secrets가 바뀌면 Terraform apply가 필요합니다. 단순히 application image만 바뀌는 경우에는 `baro-server` deploy workflow로 충분합니다.
