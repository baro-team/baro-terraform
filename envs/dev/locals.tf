locals {
  name_prefix       = "${var.project}-${var.environment}"
  app_domain_name   = var.app_domain_name != "" ? var.app_domain_name : "${var.environment}.${var.domain_name}"
  effective_db_name = (var.runtime_enabled && length(aws_db_instance.postgres) > 0) ? coalesce(try(aws_db_instance.postgres[0].db_name, null), var.rds_database_name) : var.rds_database_name

  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  all_services = {
    gateway = {
      module            = "gateway-service"
      container_port    = 8080
      priority          = 90
      path_patterns     = ["/user", "/user/*", "/dispatch", "/dispatch/*", "/control", "/control/*", "/relocation/assign"]
      health_check_path = "/actuator/health"
      extra_environment = {
        USER_SERVICE_URL       = "http://user-service.${aws_service_discovery_private_dns_namespace.this.name}:8084"
        DISPATCH_SERVICE_URL   = "http://dispatch-service.${aws_service_discovery_private_dns_namespace.this.name}:8082"
        CONTROL_SERVICE_URL    = "http://control-service.${aws_service_discovery_private_dns_namespace.this.name}:8081"
        RELOCATION_SERVICE_URL = "http://relocation-service.${aws_service_discovery_private_dns_namespace.this.name}:8083"
      }
      secret_names = []
    }

    control = {
      module            = "control-service"
      container_port    = 8081
      priority          = 100
      path_patterns     = ["/control", "/control/*"]
      health_check_path = "/actuator/health"
      extra_environment = {
        BARO_ERROR_INCLUDE_DETAILS = "true"
        MQTT_MODE                  = "aws"
        IOT_ENDPOINT               = "a7xnpqbtrafiw-ats.iot.ap-northeast-2.amazonaws.com"
        IOT_CA_PATH                = "certs/AmazonRootCA1.pem"
        IOT_CERT_PATH              = "certs/cert.pem.crt"
        IOT_KEY_PATH               = "certs/private.pem.key"
        KAFKA_BOOTSTRAP_SERVERS    = "kafka.${aws_service_discovery_private_dns_namespace.this.name}:9092"
        KAFKA_TOPIC                = "vehicle-data-topic"
        DISPATCH_SERVICE_URL       = "http://dispatch-service.${aws_service_discovery_private_dns_namespace.this.name}:8082"
      }
      secret_names = ["IOT_CA_CERT", "IOT_CERT", "IOT_KEY"]
    }

    dispatch = {
      module            = "dispatch-service"
      container_port    = 8082
      priority          = 101
      path_patterns     = ["/dispatch", "/dispatch/*"]
      health_check_path = "/actuator/health"
      extra_environment = {
        BARO_ERROR_INCLUDE_DETAILS               = "true"
        SPRING_JPA_HIBERNATE_DDL_AUTO            = "update"
        SPRINGDOC_API_DOCS_PATH                  = "/dispatch/api-docs"
        SPRINGDOC_SWAGGER_UI_PATH                = "/dispatch/swagger-ui.html"
        REDIS_HOST                               = aws_elasticache_replication_group.redis.primary_endpoint_address
        REDIS_PORT                               = "6379"
        REDIS_SSL_ENABLED                        = "false"
        DISPATCH_REDIS_IDLE_CAR_GEO_KEY          = "dispatch:cars:idle:geo"
        DISPATCH_REDIS_IDLE_CAR_SEARCH_RADIUS_KM = "5.0"
        DISPATCH_DB_URL                          = var.runtime_enabled ? "jdbc:postgresql://${aws_db_instance.postgres[0].address}:${aws_db_instance.postgres[0].port}/${local.effective_db_name}?currentSchema=dispatch_service" : ""
        KAFKA_BOOTSTRAP_SERVERS                  = "kafka.${aws_service_discovery_private_dns_namespace.this.name}:9092"
        KAFKA_DISPATCH_CONSUMER_GROUP_ID         = "dispatch-service"
        KAFKA_VEHICLE_DATA_TOPIC                 = "vehicle-data-topic"
        CONTROL_SERVICE_URL                      = "http://control-service.${aws_service_discovery_private_dns_namespace.this.name}:8081"
      }
      secret_names = [
        "KAKAO_MOBILITY_API_KEY",
        "INTERNAL_API_KEY"
      ]
    }

    relocation = {
      module            = "relocation-service"
      container_port    = 8083
      priority          = 103
      path_patterns     = ["/relocation", "/relocation/*"]
      health_check_path = "/actuator/health"
      extra_environment = {
        BARO_ERROR_INCLUDE_DETAILS    = "true"
        SPRING_JPA_HIBERNATE_DDL_AUTO = "update"
      }
      secret_names = [
        "RELOCATION_DB_URL",
        "RELOCATION_DB_USERNAME",
        "RELOCATION_DB_PASSWORD",
        "INTERNAL_API_KEY"
      ]
    }

    user = {
      module            = "user-service"
      container_port    = 8084
      priority          = 102
      path_patterns     = ["/user", "/user/*"]
      health_check_path = "/actuator/health"
      extra_environment = {
        BARO_ERROR_INCLUDE_DETAILS           = "true"
        JWT_ACCESS_TOKEN_EXPIRATION_SECONDS  = "3600"
        JWT_REFRESH_TOKEN_EXPIRATION_SECONDS = "1209600"
        SPRING_JPA_HIBERNATE_DDL_AUTO        = "update"
        SPRINGDOC_API_DOCS_PATH              = "/user/api-docs"
        SPRINGDOC_SWAGGER_UI_PATH            = "/user/swagger-ui.html"
        USER_DB_URL                          = var.runtime_enabled ? "jdbc:postgresql://${aws_db_instance.postgres[0].address}:${aws_db_instance.postgres[0].port}/${local.effective_db_name}?currentSchema=user_service" : ""
      }
      secret_names = [
        "JWT_SECRET"
      ]
    }

    admin = {
      module            = "baro-admin"
      container_port    = 80
      priority          = 110
      path_patterns     = ["/admin", "/admin/*"]
      health_check_path = "/health"
      extra_environment = {}
      secret_names      = []
    }

    mobile = {
      module            = "baro-mobile"
      container_port    = 80
      priority          = 9999
      path_patterns     = ["/*"]
      health_check_path = "/health"
      extra_environment = {
        BACKEND_API_BASE_URL = var.runtime_enabled ? "https://${local.app_domain_name}" : ""
      }
      secret_names = [
        "KAKAO_REST_API_KEY"
      ]
    }
  }

  services = {
    for key, service in local.all_services : key => service
    if contains(var.enabled_services, key)
  }

  runtime_services = var.runtime_enabled ? local.services : {}

  public_alb_services = {
    for key, service in local.runtime_services : key => service
    if contains(["gateway", "admin", "mobile"], key)
  }

  secret_keys = toset(flatten([
    for service_name, service in local.all_services : [
      for secret_name in service.secret_names : "${service_name}/${secret_name}"
    ]
  ]))
}
