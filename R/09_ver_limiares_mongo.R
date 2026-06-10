# ==============================================================================
# Script: 09_ver_limiares_mongo.R
# Objetivo: Baixar e visualizar todos os dados da coleção 'limits' do MongoDB.
# ==============================================================================

library(mongolite)
library(tidyverse)

caminho_env <- "/home/thiago/.env"
if (file.exists(caminho_env)) readRenviron(caminho_env)

mongo_url <- Sys.getenv("MONGODB_URI")
if (mongo_url == "") mongo_url <- Sys.getenv("MONGO_URL")

mongo_db <- Sys.getenv("MONGO_DB")
if (mongo_db == "" || mongo_db == "cole_aqui_o_nome_do_banco") {
  mongo_db <- gsub(".*/([^/?]+).*", "\\1", mongo_url)
}

cat("Conectando à coleção 'limits'...\n")
m_limits <- mongo(collection = "limits", db = mongo_db, url = mongo_url)

# Baixa todos os 60 registros
dados_limiares <- m_limits$find()

cat(sprintf("=> SUCESSO! %d registros baixados.\n\n", nrow(dados_limiares)))

# Exibe a tabela organizada apenas com as colunas que importam
tabela_resumo <- dados_limiares %>% select(station, horas, r0, r1, r2, r3)
print(tabela_resumo, n = 20)