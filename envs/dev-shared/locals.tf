locals {
  name_prefix = "${var.project}-${var.environment}"

  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Layer       = "shared"
  }

  all_services = {
    control = {
      module = "control-service"
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
      module = "dispatch-service"
      secret_names = [
        "DISPATCH_DB_URL",
        "DISPATCH_DB_USERNAME",
        "DISPATCH_DB_PASSWORD",
        "KAKAO_MOBILITY_API_KEY"
      ]
    }

    relocation = {
      module       = "relocation-service"
      secret_names = []
    }

    user = {
      module = "user-service"
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
