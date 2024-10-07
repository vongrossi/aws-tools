import boto3
import argparse
import sys

def calculate_size(size, size_table):
    """
    Calcula dinamicamente a unidade apropriada para o tamanho fornecido.
    :param size: Tamanho em bytes a ser convertido.
    :param size_table: Dicionário que mapeia unidades de tamanho.
    :return: Representação em string do tamanho com a unidade apropriada.
    """
    count = 0
    while size >= 1024 and count < len(size_table) - 1:
        size /= 1024
        count += 1
    return f"{round(size, 2)} {size_table[count]}"

def get_s3_statistics(bucket, prefix):
    """
    Recupera estatísticas do bucket S3 especificado e prefixo.
    :param bucket: Nome do bucket S3.
    :param prefix: Prefixo dos objetos S3.
    :return: Dicionário contendo as estatísticas.
    """
    size_table = {0: "Bs", 1: "KBs", 2: "MBs", 3: "GBs", 4: "TBs", 5: "PBs", 6: "EBs"}
    s3_client = boto3.client("s3")
    paginator = s3_client.get_paginator("list_object_versions")
    operation_parameters = {"Bucket": bucket}
    if prefix:
        operation_parameters["Prefix"] = prefix

    delete_marker_count = 0
    versioned_object_count = 0
    versioned_object_size = 0
    current_object_count = 0
    current_object_size = 0

    print("$ Calculando, por favor aguarde... isso pode levar algum tempo")
    try:
        for page in paginator.paginate(**operation_parameters):
            if "DeleteMarkers" in page:
                delete_marker_count += len(page["DeleteMarkers"])

            if "Versions" in page:
                for version in page["Versions"]:
                    if not version["IsLatest"]:
                        versioned_object_count += 1
                        versioned_object_size += version["Size"]
                    else:
                        current_object_count += 1
                        current_object_size += version["Size"]
    except s3_client.exceptions.NoSuchBucket:
        print(f"Erro: O bucket '{bucket}' não existe.")
        sys.exit(1)
    except Exception as e:
        print(f"Erro: {e}")
        sys.exit(1)

    total_size = versioned_object_size + current_object_size

    return {
        "bucket": bucket,
        "prefix": prefix if prefix else "(nenhum)",
        "delete_marker_count": delete_marker_count,
        "current_object_count": current_object_count,
        "current_object_size": calculate_size(current_object_size, size_table),
        "versioned_object_count": versioned_object_count,
        "versioned_object_size": calculate_size(versioned_object_size, size_table),
        "total_size": calculate_size(total_size, size_table),
    }

def main():
    parser = argparse.ArgumentParser(
        description='Calcula estatísticas de armazenamento do bucket S3.',
        usage='python calculate_size.py -b <bucket_name> [-p <prefix>]'
    )
    parser.add_argument('-b', '--bucket', required=True, help='Nome do bucket S3')
    parser.add_argument('-p', '--prefix', help='Prefixo dos objetos S3 (opcional)')

    args = parser.parse_args()
    stats = get_s3_statistics(args.bucket, args.prefix)

    print("\n")
    print("-" * 10)
    print(f"$ Nome do Bucket: {stats['bucket']}")
    print(f"$ Prefixo: {stats['prefix']}")
    print(f"$ Total de Delete Markers: {stats['delete_marker_count']}")
    print(f"$ Número de Objetos Atuais: {stats['current_object_count']}")
    print(f"$ Tamanho dos Objetos Atuais: {stats['current_object_size']}")
    print(f"$ Número de Objetos Não Atuais: {stats['versioned_object_count']}")
    print(f"$ Tamanho dos Objetos Não Atuais: {stats['versioned_object_size']}")
    print(f"$ Tamanho Total (Atual + Não Atuais): {stats['total_size']}")
    print("-" * 10)
    print("\n")
    print("$ Processo concluído com sucesso")
    print("\n")

if __name__ == "__main__":
    main()
