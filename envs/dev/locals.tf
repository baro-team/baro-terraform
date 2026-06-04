locals {
  name_prefix     = "${var.project}-${var.environment}"
  app_domain_name = var.app_domain_name != "" ? var.app_domain_name : "${var.environment}.${var.domain_name}"

  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  all_services = {
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
        DISPATCH_SERVICE_URL       = "http://${aws_lb.this.dns_name}"
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
        BARO_ERROR_INCLUDE_DETAILS    = "true"
        SPRING_JPA_HIBERNATE_DDL_AUTO = "update"
        SPRINGDOC_API_DOCS_PATH       = "/dispatch/api-docs"
        SPRINGDOC_SWAGGER_UI_PATH     = "/dispatch/swagger-ui.html"
        REDIS_HOST                    = aws_elasticache_cluster.redis.cache_nodes[0].address
        REDIS_PORT                    = "6379"
        DISPATCH_DB_URL               = "jdbc:postgresql://${aws_db_instance.postgres.address}:${aws_db_instance.postgres.port}/${aws_db_instance.postgres.db_name}?currentSchema=dispatch_service"
      }
      secret_names = [
        "KAKAO_MOBILITY_API_KEY"
      ]
    }

    relocation = {
      module            = "relocation-service"
      container_port    = 8083
      priority          = 103
      path_patterns     = ["/relocation", "/relocation/*"]
      health_check_path = "/actuator/health"
      extra_environment = {
        BARO_ERROR_INCLUDE_DETAILS = "true"
      }
      secret_names = []
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
        USER_DB_URL                          = "jdbc:postgresql://${aws_db_instance.postgres.address}:${aws_db_instance.postgres.port}/${aws_db_instance.postgres.db_name}?currentSchema=user_service"
      }
      secret_names = [
        "JWT_SECRET"
      ]
    }
  }

  services = {
    for key, service in local.all_services : key => service
    if contains(var.enabled_services, key)
  }

  secret_keys = toset(flatten([
    for service_name, service in local.services : [
      for secret_name in service.secret_names : "${service_name}/${secret_name}"
    ]
  ]))
}
