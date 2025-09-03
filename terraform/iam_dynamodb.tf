# 1. Tabela DynamoDB para controlar o estado das partições processadas
resource "aws_dynamodb_table" "partitions_state" {
  name         = "partitions-catalog-state"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "partition_key"

  attribute {
    name = "partition_key"
    type = "S"
  }
}

# 2. Política de permissões para a Lambda
data "aws_iam_policy_document" "lambda_policy_doc" {
  statement {
    actions = [
      # Permissões para SQS
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      # Permissões para DynamoDB
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      # Permissões para Glue
      "glue:GetTable",
      "glue:GetPartition",
      "glue:CreatePartition",
      # Permissões para Logs
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["*"]
  }
}

# 3. Role (Papel) que a Lambda irá assumir
resource "aws_iam_role" "lambda_execution_role" {
  name = "datahub-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# 4. Anexar a política de permissões à Role
resource "aws_iam_role_policy" "lambda_policy" {
  name   = "datahub-lambda-policy"
  role   = aws_iam_role.lambda_execution_role.id
  policy = data.aws_iam_policy_document.lambda_policy_doc.json
}