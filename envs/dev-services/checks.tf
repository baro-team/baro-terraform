check "shared_services_include_enabled_services" {
  assert {
    condition = alltrue([
      for service in var.enabled_services : contains(keys(local.shared.ecr_repository_urls), service)
    ])
    error_message = "dev-services enabled_services must be included in dev-shared enabled_services so ECR repositories and service secret placeholders exist."
  }
}
