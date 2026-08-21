# O state sai do disco de quem roda o apply e passa a morar no S3, para que a
# CI enxergue a mesma realidade que voce. O bucket precisa existir ANTES do init,
# por isso ele e criado na CLI e nao aqui.
terraform {
  backend "s3" {
    bucket = "nyc-taxi-regression-tfstate-769291435352"
    key    = "prod/terraform.tfstate"
    region = "us-east-1"

    encrypt = true

    # lock nativo do backend S3 (Terraform >= 1.10): grava um .tflock ao lado do
    # state e impede dois applies simultaneos - o seu e o da CI, por exemplo.
    # Tutorial antigo manda criar tabela DynamoDB para isso; nao precisa mais.
    use_lockfile = true
  }
}