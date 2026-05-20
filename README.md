# Cálculo de Limiares para Alertas de Deslizamentos

Este repositório contém o pipeline de dados (ETL) e as metodologias estatísticas para o cálculo de limiares de chuva acumulada (96h). O objetivo do sistema é fornecer gatilhos confiáveis para a emissão de alertas de risco de deslizamentos no Rio Grande do Sul, utilizando dados históricos pluviométricos do INMET.

## Arquitetura do Projeto

A estrutura do repositório foi desenhada para separar claramente a ingestão de dados, as funções centrais, os processos em lote (batch) e a visualização:

```text
/calculo_limiares/
├── dados/
│   ├── inmet_brutos/          # CSVs históricos organizados por estação (Ignorado no Git)
│   └── parametros/            # Resultados do treinamento: tb_params_atual.rds
├── R/
│   ├── 01_processo_treinamento.R # (LEGADO) Script de ETL baseado em arquivos CSV
│   ├── 01_processo_treinamento_db.R # Script de ETL: lê do banco, ajusta modelos e salva o .rds
│   ├── 02_carga_banco.R          # Script de carga única: migra CSVs para o PostGIS
│   ├── funcoes_calculo.R         # Core: funções de leitura, acumulado 96h e cálculo Tweedie
│   └── funcoes_db.R              # Core (DB): funções que acessam o banco de dados
├── relatorios/
│   ├── relatorio_tecnico.qmd      # Dashboard técnico interativo da metodologia
│   └── relatorio_fontes_dados.qmd # Análise crítica das fontes de dados
├── organiza_inmet.sh              # Script Bash para mapear e organizar CSVs baixados
└── README.md
```

## Metodologia Estatística

O pilar do cálculo é a **distribuição Tweedie**, que é o padrão ouro na meteorologia para modelar dados de precipitação, pois consegue lidar perfeitamente com massas de dados contendo valores zero (dias sem chuva) e valores contínuos positivos.

Foram implementados dois motores de cálculo para a extração dos limiares (quantis de 65%, 85%, 95% e 99%):

1. **Método "Pacote" (GLM Iterativo)**: Utiliza `tweedie::tweedie_profile` e máxima verossimilhança. Apesar de tradicional, sofre penalidade extrema de performance devido à alta quantidade de dias sem chuva, levando minutos por estação.
2. **Método "Matemático" (Exato)**: Como o nosso modelo busca apenas a média isolada (`y ~ 1`), fixamos o padrão literário de chuva (`power = 1.5`) e resolvemos a média aritmética e a dispersão via Resíduos de Pearson. O resultado é idêntico ao GLM iterativo, porém calculado de forma exata e em **milissegundos**.

## 🚀 Como Executar o Projeto

### 1. Pré-requisitos e Configuração
* **R** (versão 4.0 ou superior)
* **PostgreSQL com PostGIS**: Um servidor de banco de dados acessível.
  * **Recomendado (Docker)**: Utilize uma imagem oficial do PostGIS. Exemplo:
    `docker run --name postgis-limiares -e POSTGRES_USER=thiago -e POSTGRES_PASSWORD=uma_senha_forte_para_thiago -e POSTGRES_DB=limiares_db -p 15432:5432 -d postgis/postgis`
  * **Instalação Nativa (Ubuntu/Debian)**: Requer a instalação da extensão via gerenciador de pacotes (ex: `sudo apt install postgis postgresql-16-postgis-3`).
* **Quarto**: Para renderizar os relatórios.
* **Bibliotecas R**: Instale os pacotes necessários:
  ```r
  install.packages(c("tidyverse", "tweedie", "statmod", "plotly", "DT", "leaflet", "crosstalk", "RPostgres", "DBI", "lubridate"))
  ```
* **Variáveis de Ambiente**: Crie um arquivo `.Renviron` na raiz do projeto (`/home/thiago/calculo_limiares/.Renviron`) com as credenciais do seu banco de dados para que os scripts possam se conectar:
  ```
  DB_HOST=localhost
  DB_PORT=5432
  DB_NAME=seu_banco
  DB_USER=seu_usuario
  DB_PASSWORD=sua_senha
  ```
  **Importante:** Após criar ou modificar o arquivo `.Renviron`, você **deve reiniciar sua sessão R** (no RStudio, vá em `Session > Restart R`) para que as variáveis sejam carregadas.

### 2. Preparação e Carga dos Dados
Baixe os dados históricos do portal do INMET. Salve os arquivos `INMET_*.CSV` descompactados em qualquer pasta (ex: `~/datasets-landslides/dados/`).

**Passo 2.1: Organizar os CSVs (Opcional, se já não estiver feito)**
O script `organiza_inmet.sh` ajuda a mover os arquivos CSV para a estrutura de pastas esperada em `dados/inmet_brutos/`.
```bash
chmod +x organiza_inmet.sh
./organiza_inmet.sh
```

### 3. Treinamento em Lote (ETL)
Uma vez com os dados na pasta `dados/inmet_brutos/`, rode o script de treinamento. Ele processará o histórico de todas as estações e consolidará os parâmetros e limiares quantílicos:

No R:
```r
source("R/01_processo_treinamento.R")
```
Isso vai gerar o arquivo "banco de dados" oficial em `dados/parametros/tb_params_atual.rds`.

### 4. Visualização e Dashboard
Com os parâmetros gerados, renderize o dashboard iterativo para visualizar a tabela de limiares treinados e os gráficos comparativos de metodologia.

No terminal, a partir da raiz do projeto:
```bash
quarto preview relatorios/relatorio_tecnico.qmd
```
Ou abra o arquivo no RStudio e clique em **"Knit"**.

## 📌 Funcionalidades Core

A função `calcular_limiares_estacao` é flexível e inteligente:
- **Busca por Nome:** Puxa os dados exatos se informada uma estação do INMET (ex: `nome_estacao = "BENTO GONCALVES"`).
- **Busca por Coordenada (Distância Haversine):** Permite inserir Latitude e Longitude de um município sem estação própria ou de outra rede (ex: Cemaden). A função identifica a estação INMET mais próxima e sugere os parâmetros baseados no vizinho.

## 🗺️ Próximos Passos (Roadmap)

- [ ] Encapsular a função de cálculo em uma API (`api.R`) RESTful utilizando `plumber`.
- [ ] Automatizar o script de ETL via `cronjob` ou GitHub Actions para atualização contínua.
- [ ] Adicionar suporte nativo à leitura de dados de outras redes (ex: Cemaden, ANA).