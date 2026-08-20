output "ecr_repository" {
  description = "ECR repository URL"
  value       = aws_ecr_repository.api.repository_url
}

output "lambda_function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.api.function_name
}

output "api_endpoint" {
  description = "API Public URL"
  value       = aws_apigatewayv2_stage.default.invoke_url
}