# Empacota o código da nossa Lambda em um arquivo .zip
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../src/partition_cataloger"
  output_path = "${path.module}/../dist/partition_cataloger.zip"
}

# Recurso da Função Lambda
resource "aws_lambda_function" "partition_cataloger" {
  function_name = "PartitionCatalogerFunction"
  # O nome do arquivo zip gerado e seu hash (para detectar mudanças)
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  
  role    = aws_iam_role.lambda_execution_role.arn
  handler = "app.handler" # Arquivo 'app.py', função 'handler'
  runtime = "python3.9"
  timeout = 30 # Segundos

  environment {
    variables = {
      # Aponta a Lambda para o LocalStack (essencial para o ambiente local)
      AWS_ENDPOINT_URL      = "http://localstack:4566"
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.partitions_state.name
      GLUE_DATABASE_NAME  = aws_glue_catalog_database.datahub_db.name
    }
  }
}

# Conexão entre a fila SQS e a função Lambda (o "gatilho")
resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.partitions_queue.arn
  function_name    = aws_lambda_function.partition_cataloger.arn
  batch_size       = 1 # Processar uma mensagem de cada vez
}