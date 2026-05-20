# ==============================================================================
# 02_CARGA_BANCO.R
#
#
# Descrição:
# Este script realiza a carga inicial (ETL) dos dados pluviométricos das
# estações do INMET, previamente organizados em formato CSV, para um banco
# de dados PostgreSQL com a extensão PostGIS.
#
# O script executa as seguintes etapas:
# 1. Conecta-se ao banco de dados usando credenciais de variáveis de ambiente.
# 2. Cria as tabelas 'estacoes' e 'leituras_horarias' se elas não existirem.
#    - A tabela 'estacoes' armazena metadados e a localização geométrica.
#    - A tabela 'leituras_horarias' armazena os dados de precipitação.
# 3. Lê os metadados das estações a partir dos diretórios de arquivos brutos.
# 4. Insere ou atualiza os dados das estações na tabela 'estacoes'.
# 5. Itera sobre cada estação, lê os respectivos arquivos CSV, e insere os
#    dados de leitura horária na tabela 'leituras_horarias', evitando duplicatas.
#
# Pré-requisitos:
# - Pacotes R: RPostgres, DBI, tidyverse, lubridate
# - Banco de dados PostgreSQL com PostGIS ativo.
# - Arquivo .Renviron na raiz do projeto com as credenciais do banco.
#
# Como usar:
# 1. Certifique-se de que os pré-requisitos estão atendidos.
# 2. Execute o script a partir da raiz do projeto: source("R/02_carga_banco.R")
# ==============================================================================

# ---- 1. Carga de Pacotes e Funções ----
library(DBI)
library(RPostgres)
library(tidyverse)
library(lubridate)

# Funções auxiliares do projeto (para ler metadados e dados dos CSVs)
source("R/funcoes_calculo.R")

# Diretório onde os CSVs estão organizados por estação
dir_brutos <- "/home/thiago/calculo_limiares/dados/inmet_brutos"

# ---- 2. Conexão e Criação das Tabelas no Banco ----

# Força a leitura do arquivo .Renviron a partir da raiz do projeto
caminho_env <- "/home/thiago/calculo_limiares/.Renviron"
if (file.exists(caminho_env)) readRenviron(caminho_env)

# Valida se as variáveis de ambiente essenciais estão configuradas
if (Sys.getenv("DB_USER") == "" || Sys.getenv("DB_NAME") == "") {
  user_val <- Sys.getenv("DB_USER")
  name_val <- Sys.getenv("DB_NAME")
  stop(
    "As variáveis de ambiente do banco de dados não foram carregadas.\n",
    "-> Causa provável: Você precisa reiniciar sua sessão R/RStudio para que o arquivo '.Renviron' seja lido.\n",
    "-> Verificação: O script encontrou DB_USER='", user_val, "' e DB_NAME='", name_val, "'. Ambos precisam estar preenchidos.\n",
    "-> Ação: Reinicie sua sessão R e tente executar o script novamente."
  )
}

# Conecta ao banco de dados usando as variáveis de ambiente
con <- DBI::dbConnect(
  RPostgres::Postgres(),
  host = Sys.getenv("DB_HOST", "127.0.0.1"),
  port = Sys.getenv("DB_PORT", 5432),
  dbname = Sys.getenv("DB_NAME"),
  user = Sys.getenv("DB_USER"),
  password = Sys.getenv("DB_PASSWORD")
)

cat("Conexão com o banco de dados estabelecida.\n")

# Garante que a extensão PostGIS esteja instalada no banco
tryCatch({
  dbExecute(con, "CREATE EXTENSION IF NOT EXISTS postgis;")
  cat("Extensão PostGIS ativada/verificada com sucesso.\n")
}, error = function(e) {
  # Cria uma mensagem de erro mais informativa e amigável
  msg <- paste(
    "FALHA AO ATIVAR A EXTENSÃO POSTGIS.\n\n",
    "CAUSA: A extensão PostGIS não está disponível no servidor PostgreSQL conectado.\n",
    "SOLUÇÃO:\n",
    "- Se estiver usando Docker (Recomendado): Certifique-se de que a imagem utilizada suporta PostGIS (ex: 'postgis/postgis' em vez de apenas 'postgres').\n",
    "- Se estiver usando uma instalação nativa (Ubuntu/Debian): Conecte-se ao seu servidor e instale o pacote via SO:\n",
    "sudo apt update\n",
    "sudo apt install postgis postgresql-16-postgis-3\n",
    "E não se esqueça de reiniciar o serviço do PostgreSQL.\n\n",
    "--- Mensagem de Erro Original do Banco de Dados ---\n",
    e$message
  )
  stop(msg, call. = FALSE) # call. = FALSE para um traceback mais limpo
})

