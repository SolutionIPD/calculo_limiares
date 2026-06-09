# ==============================================================================
# Script: 04_explorar_mongo.R
# Objetivo: Conectar ao MongoDB da plataforma, fazer um "dump" (baixar) todos 
#           os limiares atuais e salvar localmente para exploração offline.
# ==============================================================================

library(mongolite)
library(tidyverse)

# 1. Lê as credenciais do .Renviron
mongo_url <- Sys.getenv("MONGO_URL", "mongodb://localhost:27017")
mongo_db <- Sys.getenv("MONGO_DB", "nome_do_banco")
mongo_collection <- "limiares_automatizados"

cat(sprintf("Conectando ao MongoDB...\nBanco: %s\nColeção: %s\n", mongo_db, mongo_collection))

# Conecta à coleção
mongo_conn <- mongo(
  collection = mongo_collection,
  db = mongo_db,
  url = mongo_url
)

# 2. Baixar Todos os Dados (O find sem parâmetros traz todos os documentos)
cat("Baixando dados da coleção...\n")
dados_mongo <- mongo_conn$find("{}")

cat(sprintf("=> Sucesso! Encontrados %d registros.\n", nrow(dados_mongo)))

# 3. Salvar Localmente para Exploração Offline
dir_mongo <- "/home/thiago/calculo_limiares/dados/mongo"
dir.create(dir_mongo, recursive = TRUE, showWarnings = FALSE)

arquivo_rds <- file.path(dir_mongo, "limiares_plataforma_dump.rds")
arquivo_csv <- file.path(dir_mongo, "limiares_plataforma_dump.csv")

saveRDS(dados_mongo, arquivo_rds)
write_csv(dados_mongo, arquivo_csv)

cat(sprintf("Dados salvos em '%s' para exploração local.\n", arquivo_rds))

# 4. Visão geral dos dados
glimpse(dados_mongo)

# Encerra a conexão (o pacote mongolite lida com isso sozinho, mas podemos forçar)
rm(mongo_conn)
gc()