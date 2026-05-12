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
│   ├── 01_processo_treinamento.R  # Script de ETL: varre os CSVs, ajusta modelos e salva o .rds
│   ├── funcoes_calculo.R          # Core: funções de leitura, acumulado 96h e cálculo Tweedie
│   └── exemplos_uso.R             # Script de teste isolado das funções
├── relatorios/
│   └── relatorio_final.Rmd        # Dashboard interativo (Quarto/RMarkdown)
├── organiza_inmet.sh              # Script Bash para mapear e organizar CSVs baixados
└── README.md
```

## Metodologia Estatística

O pilar do cálculo é a **distribuição Tweedie**, que é o padrão ouro na meteorologia para modelar dados de precipitação, pois consegue lidar perfeitamente com massas de dados contendo valores zero (dias sem chuva) e valores contínuos positivos.

Foram implementados dois motores de cálculo para a extração dos limiares (quantis de 65%, 85%, 95% e 99%):

1. **Método "Pacote" (GLM Iterativo)**: Utiliza `tweedie::tweedie_profile` e máxima verossimilhança. Apesar de tradicional, sofre penalidade extrema de performance devido à alta quantidade de dias sem chuva, levando minutos por estação.
2. **Método "Matemático" (Exato)**: Como o nosso modelo busca apenas a média isolada (`y ~ 1`), fixamos o padrão literário de chuva (`power = 1.5`) e resolvemos a média aritmética e a dispersão via Resíduos de Pearson. O resultado é idêntico ao GLM iterativo, porém calculado de forma exata e em **milissegundos**.

## 🚀 Como Executar o Projeto

### 1. Pré-requisitos
* **R** (versão 4.0 ou superior)
* Bibliotecas R: `tidyverse`, `tweedie`, `statmod`, `flexdashboard`, `plotly`, `DT`
* **Quarto** / RMarkdown instalado

### 2. Preparação dos Dados Brutos
Baixe os dados históricos do portal do INMET. Salve os arquivos `INMET_*.CSV` descompactados em qualquer pasta (ex: `~/datasets-landslides/dados/`).

Em seguida, edite o diretório de origem no script `organiza_inmet.sh` e execute-o. Ele vai varrer, filtrar estações do RS e organizar tudo nas pastas corretas em milissegundos:

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

No terminal:
```bash
quarto preview relatorios/relatorio_final.Rmd
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