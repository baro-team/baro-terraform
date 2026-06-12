# baro-terraform

`baro-server`를 AWS dev 환경에 배포하기 위한 Terraform 저장소입니다.  
현재 dev 환경은 ECS on Fargate, private RDS, Kafka EC2, ElastiCache Valkey를 중심으로 구성합니다.

## 목차

- [Dev stack](#dev-stack)
- [Services](#services)
- [Dev URLs](#dev-urls)
- [주요 내부 엔드포인트](#주요-내부-엔드포인트)
- [Service environment and secrets](#service-environment-and-secrets)
  - [control-service](#control-service)
  - [dispatch-service](#dispatch-service)
  - [user-service](#user-service)
- [RDS layout](#rds-layout)
  - [RDS 접속 방식](#rds-접속-방식)
- [ElastiCache Valkey](#elasticache-valkey)
- [Kafka](#kafka)
- [Secrets](#secrets)
- [Terraform GitHub Actions](#terraform-github-actions)
  - [Destroy safety](#destroy-safety)
- [Remote state](#remote-state)
- [로컬에서 Terraform을 실행해야 할 때](#로컬에서-terraform을-실행해야-할-때)
- [ECS desired count](#ecs-desired-count)
- [baro-server 배포 workflow](#baro-server-배포-workflow)
- [Terraform과 application deploy의 역할 분리](#terraform과-application-deploy의-역할-분리)

## Dev stack

현재 dev 환경은 아래 리소스를 생성/관리합니다.

- VPC with public/private subnets
- NAT Gateway for private ECS tasks
- Public ALB with HTTPS and path-based routing
- Route 53 alias and ACM certificate for `dev.barocloud.com`
- ECR repositories
- ECS cluster and Fargate services
- Private RDS PostgreSQL instance
- SSM-only bastion EC2 for private RDS access
- Kafka EC2 with EBS persistence and Cloud Map DNS
- ElastiCache Valkey for vehicle GEO cache
- CloudWatch log groups
- Secrets Manager secret placeholders and RDS master secret
- One-off ECS `db-init` task for schema initialization

## Services

지원 서비스:

| Key | Module | Port | ALB paths | Default enabled |
| --- | --- | ---: | --- | --- |
| `control` | `control-service` | 8081 | `/control`, `/control/*` | yes |
| `dispatch` | `dispatch-service` | 8082 | `/dispatch`, `/dispatch/*` | yes |
| `relocation` | `relocation-service` | 8083 | `/relocation`, `/relocation/*` | yes |
| `user` | `user-service` | 8084 | `/user`, `/user/*` | yes |
| `admin` | `baro-admin` | 80 | `/admin`, `/admin/*` | yes |
| `mobile` | `baro-mobile` | 80 | `/*` | yes |

기본 `enabled_services`는 아래와 같습니다.

```hcl
enabled_services = ["user", "dispatch", "control", "admin", "relocation", "mobile"]
```

`mobile`은 HTTPS listener의 catch-all rule로 등록되어 `/control`, `/dispatch`, `/user`, `/admin`, `/relocation` 등 더 높은 우선순위의 서비스 path를 제외한 웹 트래픽을 처리합니다.

## Dev URLs

Swagger URLs:

- User: https://dev.barocloud.com/user/swagger-ui.html
- Dispatch: https://dev.barocloud.com/dispatch/swagger-ui.html

Service base URLs:

- Control: https://dev.barocloud.com/control
- Dispatch: https://dev.barocloud.com/dispatch
- User: https://dev.barocloud.com/user/users
- Mobile web: https://dev.barocloud.com/

## 주요 내부 엔드포인트

| Component | Endpoint |
| --- | --- |
| Kafka | `kafka.baro.internal:9092` |
| RDS | private RDS endpoint, port `5432` |
| Valkey | `redis_host` output, port `6379` |

Kafka는 ECS가 아니라 private EC2에서 실행되며, Cloud Map namespace를 통해 `kafka.baro.internal`로 접근합니다.

## Service environment and secrets

### control-service

주요 환경변수:

- MQTT/AWS IoT 설정
- `KAFKA_BOOTSTRAP_SERVERS=kafka.baro.internal:9092`
- `KAFKA_TOPIC=vehicle-data-topic`
- `DISPATCH_SERVICE_URL`

직접 채워야 하는 Secrets Manager 값:

- `baro-dev/control/IOT_CA_CERT`
- `baro-dev/control/IOT_CERT`
- `baro-dev/control/IOT_KEY`

### dispatch-service

주요 환경변수:

- `DISPATCH_DB_URL`
- `KAFKA_BOOTSTRAP_SERVERS=kafka.baro.internal:9092`
- `KAFKA_DISPATCH_CONSUMER_GROUP_ID=dispatch-service`
- `KAFKA_VEHICLE_DATA_TOPIC=vehicle-data-topic`
- `REDIS_HOST`
- `REDIS_PORT=6379`
- `REDIS_SSL_ENABLED=false`
- `DISPATCH_REDIS_IDLE_CAR_GEO_KEY=dispatch:cars:idle:geo`
- `DISPATCH_REDIS_IDLE_CAR_SEARCH_RADIUS_KM=5.0`

직접 채워야 하는 Secrets Manager 값:

- `baro-dev/dispatch/KAKAO_MOBILITY_API_KEY`

공유 secret 주입:

- `DISPATCH_DB_USERNAME`, `DISPATCH_DB_PASSWORD`: `baro-dev/rds/master`에서 주입
- `JWT_SECRET`: `baro-dev/user/JWT_SECRET` 재사용

### user-service

주요 환경변수:

- `USER_DB_URL`
- JWT access/refresh 만료 시간
- Swagger path override

직접 채워야 하는 Secrets Manager 값:

- `baro-dev/user/JWT_SECRET`

공유 secret 주입:

- `USER_DB_USERNAME`, `USER_DB_PASSWORD`: `baro-dev/rds/master`에서 주입

### mobile web

주요 환경변수:

- `BACKEND_API_BASE_URL=https://dev.barocloud.com`

직접 채워야 하는 Secrets Manager 값:

- `baro-dev/mobile/KAKAO_REST_API_KEY`

Terraform은 이 값을 ECS task definition의 `secrets`로 참조만 합니다. 값은 AWS Secrets Manager에 직접 입력해야 하며, GitHub Actions secret 또는 Terraform variable에서 일반 환경변수로 주입하지 않습니다.
처음 반영할 때는 ECS service가 새 task definition으로 배포되기 전에 `baro-dev/mobile/KAKAO_REST_API_KEY`에 실제 SecretString 값을 먼저 채워야 합니다.
이미 AWS Secrets Manager에 수동 생성된 dev secret은 Terraform `import` block으로 state에 편입합니다. secret을 삭제하지 말고 값 변경은 `put-secret-value`만 사용합니다.

`baro-mobile` 컨테이너는 정적 SPA를 nginx로 서빙하며, `/api/auth`, `/api/dispatch`, `/api/places/search` 요청을 런타임 nginx 프록시로 처리합니다.

## RDS layout

dev 환경은 private PostgreSQL RDS instance 1개를 사용합니다.

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

RDS는 public access를 허용하지 않습니다.

### RDS 접속 방식

DB tool 또는 로컬 CLI에서 접근해야 할 때는 SSM-only bastion을 통해 port forwarding합니다.

```bash
aws ssm start-session \
  --region ap-northeast-2 \
  --target <bastion_instance_id> \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["<rds_host>"],"portNumber":["5432"],"localPortNumber":["15432"]}'
```

로컬 접속 예시:

```text
Host: localhost
Port: 15432
Database: baro
User/Password: baro-dev/rds/master secret
```

## ElastiCache Valkey

dispatch-service의 차량 GEO cache는 ElastiCache Valkey를 사용합니다.

현재 dev 설정:

```text
engine: valkey
engine_version: 7.2
node_type: cache.t4g.micro
num_cache_clusters: 1
automatic_failover_enabled: false
at_rest_encryption_enabled: true
apply_immediately: true
```

Terraform output 이름은 application 호환성을 위해 `redis_host`, `redis_port`를 유지합니다.  
애플리케이션도 Valkey에 Redis protocol로 접속하므로 `REDIS_HOST`, `REDIS_PORT` 환경변수를 사용합니다.

## Kafka

Kafka는 private EC2에서 Docker container로 실행합니다.

- private subnet 배치
- EBS volume persistence
- ECS task SG와 on-prem/VPN CIDR에서 `9092` 접근 허용
- Cloud Map DNS: `kafka.baro.internal`

서비스에서는 아래 bootstrap server를 사용합니다.

```text
kafka.baro.internal:9092
```

## Secrets

Terraform이 생성/관리하는 주요 secret:

- `baro-dev/rds/master`: RDS master username/password
- service-level secret placeholders

직접 값 입력이 필요한 app-level secret:

- `baro-dev/user/JWT_SECRET`
- `baro-dev/dispatch/KAKAO_MOBILITY_API_KEY`
- `baro-dev/control/IOT_CA_CERT`
- `baro-dev/control/IOT_CERT`
- `baro-dev/control/IOT_KEY`

AWS Console에서 secret 값을 넣으려면:

```text
AWS Console → Secrets Manager → Secrets → secret name → Retrieve/Update secret value
```

AWS CLI 예시:

```bash
aws secretsmanager put-secret-value --secret-id baro-dev/user/JWT_SECRET --secret-string '...'
aws secretsmanager put-secret-value --secret-id baro-dev/dispatch/KAKAO_MOBILITY_API_KEY --secret-string '...'
```

## Terraform GitHub Actions

Workflow 파일:

```text
.github/workflows/terraform-dev.yml
```

필요한 repository secrets:

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

실행 방식:

- PR: `terraform fmt`, `init`, `validate`, `plan`
- `main` push/merge: `plan`, `apply`, `db-init`
- 수동 실행: `workflow_dispatch`

수동 실행 action:

- `plan`
- `apply`
- `db-init`
- `destroy`

일반적인 변경 흐름:

```text
branch에서 Terraform 코드 수정
→ PR 생성
→ GitHub Actions plan 확인
→ PR merge
→ main에서 자동 apply
→ db-init 실행
```

가능하면 `main` 직접 push는 피하고 PR merge로 반영합니다.

### Destroy safety

수동 `destroy`는 안전장치가 있습니다.

Runtime destroy:

```text
action = destroy
destroy_scope = runtime
confirm_destroy = destroy-dev
```

`runtime` destroy는 비용이 큰 실행 리소스 중심으로 삭제하고, VPC/Subnets/ECR/서비스 Secret placeholder 같은 보존 리소스는 남깁니다.

Full destroy:

```text
action = destroy
destroy_scope = all
confirm_destroy = destroy-dev-all
```

`confirm_destroy` 값이 destroy 범위와 정확히 맞지 않으면 destroy plan 전에 실패합니다.

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

## ECS desired count

현재 dev 기본값은 아래와 같습니다.

```hcl
service_desired_counts = {
  user     = 1
  dispatch = 1
}
```

`control-service`는 `service_desired_counts`에 별도 값이 없으면 `service_desired_count` 기본값을 사용합니다.

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
- RDS and SSM bastion
- Kafka EC2 and Cloud Map registration
- ElastiCache Valkey
- Secrets Manager entries
- IAM roles
- CloudWatch log groups

`baro-server` deploy workflow가 관리하는 것:

- Docker image build
- ECR image push
- ECS force new deployment

Task definition의 environment variables나 secrets가 바뀌면 Terraform apply가 필요합니다. 단순히 application image만 바뀌는 경우에는 `baro-server` deploy workflow로 충분합니다.
