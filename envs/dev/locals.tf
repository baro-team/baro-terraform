locals {
  name_prefix = "${var.project}-${var.environment}"

  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  all_services = {
    control = {
      module         = "control-service"
      container_port = 8081
      priority       = 100
      path_patterns  = ["/control", "/control/*"]
      extra_environment = {
        MQTT_MODE               = "aws"
        IOT_ENDPOINT            = "a7xnpqbtrafiw-ats.iot.ap-northeast-2.amazonaws.com"
        IOT_CA_PATH             = "certs/AmazonRootCA1.pem"
        IOT_CERT_PATH           = "certs/5647e867d2841c19a463402ca6e2c7fce6fde3a45c35c250087dda79a985a0f1-certificate.pem.crt"
        IOT_KEY_PATH            = "certs/5647e867d2841c19a463402ca6e2c7fce6fde3a45c35c250087dda79a985a0f1-private.pem.key"
        KAFKA_BOOTSTRAP_SERVERS = "kafka.${aws_service_discovery_private_dns_namespace.this.name}:9092"
        KAFKA_TOPIC             = "vehicle-data-topic"
        DISPATCH_SERVICE_URL    = "http://${aws_lb.this.dns_name}"
      }
      secret_names = ["DB_URL", "DB_USERNAME", "DB_PASSWORD"]
    }

    dispatch = {
      module         = "dispatch-service"
      container_port = 8082
      priority       = 101
      path_patterns  = ["/dispatch", "/dispatch/*"]
      extra_environment = {
        SPRING_JPA_HIBERNATE_DDL_AUTO = "update"
        SPRINGDOC_API_DOCS_PATH       = "/dispatch/api-docs"
        SPRINGDOC_SWAGGER_UI_PATH     = "/dispatch/swagger-ui.html"
      }
      secret_names = [
        "DISPATCH_DB_URL",
        "DISPATCH_DB_USERNAME",
        "DISPATCH_DB_PASSWORD",
        "KAKAO_MOBILITY_API_KEY"
      ]
    }

    relocation = {
      module            = "relocation-service"
      container_port    = 8083
      priority          = 103
      path_patterns     = ["/relocation", "/relocation/*"]
      extra_environment = {}
      secret_names      = []
    }

    user = {
      module         = "user-service"
      container_port = 8084
      priority       = 102
      path_patterns  = ["/auth", "/auth/*", "/users", "/users/*"]
      extra_environment = {
        JWT_ACCESS_TOKEN_EXPIRATION_SECONDS  = "3600"
        JWT_REFRESH_TOKEN_EXPIRATION_SECONDS = "1209600"
        SPRING_JPA_HIBERNATE_DDL_AUTO        = "update"
        SPRINGDOC_API_DOCS_PATH              = "/api-docs"
        SPRINGDOC_SWAGGER_UI_PATH            = "/swagger-ui.html"
      }
      secret_names = [
        "USER_DB_URL",
        "USER_DB_USERNAME",
        "USER_DB_PASSWORD",
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
