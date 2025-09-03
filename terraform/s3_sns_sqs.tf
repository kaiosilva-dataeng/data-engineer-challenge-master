# 1. Bucket S3 para receber os dados
resource "aws_s3_bucket" "datahub_storage" {
  bucket = "datahub"
}

# 2. Tópico SNS para receber as notificações do S3
resource "aws_sns_topic" "s3_events_topic" {
  name = "datahub-s3-new-object-events"
}

# 3. Fila SQS que será lida pela Lambda
resource "aws_sqs_queue" "partitions_queue" {
  name = "new-partitions-to-process"
}

# 4. Conexão entre S3 e SNS: notificar o tópico quando um .parquet for criado
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.datahub_storage.id
  topic {
    topic_arn     = aws_sns_topic.s3_events_topic.arn
    events        = ["s3:ObjectCreated:*"]
  }
}

# 5. Conexão entre SNS e SQS: inscrever a fila no tópico
resource "aws_sns_topic_subscription" "queue_subscription" {
  topic_arn = aws_sns_topic.s3_events_topic.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.partitions_queue.arn
}

# 6. Política do Tópico SNS para permitir que o S3 publique mensagens
resource "aws_sns_topic_policy" "s3_publish_policy" {
  arn    = aws_sns_topic.s3_events_topic.arn
  policy = data.aws_iam_policy_document.sns_topic_policy_doc.json
}

data "aws_iam_policy_document" "sns_topic_policy_doc" {
  statement {
    effect  = "Allow"
    actions = ["SNS:Publish"]

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    # Recurso: O nosso tópico SNS
    resources = [aws_sns_topic.s3_events_topic.arn]

    # Condição: Apenas permitir publicações originadas do nosso bucket S3
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.datahub_storage.arn]
    }
  }
}