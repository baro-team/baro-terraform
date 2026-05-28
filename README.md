# baro-terraform

`baro-server`를 AWS ECS on Fargate로 배포하기 위한 Terraform 저장소입니다.

## Dev stack

현재 dev 환경은 아래 리소스를 생성/관리합니다.

- VPC with public/private subnets
- NAT Gateway for private ECS tasks
- ECR repositories
- ECS cluster and Fargate services
- Single private RDS PostgreSQL instance
- Public ALB with path-based routing
- CloudWatch log groups
- Secrets Manager entries

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

- PR branch push: `terraform fmt`, `init`, `validate`, `plan`
- `main` push/merge: `terraform fmt`, `init`, `validate`, `plan`, `apply`
- 수동 실행: `workflow_dispatch`로 `plan`, `apply`, `destroy` 선택 가능

즉 일반적인 변경 흐름은 아래와 같습니다.

```text
branch에서 Terraform 코드 수정
→ PR 생성
→ GitHub Actions plan 확인
→ PR merge
→ main에서 자동 apply
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

수동 `destroy`는 안전장치가 있습니다.

```text
action = destroy
confirm_destroy = destroy-dev
```

`confirm_destroy` 값이 정확하지 않으면 destroy는 실패합니다.

## Remote state

dev 환경은 S3 backend를 사용합니다.

```hcl
bucket         = "baro-dev-terraform-state-379992420279"
key            = "baro/dev/terraform.tfstate"
region         = "ap-northeast-2"
dynamodb_table = "baro-dev-terraform-locks"
encrypt        = true
```

State locking은 DynamoDB를 사용합니다.

## 로컬에서 Terraform을 실행해야 할 때

대부분의 작업은 GitHub Actions에서 처리합니다. 그래도 로컬 확인이 필요하면 아래처럼 실행합니다.

```bash
cd envs/dev
AWS_PROFILE=baro-dev AWS_REGION=ap-northeast-2 terraform init -backend-config=backend.hcl.example
AWS_PROFILE=baro-dev AWS_REGION=ap-northeast-2 terraform plan
```

로컬에서 `terraform apply`는 가급적 사용하지 않습니다.

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
