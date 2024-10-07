
## Introdução

Ao longo do tempo, buckets S3 podem acumular objetos e versões que ocupam espaço de armazenamento e podem gerar custos adicionais. Este projeto ajuda a:

-   Identificar o número e tamanho dos objetos atuais (versões mais recentes).
-   Identificar o número e tamanho das versões anteriores dos objetos.
-   Contabilizar marcadores de exclusão que podem afetar políticas de versionamento.
-   Fornecer uma visão geral do uso total de armazenamento no bucket.

## Pré-requisitos

-   **Conta AWS**: Uma conta na AWS com acesso ao bucket S3 desejado.
-   **Credenciais AWS Configuradas**: As credenciais devem ter permissões para listar versões de objetos no S3.
-   **Python 3.x** ou **Go 1.13+** instalado em sua máquina.

## Instalação

### Script em Python

1.  **Clonar o Repositório** :
```bash
git clone https://github.com/vongrossi/aws-tools
cd aws-tools/s3/
```
2.  **Caso use python** :
```bash
pip install boto3
```
## Uso

Execute o script `calculate_size.py` com os seguintes parâmetros:

-   `-b` ou `--bucket`: **(Obrigatório)** Nome do bucket S3.
-   `-p` ou `--prefix`: **(Opcional)** Prefixo dos objetos S3.

```python
python script.py -b nome-do-seu-bucket -p seu/prefixo/` 
```

## Exemplo de Saída

```bash
----------
$ Nome do Bucket: meu-bucket
$ Prefixo: meu/prefixo/
$ Total de Delete Markers: 10
$ Número de Objetos Atuais: 150
$ Tamanho dos Objetos Atuais: 1.2 GBs
$ Número de Objetos Não Atuais: 50
$ Tamanho dos Objetos Não Atuais: 500.5 MBs
$ Tamanho Total (Atual + Não Atuais): 1.7 GBs
----------
 $ Processo concluído com sucesso 
```

### Script em Go

```bash
go mod init s3dirsize
go get -u github.com/aws/aws-sdk-go 
```
**Notas Importantes para o Script em Go:**

-   **Nome do Aplicativo**: O aplicativo é chamado `s3dirsize`.
    
-   **Inicialização do Módulo Go**: É necessário inicializar o módulo Go antes de executar o script. Isso é feito usando `go mod init s3dirsize`.
    
-   **Definir a Região AWS**: Certifique-se de que a região AWS esteja especificada no código ou configurada através de variáveis de ambiente ou arquivo de configuração. No código, você pode alterar a região na seguinte linha:

## Build

```bash
go build -o s3dirsize main.go
```
## Uso 

Execute o script `s3dirsize` com os seguintes parâmetros:

-   `-b`: **(Obrigatório)** Nome do bucket S3.
-   `-p`: **(Opcional)** Prefixo dos objetos S3.

**Exemplo:**

```bash
./s3dirsize -b nome-do-seu-bucket -p seu/prefixo/
```

```bash
----------
$ Nome do Bucket: meu-bucket
$ Prefixo: meu/prefixo/
$ Total de Delete Markers: 10
$ Número de Objetos Atuais: 150
$ Tamanho dos Objetos Atuais: 1.2 GBs
$ Número de Objetos Não Atuais: 50
$ Tamanho dos Objetos Não Atuais: 500.5 MBs
$ Tamanho Total (Atual + Não Atuais): 1.7 GBs
----------
 $ Processo concluído com sucesso` 
```

## Explicação dos Itens de Saída

### Total de Delete Markers

-   **O que é?**
    -   Marcadores de exclusão são indicadores que mostram que uma versão específica de um objeto foi excluída em um bucket com versionamento habilitado.
-   **Quando e como acontecem?**
    -   Quando um objeto é excluído em um bucket versionado, ao invés de ser removido imediatamente, um marcador de exclusão é criado. Isso permite recuperar versões anteriores se necessário.
-   **Por que é importante?**
    -   Marcadores de exclusão podem acumular ao longo do tempo e consumir espaço de armazenamento. Conhecer a quantidade ajuda a gerenciar e otimizar o uso do bucket.

### Número de Objetos Atuais

-   **O que é?**
    -   Refere-se ao número total de objetos que são a versão mais recente no bucket.
-   **Quando e como acontecem?**
    -   Sempre que um objeto é carregado ou atualizado, ele se torna o objeto atual.
-   **Por que é importante?**
    -   Representa os dados ativos que estão sendo usados ou acessados regularmente.

### Tamanho dos Objetos Atuais

-   **O que é?**
    -   O espaço total de armazenamento ocupado pelos objetos atuais.
-   **Quando e como acontecem?**
    -   Acumula à medida que novos objetos são adicionados ou existentes são atualizados.
-   **Por que é importante?**
    -   Ajuda a entender o consumo atual de armazenamento e possíveis custos associados.

### Número de Objetos Não Atuais

-   **O que é?**
    -   Quantidade de versões anteriores dos objetos que não são as versões mais recentes.
-   **Quando e como acontecem?**
    -   Sempre que um objeto é atualizado, a versão anterior se torna não atual.
-   **Por que é importante?**
    -   Versões antigas podem ocupar espaço significativo. Saber quantas existem ajuda na decisão de mantê-las ou removê-las.

### Tamanho dos Objetos Não Atuais

-   **O que é?**
    -   Espaço de armazenamento ocupado pelas versões antigas dos objetos.
-   **Quando e como acontecem?**
    -   Aumenta com cada atualização de objeto, pois as versões antigas são retidas.
-   **Por que é importante?**
    -   Versões não atuais podem gerar custos de armazenamento. Identificar seu tamanho total permite otimizar o uso do espaço.

### Tamanho Total

-   **O que é?**
    -   Soma do tamanho dos objetos atuais e não atuais.
-   **Quando e como acontecem?**
    -   Reflete o uso total de armazenamento no bucket, incluindo todas as versões de objetos.
-   **Por que é importante?**
    -   Fornece uma visão completa do consumo de armazenamento, essencial para gerenciamento de custos e desempenho.

## Licença

Este projeto está licenciado sob os termos da licença MIT. Consulte o arquivo LICENSE para obter mais informações.