# Destruição TOTAL do banco de dados (a pedido) para garantir uma recarga limpa
dbExecute(con, "DROP TABLE IF EXISTS leituras_horarias CASCADE;")
dbExecute(con, "DROP TABLE IF EXISTS estacoes CASCADE;")

# Cria a tabela de estações com um campo de geometria PostGIS
dbExecute(con, "
  CREATE TABLE IF NOT EXISTS estacoes (
    id SERIAL PRIMARY KEY,
    codigo VARCHAR(50) UNIQUE NOT NULL,
    nome VARCHAR(255),
    lat DOUBLE PRECISION NOT NULL,
    lon DOUBLE PRECISION NOT NULL,
    geom GEOMETRY(Point, 4326)
  );
")

# Cria a tabela de leituras horárias com chave estrangeira
dbExecute(con, "
  CREATE TABLE IF NOT EXISTS leituras_horarias (
    id SERIAL PRIMARY KEY,
    estacao_id INTEGER REFERENCES estacoes(id),
    data_hora TIMESTAMP NOT NULL,
    precipitacao_mm DOUBLE PRECISION,
    UNIQUE (estacao_id, data_hora)
  );
")

cat("Tabelas 'estacoes' e 'leituras_horarias' garantidas no banco.\n")

# ---- 3. Carga dos Metadados das Estações ----

meta_estacoes <- obter_metadados_estacoes(dir_brutos)

cat(paste("Encontradas", nrow(meta_estacoes), "estações nos diretórios.\n"))

for (i in 1:nrow(meta_estacoes)) {
  estacao <- meta_estacoes[i, ]
  # Insere a estação, ou não faz nada se o código já existir (ON CONFLICT)
  dbExecute(con, 
    "INSERT INTO estacoes (codigo, nome, lat, lon, geom) VALUES ($1, $2, $3, $4, ST_SetSRID(ST_MakePoint($5, $6), 4326)) ON CONFLICT (codigo) DO NOTHING",
    params = list(estacao$estacao, estacao$nome, estacao$lat, estacao$lon, estacao$lon, estacao$lat)
  )
}

cat("Metadados das estações carregados no banco.\n")

# ---- 4. Carga dos Dados Horários ----

estacoes_no_banco <- dbGetQuery(con, "SELECT id, codigo FROM estacoes")

estacoes_sucesso <- 0
estacoes_vazias <- 0
total_linhas <- 0

for (i in 1:nrow(estacoes_no_banco)) {
  codigo_estacao <- estacoes_no_banco$codigo[i]
  id_estacao <- estacoes_no_banco$id[i]
  
  cat(sprintf("Processando estação: %s ", codigo_estacao))
  
  # Lê os dados do CSV usando a função existente
  dados_csv <- ler_dados_estacao(codigo_estacao, dir_brutos) %>%
    select(data_hora, precipitacao_mm) %>%
    mutate(estacao_id = id_estacao) %>%
    filter(!is.na(data_hora))

  if (nrow(dados_csv) > 0) {
    cat(sprintf("-> %d registros... ", nrow(dados_csv)))
    # Padrão de "upsert" em lote para alta performance e segurança:
    # 1. Carrega os dados em uma tabela temporária (operação de COPY, muito rápida).
    #    Usamos `overwrite = TRUE` para garantir que a tabela temp seja limpa a cada iteração do loop.
    dbWriteTable(con, "temp_leituras_carga", dados_csv, temporary = TRUE, overwrite = TRUE, row.names = FALSE)
    
    # 2. Usa um INSERT com ON CONFLICT para inserir apenas os registros que não existem.
    #    Isso torna o script "idempotente" (pode ser rodado várias vezes sem erro).
    #    A verificação de duplicatas é feita pelo banco de dados, que é a forma mais eficiente.
    dbExecute(con, "INSERT INTO leituras_horarias (estacao_id, data_hora, precipitacao_mm) SELECT estacao_id, data_hora, precipitacao_mm FROM temp_leituras_carga ON CONFLICT (estacao_id, data_hora) DO NOTHING;")
    cat("OK\n")
    estacoes_sucesso <- estacoes_sucesso + 1
    total_linhas <- total_linhas + nrow(dados_csv)
  } else {
    cat("-> VAZIA (Nenhum dado lido dos CSVs)\n")
    estacoes_vazias <- estacoes_vazias + 1
  }
}

cat("\n=========================================\n")
cat("RESUMO DA CARGA DE DADOS NO BANCO:\n")
cat(sprintf("- Estações carregadas com sucesso: %d\n", estacoes_sucesso))
cat(sprintf("- Estações sem dados válidos (ignoradas): %d\n", estacoes_vazias))
cat(sprintf("- Total de linhas de precipitação processadas: %d\n", total_linhas))
cat("=========================================\n")

# ---- 5. Desconexão ----
dbDisconnect(con)