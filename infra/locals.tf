locals {
  name_prefix = "${var.project_name}-${var.environment}"

  # todo parametro da aplicacao vive sob este caminho no SSM
  ssm_prefix = "/${var.project_name}/${var.environment}"

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
