# O recurso do Banco de Dados
resource "aws_glue_catalog_database" "datahub_db" {
  name = "datahub_db"
}

# Recurso para as Tabelas no Glue Catalog
resource "aws_glue_catalog_table" "generic_tables" {
  # O for_each vai iterar sobre cada chave do mapa var.glue_tables
  for_each = var.glue_tables

  # "each.key" é o nome da tabela (ex: "tabela_clientes")
  name          = each.key
  database_name = aws_glue_catalog_database.datahub_db.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "EXTERNAL"            = "TRUE"
    "parquet.compression" = "SNAPPY"
  }

  # Bloco dinâmico para criar as colunas de partição
  dynamic "partition_keys" {
    # "each.value" é o objeto com colunas e partições
    for_each = each.value.partition_keys
    content {
      name = partition_keys.value.name
      type = partition_keys.value.type
    }
  }

  storage_descriptor {
    # Bloco dinâmico para criar as colunas do schema
    dynamic "columns" {
      for_each = each.value.columns
      content {
        name = columns.value.name
        type = columns.value.type
      }
    }

    # A localização no S3 também é dinâmica, baseada no nome da tabela
    location      = "s3://${aws_s3_bucket.datahub_storage.bucket}/${each.key}/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"
    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }
  }

  depends_on = [aws_s3_bucket.datahub_storage]
}