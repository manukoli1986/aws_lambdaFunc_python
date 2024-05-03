provider "aws" {
  region  = "us-west-1"
  profile = "mayank" #NEED TO CHANGE
}

resource "aws_iam_role" "pricing_demo" {
  name = "pricing_demo"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AssumeRole",
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF

}

resource "aws_iam_role_policy_attachment" "pricing_demo_eni_attachment" {
  role       = aws_iam_role.pricing_demo.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_cloudwatch_log_group" "pricing_demo" {
  name = "/aws/lambda/pricing_demo"
}

resource "aws_vpc" "pricing_demo" {
  cidr_block           = "172.16.0.0/18"
  enable_dns_hostnames = true
  enable_dns_support   = true
}

resource "aws_internet_gateway" "pricing_demo" {
  vpc_id = aws_vpc.pricing_demo.id
}

data "aws_availability_zones" "available" {}

resource "aws_subnet" "pricing_demo" {
  vpc_id            = aws_vpc.pricing_demo.id
  cidr_block        = cidrsubnet(aws_vpc.pricing_demo.cidr_block, 8, 0)
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "${data.aws_availability_zones.available.names[0]}_pricing_demo"
  }
}

resource "aws_route_table" "pricing_demo" {
  vpc_id = aws_vpc.pricing_demo.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.pricing_demo.id
  }

  tags = {
    Name = "pricing_demo"
  }
}

resource "aws_route_table_association" "pricing_demo" {
  depends_on = [aws_subnet.pricing_demo]

  subnet_id      = aws_subnet.pricing_demo.id
  route_table_id = aws_route_table.pricing_demo.id
}

resource "aws_security_group" "pricing_demo" {
  name        = "pricing_demo"
  description = "pricing_demo"
  vpc_id      = aws_vpc.pricing_demo.id

  # allow no inbound traffic
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/32"]
  }

  # allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

## Added below block to store python code in a ZIP file in order to upload to AWS
data "archive_file" "lambda" {
  type        = "zip"
  source_file = "pricing.py"
  output_path = "lambda_function_payload.zip"
}

resource "aws_lambda_function" "pricing_demo" {
  function_name    = "pricingDemo"
  filename         = "${path.module}/lambda_function_payload.zip"
  source_code_hash = data.archive_file.lambda.output_base64sha256
  handler          = "pricing.lambda_handler"
  runtime = "python3.12"
  role = aws_iam_role.pricing_demo.arn
  vpc_config {
    subnet_ids         = [aws_subnet.pricing_demo.id]
    security_group_ids = [aws_security_group.pricing_demo.id]
  }
  environment {
    variables = {
      SEED = "0"
    }
  }
}

resource "aws_lambda_function_url" "pricing_demo" {
  function_name      = aws_lambda_function.pricing_demo.function_name
  authorization_type = "NONE"
  cors {
    allow_credentials = false
    allow_headers     = ["*"]
    allow_methods     = ["POST", "GET"]
    allow_origins     = ["*"]
    max_age           = 3600
  }
}

#################################
resource "aws_cloudwatch_metric_alarm" "pricing_demo_errors" {
  alarm_name          = "pricing_demo_errors"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Sum"
  threshold           = "1"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.pricing_demo.function_name
  }
}

output "lambda_function_url" {
  value = aws_lambda_function_url.pricing_demo.function_url
}