resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/lambda/${local.name_prefix}-api"
  retention_in_days = 14
}

resource "aws_lambda_function" "api" {
  function_name = "${local.name_prefix}-api"
  role          = aws_iam_role.lambda.arn

  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.api.repository_url}:${var.image_tag}"
  architectures = ["x86_64"]

  memory_size = 1024
  timeout     = 30

  logging_config {
    log_format = "JSON"
    log_group  = aws_cloudwatch_log_group.api.name
  }

  # apenas o CAMINHO no SSM, nunca os valores: variavel de ambiente da Lambda
  # aparece em texto puro no console e em GetFunctionConfiguration
  environment {
    variables = {
      SSM_PREFIX = local.ssm_prefix

      # muda sempre que app_config muda. Como alterar a config da funcao
      # descarta os containers vivos, o valor novo passa a valer no apply -
      # sem isto, a Lambda so releria o SSM no proximo cold start espontaneo.
      CONFIG_VERSION = substr(sha1(jsonencode(var.app_config)), 0, 8)
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_logs,
    aws_iam_role_policy.lambda_ssm,
  ]

}