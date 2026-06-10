# ==============================================================================
# Script: 10_preparar_carga_mongo.R
# Objetivo: Formatar os novos parâmetros no esquema exigido pelo MongoDB, 
#           limpar a string do nome da estação, e realizar a migração.
# ==============================================================================

library(tidyverse)
library(tweedie)
library(mongolite)

# 1. Carrega os parâmetros novos e o dump do Mongo legado
arquivo_rds_novo <- "/home/thiago/calculo_limiares/dados/parametros/tb_params_atual.rds"
arquivo_rds_antigo <- "/home/thiago/calculo_limiares/dados/mongo/limits_producao_dump.rds"

if (!file.exists(arquivo_rds_novo) || !file.exists(arquivo_rds_antigo)) {
  stop("Arquivos de dados não encontrados. Verifique se executou os scripts de treinamento e de dump.")
}

tb_params <- readRDS(arquivo_rds_novo)
limites_antigos <- readRDS(arquivo_rds_antigo)

cat("Formatando os novos limiares e calculando os quantis (65%, 85%, 95%, 99%)...\n")

# 2. Formata a nova tabela para bater exatamente com a coleção 'limits' do Mongo
novos_limites <- tb_params %>%
  rowwise() %>%
  mutate(
    # Remove o prefixo do código da estação (ex: "A840_BENTO GONCALVES" -> "BENTO GONCALVES")
    station = gsub("^[A-Z0-9]+_", "", station),
    
    horas = 96, # Nova metodologia de janela de chuva acumulada
    r0 = qtweedie(0.65, power = power, mu = mu, phi = phi),
    r1 = qtweedie(0.85, power = power, mu = mu, phi = phi),
    r2 = qtweedie(0.95, power = power, mu = mu, phi = phi),
    r3 = qtweedie(0.99, power = power, mu = mu, phi = phi),
    `__v` = 0,
    createdAt = Sys.time(),
    updatedAt = Sys.time()
  ) %>%
  ungroup() %>%
  select(station, horas, mu, phi, power, `__v`, createdAt, updatedAt, r0, r1, r2, r3)

cat(sprintf("=> %d novas estações formatadas com sucesso.\n\n", nrow(novos_limites)))
print(head(novos_limites %>% select(station, horas, r0, r1, r2, r3), 5))
cat("=======================================================\n")

# ------------------------------------------------------------------------------
# 3. Bloco de Atualização no MongoDB (Produção)
# ------------------------------------------------------------------------------
# AVISO: O código abaixo vai DELETAR a tabela antiga e INSERIR os novos dados!
# Para executar de fato a migração, mude a variável 'EXECUTAR_MIGRACAO' para TRUE.

EXECUTAR_MIGRACAO <- FALSE

if (EXECUTAR_MIGRACAO) {
  caminho_env <- "/home/thiago/.env"
  if (file.exists(caminho_env)) readRenviron(caminho_env)
  mongo_url <- Sys.getenv("MONGODB_URI")
  if (mongo_url == "") mongo_url <- Sys.getenv("MONGO_URL")
  mongo_db <- Sys.getenv("MONGO_DB")
  if (mongo_db == "" || mongo_db == "cole_aqui_o_nome_do_banco") {
    mongo_db <- gsub(".*/([^/?]+).*", "\\1", mongo_url)
  }
  
  m_limits <- mongo(collection = "limits", db = mongo_db, url = mongo_url)
  
  cat("\n[CUIDADO] Conectado ao MongoDB de Produção. Iniciando migração...\n")
  
  # Deleta os limites antigos
  m_limits$remove('{}')
  cat(" -> Limites antigos (legado) removidos com sucesso.\n")
  
  # Insere os novos limites do PostGIS
  m_limits$insert(novos_limites)
  cat(" -> SUCESSO! Novos limites inseridos!\n")
  
  rm(m_limits)
} else {
  cat("\nMigração abortada por segurança. Altere 'EXECUTAR_MIGRACAO <- TRUE' no script para gravar no banco.\n")
}