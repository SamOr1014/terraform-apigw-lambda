provider "aws" {
  region = "eu-west-2"
}

resource "aws_iam_role" "lambda_role" {
  name               = "terraform_aws_lambda_role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

# IAM policy for logging from a lambda
resource "aws_iam_policy" "iam_policy_for_lambda" {

  name        = "aws_iam_policy_for_terraform_aws_lambda_role"
  path        = "/"
  description = "AWS IAM Policy for managing aws lambda role"
  policy      = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*",
      "Effect": "Allow"
    }
  ]
}
EOF
}

# Policy Attachment on the role.

resource "aws_iam_role_policy_attachment" "attach_iam_policy_to_iam_role" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.iam_policy_for_lambda.arn
}

# Generates an archive from content, a file, or a directory of files.
data "archive_file" "zip_the_python_code" {
  type        = "zip"
  source_dir  = "${path.module}/python/"
  output_path = "${path.module}/python/hello-python.zip"
}

# Create a lambda function
# In terraform ${path.module} is the current directory.
# the zip file will directly apply to the function during create
resource "aws_lambda_function" "terraform_lambda_func" {
  filename      = "${path.module}/python/hello-python.zip"
  function_name = "hello-python-Function"
  role          = aws_iam_role.lambda_role.arn
  handler       = "hello-python.lambda_handler"
  runtime       = "python3.12"
  depends_on    = [aws_iam_role_policy_attachment.attach_iam_policy_to_iam_role]
}

# API gateways
resource "aws_apigatewayv2_api" "endpoint_to_hello" {
  name          = "hello_endpoint"
  protocol_type = "HTTP"
}

resource "aws_cloudwatch_log_group" "hello_endpoint_gw" {
  name = "/aws/api-gw/${aws_apigatewayv2_api.endpoint_to_hello.name}"

  retention_in_days = 1
}

resource "aws_apigatewayv2_stage" "dev" {
  api_id      = aws_apigatewayv2_api.endpoint_to_hello.id
  name        = "dev"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.hello_endpoint_gw.arn

    format = jsonencode({
      requestId               = "$context.requestId"
      sourceIp                = "$context.identity.sourceIp"
      requestTime             = "$context.requestTime"
      protocol                = "$context.protocol"
      httpMethod              = "$context.httpMethod"
      resourcePath            = "$context.resourcePath"
      routeKey                = "$context.routeKey"
      status                  = "$context.status"
      responseLength          = "$context.responseLength"
      integrationErrorMessage = "$context.integrationErrorMessage"
      }
    )
  }
}

# integration btw Lambda and api_gateway
resource "aws_apigatewayv2_integration" "get_hello" {
  api_id = aws_apigatewayv2_api.endpoint_to_hello.id
  # pointing to a lambda create from above
  integration_uri    = aws_lambda_function.terraform_lambda_func.invoke_arn
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
}

# specify the target of different route
resource "aws_apigatewayv2_route" "get_hello" {
  api_id    = aws_apigatewayv2_api.endpoint_to_hello.id
  route_key = "GET /hello"
  # choose the gw integration for the lambda
  target = "integrations/${aws_apigatewayv2_integration.get_hello.id}"
}

# Grant permission to apigw to invoke lambda function
resource "aws_lambda_permission" "for_api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  principal     = "apigateway.amazonaws.com"
  function_name = aws_lambda_function.terraform_lambda_func.function_name

  source_arn = "${aws_apigatewayv2_api.endpoint_to_hello.execution_arn}/*/*"
}

output "hello_base_url" {
  value = aws_apigatewayv2_stage.dev.invoke_url
}