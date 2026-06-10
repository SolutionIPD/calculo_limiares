# ==============================================================================
# Script: 04_explorar_mongo.R
# Objetivo: Conectar ao MongoDB da plataforma, fazer um "dump" (baixar) todos 
#           os limiares atuais e salvar localmente para exploração offline.
# ==============================================================================

# Instala o pacote mongolite caso não esteja presente
if (!requireNamespace("mongolite", quietly = TRUE)) {
  install.packages("mongolite")
}

library(mongolite)
library(tidyverse)

# 1. Lê as credenciais do .env no home
caminho_env <- "/home/thiago/.env" # Arquivo de credenciais no seu home
if (file.exists(caminho_env)) {
  readRenviron(caminho_env)
} else {
  message(sprintf("Aviso: Arquivo de credenciais não encontrado em '%s'", caminho_env))
}

# Tenta ler a variável MONGODB_URI (definida no seu .env)
mongo_url <- Sys.getenv("MONGODB_URI")
if (mongo_url == "") {
  mongo_url <- Sys.getenv("MONGO_URL")
}

# Tenta ler o nome do banco, ou extrai automaticamente do fim da URI
mongo_db <- Sys.getenv("MONGO_DB")
if (mongo_db == "" || mongo_db == "cole_aqui_o_nome_do_banco") {
  mongo_db <- gsub(".*/([^/?]+).*", "\\1", mongo_url)
}

if (mongo_url == "" || mongo_url == "cole_aqui_a_url_que_seu_chefe_passar") {
  stop(
    "Variáveis de conexão não encontradas no ambiente!\n",
    sprintf("Verifique se o arquivo %s existe e contém a variável MONGODB_URI definida.", caminho_env)
  )
}
mongo_collection <- "limits"

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

arquivo_rds <- file.path(dir_mongo, "limits_producao_dump.rds")
arquivo_csv <- file.path(dir_mongo, "limits_producao_dump.csv")

saveRDS(dados_mongo, arquivo_rds)
write_csv(dados_mongo, arquivo_csv)

cat(sprintf("Dados salvos em '%s' para exploração local.\n", arquivo_rds))

# 4. Visão geral dos dados
glimpse(dados_mongo)

# Encerra a conexão (o pacote mongolite lida com isso sozinho, mas podemos forçar)
rm(mongo_conn)
gc()