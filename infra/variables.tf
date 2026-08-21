variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix for resources"
  type        = string
  default     = "nyc-taxi-regression"
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "image_tag" {
  description = "ECR Image Tag to lambda execute"
  type        = string
}

# Configuracao nao-sensivel: o Terraform e dono do valor.
# Mudou aqui -> apply -> mudou no SSM.
variable "app_config" {
  description = "Non-sensitive parameters exposed to the application via SSM"
  type        = map(string)

  default = {
    client_url = "https://app.exemplo.com"
  }
}

# Segredos: o Terraform cria apenas a casca do parametro.
# O valor e definido fora, via CLI, e nunca aparece no codigo.
variable "app_secrets" {
  description = "Names of sensitive parameters (values ​​defined via CLI)"
  type        = set(string)
  default     = []
}




# CI/CD

variable "github_repository" {
  description = "Onwer/Repo authorized to assume an implementation role"
  type        = string
  default     = "PedroBSanchez/nyc_taxi_regression"
}

variable "state_bucket" {
  description = "Bucket of remote terraform state file"
  type        = string
  default     = "nyc-taxi-regression-tfstate-769291435352"
}