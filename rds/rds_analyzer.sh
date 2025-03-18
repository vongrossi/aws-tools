#!/bin/bash

# Função para mostrar mensagens de log
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >&2
}

# Printa Helper
show_usage() {
    echo "Uso: $0 <região-aws> [arquivo-saída]"
    echo "Exemplo: $0 sa-east-1 output.json"
    echo ""
    echo "Este script lista todos os RDS na região especificada, mostrando em formato JSON:"
    echo "- Engine e versão"
    echo "- Tipo de storage (gp2, gp3, io1, etc.)"
    echo "- Família de instância"
    echo "- Status do binary logging (parâmetro específico por engine)"
    echo "- Se a instância pertence a um cluster"
    echo "- Endpoint de leitura (se houver réplicas de leitura)"
    echo "- Janelas de manutenção e backup (se aplicável ao cluster)"
    echo "- Prazo de retenção de backup (em dias)"
    echo "- Configuração de Zero ETL (se houver)"
    echo "- Status do Performance Insights"
    echo "- Se é serverless ou não"
    echo "- Status do CDC (Change Data Capture) para PostgreSQL e MySQL"
    echo "- Informações sobre read replicas"
    echo ""
    echo "Se um arquivo de saída for especificado, o JSON será gravado nele. Caso contrário, o JSON será exibido na saída padrão."
    exit 1
}

