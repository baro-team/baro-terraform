# AGENTS.md

## 작업 범위

- 이 저장소는 `baro-server`의 AWS dev 인프라를 Terraform으로 관리한다.
- 현재 dev 런타임은 ECS on Fargate, public ALB, internal ALB, Cloud Map, private RDS, Kafka EC2, ElastiCache Valkey를 중심으로 구성한다.
- 실제 비밀값은 Git에 기록하지 않는다. Terraform은 Secrets Manager secret 리소스/참조만 관리하고 값은 AWS Console/CLI에서 입력한다.
- 배포 workflow, ECS 서비스, ALB 라우팅 변경은 `baro-server`의 서비스 구조와 함께 맞춘다.

## Gateway와 라우팅 원칙

- 외부 업무 API 진입점은 `gateway-service`다.
- Public ALB에서 업무 API 경로는 기본적으로 `gateway-service`로 라우팅한다.
  - `/user`, `/user/*`
  - `/dispatch`, `/dispatch/*`
  - `/control`, `/control/*`
  - `/relocation/assign`
- Public ALB에 직접 연결되는 서비스는 `local.public_alb_services`로 제한한다.
  - 현재 대상: `gateway`, `admin`, `mobile`
- `aws_lb_target_group.service`와 ECS service의 public `load_balancer` 블록은 `local.public_alb_services` 대상에만 생성/적용한다.
- `user`, `dispatch`, `control`, `relocation` 같은 내부 API 서비스는 public ALB target group에 직접 등록하지 않는다.
- `/internal/*` 및 `*/internal/*`은 public ALB listener rule에서 403으로 차단한다.

## Internal 통신 원칙

- 서비스 간 내부 호출은 public Gateway를 우회하고 Cloud Map private DNS 또는 internal ALB를 사용한다.
- Cloud Map namespace는 `baro.internal`이다.
- 주요 서비스 DNS 예시:
  - `gateway-service.baro.internal:8080`
  - `user-service.baro.internal:8084`
  - `dispatch-service.baro.internal:8082`
  - `control-service.baro.internal:8081`
  - `relocation-service.baro.internal:8083`
  - `kafka.baro.internal:9092`
- `gateway-service`의 downstream URL은 Cloud Map DNS를 사용한다.
- `control-service`의 `DISPATCH_SERVICE_URL`과 `dispatch-service`의 `CONTROL_SERVICE_URL`도 Cloud Map DNS를 사용한다.
- Internal ALB는 `/internal/{service}/*` 형태의 내부 라우팅을 제공한다.

## Internal API Key

- 기존 `INTERNAL_API_KEY` secret은 유지한다.
- `internal_api_key_secret_name` 기본값은 `baro-dev/dispatch/INTERNAL_API_KEY`다.
- ECS task definition에는 `data.aws_secretsmanager_secret.internal_api_key`를 통해 같은 값을 주입한다.
- 현재 주입 대상은 `dispatch`, `relocation`이다.
- `control`은 현재 서버 코드에서 `INTERNAL_API_KEY`를 읽거나 전송하지 않으므로 주입하지 않는다.
- `secret_names`에 있는 `INTERNAL_API_KEY`는 기존 Secret Manager 리소스 유지를 위한 항목이므로 삭제하지 않는다.
- 컨테이너 secret 생성 시 `INTERNAL_API_KEY`는 service-level secret placeholder가 아니라 shared existing secret 참조로 주입한다.

## Terraform 작업 규칙

- 가능하면 `main` 직접 push보다 PR을 사용한다. 단, 명시적으로 요청받은 경우에만 main에 직접 push한다.
- 로컬 사용자 변경(`.gitignore`, `.local-notes/` 등)은 임의로 커밋하지 않는다.
- 커밋 전 확인:
  - `git status`
  - `git diff`
  - `git log --oneline -10`
- 검증:
  - `cd envs/dev && terraform fmt -recursive && terraform validate`
- 배포 적용은 GitHub Actions가 main push/merge 후 수행한다.
- Terraform apply 전, task definition이 참조하는 Secrets Manager 값이 실제로 채워져 있는지 확인한다.

## 서비스 추가/변경 시 주의

- 새 backend 서비스가 외부 업무 API라면 먼저 Gateway 라우팅과 server-side 인증/헤더 정책을 정한다.
- 새 서비스를 public ALB에 직접 붙이지 말고 Gateway 경유가 맞는지 우선 검토한다.
- public web 서비스만 `local.public_alb_services`에 추가한다.
- 내부 API 인증이 필요한 경우 서버 코드에서 `X-Internal-Api-Key` 처리와 Terraform secret 주입을 함께 변경한다.
- 인프라만 추가해도 이미지가 없으면 ECS 배포/헬스체크가 실패할 수 있으므로 `baro-server` 배포 순서와 함께 조율한다.
