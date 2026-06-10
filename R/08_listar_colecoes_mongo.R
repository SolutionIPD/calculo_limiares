# ==============================================================================
# Script: 08_listar_colecoes_mongo.R
# Objetivo: Descobrir quais coleções existem no MongoDB em produção e 
#           mostrar o esquema (schema) de 1 registro de cada para engenharia reversa.
# ==============================================================================

library(mongolite)
library(tidyverse)

# 1. Carrega as credenciais
caminho_env <- "/home/thiago/.env"
if (file.exists(caminho_env)) {
  readRenviron(caminho_env)
}

mongo_url <- Sys.getenv("MONGODB_URI")
if (mongo_url == "") {
  mongo_url <- Sys.getenv("MONGO_URL")
}

mongo_db <- Sys.getenv("MONGO_DB")
if (mongo_db == "" || mongo_db == "cole_aqui_o_nome_do_banco") {
  mongo_db <- gsub(".*/([^/?]+).*", "\\1", mongo_url)
}

cat(sprintf("Conectando ao banco de dados '%s' para mapeamento...\n", mongo_db))

# 2. Usamos uma conexão genérica para rodar o comando de listar coleções
m_temp <- mongo(collection = "dummy", db = mongo_db, url = mongo_url)
cols_info <- m_temp$run('{"listCollections": 1, "nameOnly": true}')

colecoes <- cols_info$cursor$firstBatch$name
# Remove coleções de sistema internas do Mongo
colecoes <- colecoes[!grepl("^system\\.", colecoes)]

cat(sprintf("\n=> SUCESSO! Encontradas %d coleções (tabelas) no banco:\n", length(colecoes)))
print(colecoes)

cat("\n=======================================================\n")
cat("Amostra de Estrutura (Schema) das Coleções Existentes\n")
cat("=======================================================\n")

# 3. Itera sobre cada coleção e busca 1 registro para vermos os campos
for (col in colecoes) {
  cat(sprintf("\n--- Coleção: %s ---\n", col))
  m_col <- mongo(collection = col, db = mongo_db, url = mongo_url)
  
  n_docs <- m_col$count()
  cat(sprintf("Total de registros (documentos): %d\n", n_docs))
  
  if (n_docs > 0) {
    amostra <- m_col$find(limit = 1)
    glimpse(amostra)
  }
}