# Check region != null
if [ $# -eq 0 ]; then
    show_usage
fi

REGION="$1"
OUTPUT_FILE="$2"

# Verificar CDC para PostgreSQL
check_postgres_cdc() {
    local cluster_param_group="$1"
    
    if [ -z "$cluster_param_group" ] || [ "$cluster_param_group" = "null" ]; then
        echo "false"
        return
    fi
    
    log_message "    Verificando CDC para PostgreSQL no parameter group $cluster_param_group..."
    
    # Verificar wal_level
    wal_level=$(aws rds describe-db-cluster-parameters --region $REGION --db-cluster-parameter-group-name $cluster_param_group --query "Parameters[?ParameterName=='wal_level'].ParameterValue" --output text 2>/dev/null)
    wal_level=$(echo "$wal_level" | xargs | tr '[:upper:]' '[:lower:]')
    log_message "    wal_level = '$wal_level'"
    
    if [ "$wal_level" = "logical" ]; then
        log_message "    CDC detectado via wal_level=logical"
        echo "true"
        return
    fi
    
    # Verificar rds.logical_replication
    logical_replication=$(aws rds describe-db-cluster-parameters --region $REGION --db-cluster-parameter-group-name $cluster_param_group --query "Parameters[?ParameterName=='rds.logical_replication'].ParameterValue" --output text 2>/dev/null)
    logical_replication=$(echo "$logical_replication" | xargs | tr '[:upper:]' '[:lower:]')
    log_message "    rds.logical_replication = '$logical_replication'"
    
    if [ "$logical_replication" = "1" ] || [ "$logical_replication" = "on" ] || [ "$logical_replication" = "true" ]; then
        log_message "    CDC detectado via rds.logical_replication=$logical_replication"
        echo "true"
        return
    fi
    
    log_message "    CDC não detectado para PostgreSQL"
    echo "false"
}

# Verificar CDC para MySQL
check_mysql_cdc() {
    local cluster_param_group="$1"
    
    if [ -z "$cluster_param_group" ] || [ "$cluster_param_group" = "null" ]; then
        echo "false"
        return
    fi
    
    log_message "    Verificando CDC para MySQL no parameter group $cluster_param_group..."
    
    # Verificar binlog_format
    binlog_format=$(aws rds describe-db-cluster-parameters --region $REGION --db-cluster-parameter-group-name $cluster_param_group --query "Parameters[?ParameterName=='binlog_format'].ParameterValue" --output text 2>/dev/null)
    binlog_format=$(echo "$binlog_format" | xargs | tr '[:lower:]' '[:upper:]')
    log_message "    binlog_format = '$binlog_format'"
    
    if [ "$binlog_format" = "ROW" ]; then
        log_message "    CDC detectado via binlog_format=ROW"
        echo "true"
        return
    fi
    
    log_message "    CDC não detectado para MySQL"
    echo "false"
}

# Obtém detalhes de uma instância RDS
get_instance_details() {
    local instance="$1"
    aws rds describe-db-instances --region $REGION --db-instance-identifier $instance --query 'DBInstances[0]' --output json
}

# Obtém detalhes de um cluster RDS
get_cluster_details() {
    local cluster="$1"
    aws rds describe-db-clusters --region $REGION --db-cluster-identifier $cluster --query 'DBClusters[0]' --output json
}

# Iniciar JSON output
json_output="{"
json_output+="\n  \"db_resources\": ["

# Obter todos os clusters na região
log_message "Iniciando busca de clusters de banco de dados na região $REGION..."
clusters=$(aws rds describe-db-clusters --region $REGION --query 'DBClusters[].DBClusterIdentifier' --output text)
cluster_count=$(echo "$clusters" | wc -w)
log_message "Encontrados $cluster_count clusters de banco de dados."

# Obter todas as instâncias RDS standalone (que não pertencem a clusters)
log_message "Buscando instâncias standalone (que não pertencem a clusters)..."
standalone_instances=$(aws rds describe-db-instances --region $REGION --query 'DBInstances[?DBClusterIdentifier==`null`].DBInstanceIdentifier' --output text)
standalone_count=$(echo "$standalone_instances" | wc -w)
log_message "Encontradas $standalone_count instâncias standalone."

# Lista para rastrear todos os recursos processados (para evitar duplicatas em JSON)
processed_resources=()
first_resource=true

# Processar todos os clusters
if [ -n "$clusters" ]; then
    current_cluster=0
    for cluster in $clusters; do
        current_cluster=$((current_cluster + 1))
        log_message "Processando cluster ($current_cluster/$cluster_count): $cluster"
        
        # Adicionar separador de objeto JSON se não for o primeiro recurso
        if [ "$first_resource" = true ]; then
            first_resource=false
        else
            json_output+="\n  },"
        fi
        
        # Obter detalhes do cluster
        cluster_details=$(get_cluster_details "$cluster")
        engine=$(echo "$cluster_details" | jq -r '.Engine')
        engine_version=$(echo "$cluster_details" | jq -r '.EngineVersion')
        cluster_param_group=$(echo "$cluster_details" | jq -r '.DBClusterParameterGroup')
        preferred_maintenance_window=$(echo "$cluster_details" | jq -r '.PreferredMaintenanceWindow')
        preferred_backup_window=$(echo "$cluster_details" | jq -r '.PreferredBackupWindow')
        backup_retention_period=$(echo "$cluster_details" | jq -r '.BackupRetentionPeriod')
        
        # Verificar se é serverless
        is_serverless=$(echo "$cluster_details" | jq -r 'if .EngineMode == "serverless" then true else false end')
        
        # Verificar CDC com base no engine
        cdc_enabled="false"
        if [[ "$engine" == "postgres" || "$engine" == "aurora-postgresql" ]]; then
            cdc_enabled=$(check_postgres_cdc "$cluster_param_group")
        elif [[ "$engine" == "mysql" || "$engine" == "aurora-mysql" ]]; then
            cdc_enabled=$(check_mysql_cdc "$cluster_param_group")
        fi
        
        # Iniciar objeto JSON para este cluster
        json_output+="\n  {"
        json_output+="\n    \"resource_type\": \"cluster\","
        json_output+="\n    \"identifier\": \"$cluster\","
        json_output+="\n    \"engine\": \"$engine\","
        json_output+="\n    \"version\": \"$engine_version\","
        json_output+="\n    \"parameter_group\": \"$cluster_param_group\","
        json_output+="\n    \"maintenance_window\": \"$preferred_maintenance_window\","
        json_output+="\n    \"backup_window\": \"$preferred_backup_window\","
        json_output+="\n    \"backup_retention_period\": $backup_retention_period,"
        json_output+="\n    \"is_serverless\": $is_serverless,"
        json_output+="\n    \"cdc_enabled\": $cdc_enabled,"
        
        # Obter instâncias do cluster
        log_message "Obtendo instâncias para o cluster $cluster..."
        cluster_instances=$(aws rds describe-db-instances --region $REGION --query "DBInstances[?DBClusterIdentifier=='$cluster'].DBInstanceIdentifier" --output text)
        instance_count=$(echo "$cluster_instances" | wc -w)
        log_message "Encontradas $instance_count instâncias para o cluster $cluster"
        
        # Adicionar instâncias do cluster ao JSON
        json_output+="\n    \"instances\": ["
        
        if [ -n "$cluster_instances" ]; then
            first_instance=true
            for instance in $cluster_instances; do
                # Adicionar esta instância à lista de recursos processados
                processed_resources+=("$instance")
                
                # Adicionar separador de instância JSON se não for a primeira instância
                if [ "$first_instance" = true ]; then
                    first_instance=false
                else
                    json_output+=","
                fi
                
                log_message "Processando instância $instance do cluster $cluster..."
                
                # Obter detalhes da instância
                instance_details=$(get_instance_details "$instance")
                instance_class=$(echo "$instance_details" | jq -r '.DBInstanceClass')
                storage_type=$(echo "$instance_details" | jq -r '.StorageType')
                performance_insights_enabled=$(echo "$instance_details" | jq -r '.PerformanceInsightsEnabled')
                
                # Verificar se é uma réplica de leitura
                is_read_replica=$(echo "$instance_details" | jq -r 'if .ReadReplicaSourceDBInstanceIdentifier != null then true else false end')
                
                # Verificar se é serverless (na instância)
                instance_serverless=$(echo "$instance_details" | jq -r 'if .ServerlessV2ScalingConfiguration != null or (.DBInstanceClass | startswith("db.serverless")) then true else false end')
                
                # Adicionar ao JSON
                json_output+="\n      {"
                json_output+="\n        \"instance_identifier\": \"$instance\","
                json_output+="\n        \"instance_class\": \"$instance_class\","
                json_output+="\n        \"storage_type\": \"$storage_type\","
                json_output+="\n        \"performance_insights_enabled\": $performance_insights_enabled,"
                json_output+="\n        \"is_read_replica\": $is_read_replica,"
                json_output+="\n        \"is_serverless\": $instance_serverless"
                json_output+="\n      }"
            done
        fi
        
        json_output+="\n    ]"
    done
fi

# Processar instâncias standalone
if [ -n "$standalone_instances" ]; then
    current_standalone=0
    for instance in $standalone_instances; do
        # Verificar se já processamos esta instância como parte de um cluster
        if [[ " ${processed_resources[@]} " =~ " ${instance} " ]]; then
            continue
        fi
        
        current_standalone=$((current_standalone + 1))
        log_message "Processando instância standalone ($current_standalone/$standalone_count): $instance"
        
        # Adicionar separador de objeto JSON se não for o primeiro recurso
        if [ "$first_resource" = true ]; then
            first_resource=false
        else
            json_output+="\n  },"
        fi
        
        # Obter detalhes da instância
        instance_details=$(get_instance_details "$instance")
        engine=$(echo "$instance_details" | jq -r '.Engine')
        engine_version=$(echo "$instance_details" | jq -r '.EngineVersion')
        instance_class=$(echo "$instance_details" | jq -r '.DBInstanceClass')
        storage_type=$(echo "$instance_details" | jq -r '.StorageType')
        performance_insights_enabled=$(echo "$instance_details" | jq -r '.PerformanceInsightsEnabled')
        preferred_maintenance_window=$(echo "$instance_details" | jq -r '.PreferredMaintenanceWindow')
        preferred_backup_window=$(echo "$instance_details" | jq -r '.PreferredBackupWindow')
        backup_retention_period=$(echo "$instance_details" | jq -r '.BackupRetentionPeriod')
        param_group=$(echo "$instance_details" | jq -r '.DBParameterGroups[0].DBParameterGroupName')
        
        # Verificar se é serverless
        is_serverless=$(echo "$instance_details" | jq -r 'if .ServerlessV2ScalingConfiguration != null or (.DBInstanceClass | startswith("db.serverless")) then true else false end')
        
        # Verificar se é uma réplica de leitura
        is_read_replica=$(echo "$instance_details" | jq -r 'if .ReadReplicaSourceDBInstanceIdentifier != null then true else false end')
        read_replica_source=$(echo "$instance_details" | jq -r '.ReadReplicaSourceDBInstanceIdentifier')
        
        # Verificar CDC com base no engine
        cdc_enabled="false"
        if [ -n "$param_group" ] && [ "$param_group" != "null" ]; then
            log_message "Verificando CDC para instância standalone $instance..."
            if [[ "$engine" == "postgres" || "$engine" == "aurora-postgresql" ]]; then
                # Verificar rds.logical_replication
                logical_replication=$(aws rds describe-db-parameters --region $REGION --db-parameter-group-name $param_group --query "Parameters[?ParameterName=='rds.logical_replication'].ParameterValue" --output text 2>/dev/null)
                logical_replication=$(echo "$logical_replication" | xargs | tr '[:upper:]' '[:lower:]')
                log_message "  rds.logical_replication = '$logical_replication'"
                
                if [ "$logical_replication" = "1" ] || [ "$logical_replication" = "on" ] || [ "$logical_replication" = "true" ]; then
                    cdc_enabled="true"
                    log_message "  CDC detectado via rds.logical_replication=$logical_replication"
                else
                    # Verificar wal_level
                    wal_level=$(aws rds describe-db-parameters --region $REGION --db-parameter-group-name $param_group --query "Parameters[?ParameterName=='wal_level'].ParameterValue" --output text 2>/dev/null)
                    wal_level=$(echo "$wal_level" | xargs | tr '[:upper:]' '[:lower:]')
                    log_message "  wal_level = '$wal_level'"
                    
                    if [ "$wal_level" = "logical" ]; then
                        cdc_enabled="true"
                        log_message "  CDC detectado via wal_level=logical"
                    else
                        log_message "  CDC não detectado para PostgreSQL standalone"
                    fi
                fi
            elif [[ "$engine" == "mysql" || "$engine" == "aurora-mysql" ]]; then
                # Verificar binlog_format
                binlog_format=$(aws rds describe-db-parameters --region $REGION --db-parameter-group-name $param_group --query "Parameters[?ParameterName=='binlog_format'].ParameterValue" --output text 2>/dev/null)
                binlog_format=$(echo "$binlog_format" | xargs | tr '[:lower:]' '[:upper:]')
                log_message "  binlog_format = '$binlog_format'"
                
                if [ "$binlog_format" = "ROW" ]; then
                    cdc_enabled="true"
                    log_message "  CDC detectado via binlog_format=ROW"
                else
                    log_message "  CDC não detectado para MySQL standalone"
                fi
            fi
        else
            log_message "  Sem parameter group para verificar CDC na instância standalone $instance"
        fi
        
        # Verificar réplicas de leitura desta instância
        log_message "Verificando réplicas de leitura para instância $instance..."
        read_replicas=$(aws rds describe-db-instances --region $REGION --query "DBInstances[?ReadReplicaSourceDBInstanceIdentifier=='$instance'].DBInstanceIdentifier" --output json)
        
        # Iniciar objeto JSON para esta instância standalone
        json_output+="\n  {"
        json_output+="\n    \"resource_type\": \"instance\","
        json_output+="\n    \"identifier\": \"$instance\","
        json_output+="\n    \"engine\": \"$engine\","
        json_output+="\n    \"version\": \"$engine_version\","
        json_output+="\n    \"instance_class\": \"$instance_class\","
        json_output+="\n    \"storage_type\": \"$storage_type\","
        json_output+="\n    \"parameter_group\": \"$param_group\","
        json_output+="\n    \"maintenance_window\": \"$preferred_maintenance_window\","
        json_output+="\n    \"backup_window\": \"$preferred_backup_window\","
        json_output+="\n    \"backup_retention_period\": $backup_retention_period,"
        json_output+="\n    \"performance_insights_enabled\": $performance_insights_enabled,"
        json_output+="\n    \"is_serverless\": $is_serverless,"
        json_output+="\n    \"cdc_enabled\": $cdc_enabled,"
        json_output+="\n    \"is_read_replica\": $is_read_replica,"
        
        if [ "$is_read_replica" = "true" ]; then
            json_output+="\n    \"read_replica_source\": \"$read_replica_source\","
        fi
        
        json_output+="\n    \"read_replicas\": $read_replicas"
    done
fi

# Finalizar JSON
if [ "$first_resource" = false ]; then
    json_output+="\n  }"
fi
json_output+="\n  ]"
json_output+="\n}"

# Escrever JSON output
log_message "Processamento completo! Gerando saída JSON..."

if [ -n "$OUTPUT_FILE" ]; then
    echo -e "$json_output" > "$OUTPUT_FILE"
    log_message "Finalizado! O resultado foi gravado no arquivo $OUTPUT_FILE"
    echo "JSON output written to $OUTPUT_FILE"
else
    log_message "Finalizado! Exibindo resultado no console..."
    echo -e "$json_output"
fi

log_message "Script concluído com sucesso!"
