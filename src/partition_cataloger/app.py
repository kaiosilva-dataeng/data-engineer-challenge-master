import json
import os
from urllib.parse import unquote_plus

import boto3

# --- Configuração Inicial ---
# Como estamos no LocalStack, precisamos apontar o boto3 para o endpoint local.
# Em um ambiente AWS real, essa configuração não é necessária.
AWS_ENDPOINT_URL = os.environ.get("AWS_ENDPOINT_URL")
if AWS_ENDPOINT_URL:
    boto3.setup_default_session(
        region_name="us-east-1", aws_access_key_id="test", aws_secret_access_key="test"
    )
    S3_CLIENT = boto3.client("s3", endpoint_url=AWS_ENDPOINT_URL)
    GLUE_CLIENT = boto3.client("glue", endpoint_url=AWS_ENDPOINT_URL)
    DYNAMODB_CLIENT = boto3.client("dynamodb", endpoint_url=AWS_ENDPOINT_URL)
else:
    # Em um ambiente AWS real, o boto3 se configura sozinho.
    S3_CLIENT = boto3.client("s3")
    GLUE_CLIENT = boto3.client("glue")
    DYNAMODB_CLIENT = boto3.client("dynamodb")


# Nome da tabela DynamoDB e do Database do Glue, vindos de variáveis de ambiente
DYNAMODB_TABLE_NAME = os.environ.get("DYNAMODB_TABLE_NAME", "partitions-catalog-state")
GLUE_DATABASE_NAME = os.environ.get("GLUE_DATABASE_NAME", "datahub_db")


def handler(event, context):
    print("Evento recebido:", json.dumps(event))

    for record in event["Records"]:
        # 1. Parse do evento S3 que veio dentro da mensagem SQS
        sqs_body = json.loads(record["body"])
        s3_event = sqs_body["Message"]
        s3_event = json.loads(s3_event)

        # Pegar apenas o primeiro objeto do evento (geralmente só tem um)
        s3_record = s3_event["Records"][0]

        bucket_name = s3_record["s3"]["bucket"]["name"]
        # O caminho do arquivo pode ter caracteres especiais (ex: espaços), usamos unquote_plus
        object_key = unquote_plus(s3_record["s3"]["object"]["key"])

        print(f"Processando arquivo: s3://{bucket_name}/{object_key}")

        # 2. Extrair informações da partição a partir do caminho (key)
        # Ex: 'tabela_clientes/ano=2025/mes=09/dia=02/dados.parquet'
        parts = object_key.split("/")

        table_name = parts[0]
        # Pega todas as partes que parecem uma partição (contêm '=')
        partitions = [p for p in parts if "=" in p]
        partition_path = "/".join(partitions)

        if not partition_path:
            print(
                f"Arquivo '{object_key}' não parece estar em uma partição. Ignorando."
            )
            continue

        # 3. Verificar no DynamoDB (Controle de Estado)
        partition_key = f"{table_name}/{partition_path}"

        try:
            response = DYNAMODB_CLIENT.get_item(
                TableName=DYNAMODB_TABLE_NAME,
                Key={"partition_key": {"S": partition_key}},
            )
            if "Item" in response:
                print(f"Partição '{partition_key}' já foi processada. Ignorando.")
                continue  # Pula para o próximo registro no evento
        except Exception as e:
            print(f"Erro ao verificar DynamoDB: {e}")
            raise e  # Falha a execução para tentar novamente mais tarde

        print(f"Partição nova encontrada: '{partition_key}'. Adicionando ao Glue...")

        # 4. Adicionar a partição no Glue
        partition_values = [p.split("=")[1] for p in partitions]
        s3_location = f"s3://{bucket_name}/{'/'.join(parts[:-1])}/"

        try:
            # Precisamos pegar o schema da tabela para usar na partição
            print("--- DEBUG INFO ---")
            print(f"Tentando buscar a tabela: '{table_name}'")
            print(f"No banco de dados do Glue: '{GLUE_DATABASE_NAME}'")
            print("--------------------")
            table_info = GLUE_CLIENT.get_table(
                DatabaseName=GLUE_DATABASE_NAME, Name=table_name
            )
            storage_descriptor = table_info["Table"]["StorageDescriptor"]

            GLUE_CLIENT.create_partition(
                DatabaseName=GLUE_DATABASE_NAME,
                TableName=table_name,
                PartitionInput={
                    "Values": partition_values,
                    "StorageDescriptor": {
                        "Location": s3_location,
                        "Columns": storage_descriptor.get("Columns", []),
                        "InputFormat": storage_descriptor.get("InputFormat"),
                        "OutputFormat": storage_descriptor.get("OutputFormat"),
                        "SerdeInfo": storage_descriptor.get("SerdeInfo"),
                    },
                },
            )
            print("Partição adicionada ao Glue com sucesso!")
        except Exception as e:
            print(f"Erro ao criar partição no Glue: {e}")
            raise e

        # 5. Atualizar o estado no DynamoDB
        try:
            DYNAMODB_CLIENT.put_item(
                TableName=DYNAMODB_TABLE_NAME,
                Item={"partition_key": {"S": partition_key}},
            )
            print(f"Estado da partição '{partition_key}' salvo no DynamoDB.")
        except Exception as e:
            print(f"Erro ao salvar estado no DynamoDB: {e}")
            raise e

    return {
        "statusCode": 200,
        "body": json.dumps("Processamento concluído com sucesso!"),
    }
