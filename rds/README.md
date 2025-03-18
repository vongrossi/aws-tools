# RDS Analyzer

Script para análise detalhada de recursos Amazon RDS (instâncias e clusters) com foco em configurações de CDC (Change Data Capture).

## 📜 Descrição

Este script bash analisa todos os recursos RDS (incluindo Aurora) em uma região AWS específica e gera um relatório detalhado em formato JSON. Ele foi desenvolvido para identificar corretamente configurações como:

- Informações básicas (engine, versão, tipo de armazenamento)
- Status do CDC (Change Data Capture) para PostgreSQL e MySQL/Aurora
- Detecção de instâncias serverless
- Relações entre clusters e instâncias
- Réplicas de leitura
- Configurações de backup e manutenção

O script estrutura os dados hierarquicamente por clusters (quando aplicável) e instâncias standalone, facilitando a visualização das relações entre esses recursos.

## ❗ Requisitos

- AWS CLI configurado com as permissões adequadas
- jq instalado para processamento de JSON
- Permissões para chamar as APIs DescribeDBInstances, DescribeDBClusters, DescribeDBParameters e DescribeDBClusterParameters

## 👨‍💻 Uso

```bash
./rds-analyzer.sh <região-aws> [arquivo-saída]
```

### Exemplos:

**Exibir o resultado no terminal:**
```bash
./rds-analyzer.sh us-east-1
```

**Salvar o resultado em um arquivo:**
```bash
./rds-analyzer.sh sa-east-1 resultado-rds.json
```

## Configurações Detectadas

### Para Clusters e Instâncias
- **Tipo de recurso:** cluster ou instância standalone
- **Identificador:** nome do recurso
- **Engine e versão:** tipo e versão do banco de dados
- **Parameter group:** grupo de parâmetros associado
- **Configurações de backup:** janela e período de retenção
- **Configurações de manutenção:** janela de manutenção

### Para CDC (Change Data Capture)
- **PostgreSQL:** verifica `wal_level = logical` ou `rds.logical_replication = 1/true/on`
- **MySQL/Aurora MySQL:** verifica `binlog_format = ROW`

### Para Instâncias
- **Classe da instância:** tipo da instância (ex: db.t3.medium)
- **Tipo de armazenamento:** tipo de storage (gp2, gp3, io1, etc.)
- **Performance Insights:** status do Performance Insights
- **Serverless:** detecção se é uma instância serverless
- **Réplicas:** informações sobre réplicas de leitura

## Estrutura de Saída

A saída JSON segue este formato:

```json
{
  "db_resources": [
    {
      "resource_type": "cluster",
      "identifier": "nome-do-cluster",
      "engine": "aurora-postgresql",
      "version": "13.8",
      "parameter_group": "default.aurora-postgresql13",
      "maintenance_window": "sat:05:00-sat:05:30",
      "backup_window": "03:00-04:00",
      "backup_retention_period": 7,
      "is_serverless": false,
      "cdc_enabled": true,
      "instances": [
        {
          "instance_identifier": "instancia-writer",
          "instance_class": "db.r5.large",
          "storage_type": "aurora",
          "performance_insights_enabled": true,
          "is_read_replica": false,
          "is_serverless": false
        },
        {
          "instance_identifier": "instancia-reader",
          "instance_class": "db.r5.large",
          "storage_type": "aurora",
          "performance_insights_enabled": true,
          "is_read_replica": true,
          "is_serverless": false
        }
      ]
    },
    {
      "resource_type": "instance",
      "identifier": "instancia-standalone",
      "engine": "postgres",
      "version": "13.4",
      "instance_class": "db.t3.medium",
      "storage_type": "gp2",
      "parameter_group": "default.postgres13",
      "maintenance_window": "mon:05:00-mon:05:30",
      "backup_window": "04:00-05:00",
      "backup_retention_period": 7,
      "performance_insights_enabled": false,
      "is_serverless": false,
      "cdc_enabled": false,
      "is_read_replica": false,
      "read_replicas": []
    }
  ]
}
```

## 📈 Logs de Execução

O script gera mensagens detalhadas de log durante a execução, mostrando:

- Início e progresso da análise
- Detalhes da detecção de cada recurso
- Progresso no processamento de clusters e instâncias
- Verificações de CDC e seus resultados
- Confirmação do término da execução

## 📋 Notas 

- Para bancos Aurora, as configurações de CDC são definidas no parameter group do **cluster**, não da instância
- Instâncias em um cluster Aurora sempre compartilham as mesmas configurações de CDC
- A detecção de CDC em bancos standalone depende dos parâmetros configurados no parameter group da instância
