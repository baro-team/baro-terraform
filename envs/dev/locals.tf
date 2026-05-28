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
      path_patterns  = ["/control", "/control/*"]
      extra_environment = {
        MQTT_MODE = "LOCAL"
      }
      secret_names = [
        "REDIS_HOST",
        "REDIS_PORT",
        "LOCAL_MQTT_HOST",
        "LOCAL_MQTT_PORT",
        "IOT_ENDPOINT",
        "IOT_CLIENT_ID",
        "IOT_CERTIFICATE_PATH",
        "IOT_PRIVATE_KEY_PATH",
        "IOT_CA_CERTIFICATE_PATH",
        "DISPATCH_SERVICE_URL"
      ]
    }

    dispatch = {
      module         = "dispatch-service"
      container_port = 8082
      path_patterns  = ["/dispatch", "/dispatch/*"]
      extra_environment = {
        SPRING_JPA_HIBERNATE_DDL_AUTO = "update"
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
      path_patterns     = ["/relocation", "/relocation/*"]
      extra_environment = {}
      secret_names      = []
    }

    user = {
      module         = "user-service"
      container_port = 8084
      path_patterns  = ["/auth", "/auth/*", "/users", "/users/*"]
      extra_environment = {
        JWT_ACCESS_TOKEN_EXPIRATION_SECONDS  = "3600"
        JWT_REFRESH_TOKEN_EXPIRATION_SECONDS = "1209600"
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
