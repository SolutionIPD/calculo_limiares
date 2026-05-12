# ==============================================================================
# Script: funcoes_calculo.R
# Objetivo: Funções centrais para cálculo de parâmetros Tweedie e limiares 
#           a partir de dados brutos do INMET.
# ==============================================================================

library(tidyverse)
library(tweedie)
library(statmod)

# ------------------------------------------------------------------------------
# Função Auxiliar: Obter Metadados (Lat/Lon) a partir dos arquivos do INMET
# ------------------------------------------------------------------------------
obter_metadados_estacoes <- function(dir_brutos = "dados/inmet_brutos") {
  pastas <- list.dirs(dir_brutos, full.names = TRUE, recursive = FALSE)
  
  metadados <- map_dfr(pastas, function(pasta) {
    arquivos <- list.files(pasta, pattern = "\\.CSV$", ignore.case = TRUE, full.names = TRUE)
    if (length(arquivos) == 0) return(NULL)
    
    # Lê as primeiras 10 linhas do 1º arquivo do histórico para extrair Lat/Lon
    linhas <- readLines(arquivos[1], n = 10, encoding = "latin1")
    
    linha_nome <- grep("ESTACAO:", linhas, value = TRUE)
    linha_lat  <- grep("LATITUDE:", linhas, value = TRUE)
    linha_lon  <- grep("LONGITUDE:", linhas, value = TRUE)
    
    nome <- if (length(linha_nome) > 0) str_extract(linha_nome, "(?<=:;).*") else NA
    lat_str <- if (length(linha_lat) > 0) str_extract(linha_lat, "(?<=:;).*") else NA
    lon_str <- if (length(linha_lon) > 0) str_extract(linha_lon, "(?<=:;).*") else NA
    
    lat <- as.numeric(str_replace(lat_str, ",", "."))
    lon <- as.numeric(str_replace(lon_str, ",", "."))
    
    tibble(
      pasta = pasta,
      estacao = basename(pasta),
      nome = trimws(nome),
      lat = lat,
      lon = lon
    )
  })
  
  return(metadados)
}

# ------------------------------------------------------------------------------
# Função Auxiliar: Distância Haversine (em KM)
# ------------------------------------------------------------------------------
distancia_haversine <- function(lat1, lon1, lat2, lon2) {
  R <- 6371 # Raio da Terra em km
  p <- pi / 180
  a <- 0.5 - cos((lat2 - lat1) * p) / 2 + 
       cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2
  return(R * 2 * asin(sqrt(a)))
}

# ------------------------------------------------------------------------------
# FUNÇÃO PRINCIPAL: Calcular Limiares por Estação
# ------------------------------------------------------------------------------
#' Calcular Limiares por Estação (Distribuição Tweedie)
#'
#' @description
#' Esta função lê o histórico de precipitação de uma estação do INMET, calcula a 
#' janela móvel de chuva acumulada (padrão de 96h) e ajusta uma distribuição Tweedie 
#' para extrair os limiares quantílicos de alerta.
#'
#' @param nome_estacao Nome parcial ou completo da estação INMET (ex: "BENTO GONCALVES").
#' @param lat_busca Latitude para busca da estação INMET mais próxima (Distância Haversine).
#' @param lon_busca Longitude para busca por proximidade.
#' @param dir_brutos Caminho para o diretório com os CSVs do INMET organizados.
#' @param cuts Vetor numérico com os percentis (probabilidades) dos limiares.
#' @param metodo_ajuste Abordagem matemática para calcular os parâmetros da Tweedie:
#'   - "pacote" (Padrão): Utiliza as funções `tweedie_profile` e `glm`. Faz uma busca 
#'     iterativa pesada pelo parâmetro 'power' ótimo. Devido ao excesso de zeros 
#'     (dias sem chuva), este processo é muito lento e pode demorar vários minutos.
#'   - "matematico": Fixa `power = 1.5` (padrão da literatura meteorológica) e resolve 
#'     o intercepto matematicamente (Média Aritmética e Dispersão de Pearson). Gera 
#'     resultados rigorosos, mas com velocidade instantânea (milissegundos).
#'
#' @return Lista contendo a estação, distância, parâmetros do modelo (mu, phi, power)
#'         e um dataframe (tibble) com os limiares de criticidade em milímetros (mm).
calcular_limiares_estacao <- function(nome_estacao = NULL, lat_busca = NULL, lon_busca = NULL, 
                                      dir_brutos = "dados/inmet_brutos", cuts = c(0.65, 0.85, 0.95, 0.99),
                                      metodo_ajuste = "pacote") {
  
  # 1. Mapear estações disponíveis
  meta <- obter_metadados_estacoes(dir_brutos)
  if (nrow(meta) == 0) stop("Nenhuma estação encontrada no diretório de dados.")
  
  estacao_alvo <- NULL
  distancia_km <- 0
  
  # 2. Lógica de busca (por Coordenada ou Nome)
  if (!is.null(lat_busca) && !is.null(lon_busca)) {
    
    meta <- meta |> 
      mutate(dist_km = distancia_haversine(lat_busca, lon_busca, lat, lon)) |> 
      arrange(dist_km)
      
    estacao_alvo <- meta |> slice(1)
    distancia_km <- estacao_alvo$dist_km
    message(sprintf("=> Estação INMET mais próxima: %s (%.2f km de distância)", estacao_alvo$estacao, distancia_km))
    
  } else if (!is.null(nome_estacao)) {
    
    estacao_alvo <- meta |> 
      filter(str_detect(toupper(estacao), toupper(nome_estacao)) | 
             str_detect(toupper(nome), toupper(nome_estacao))) |> 
      slice(1)
      
    if (nrow(estacao_alvo) == 0) stop("Estação não encontrada.")
    message(sprintf("=> Estação encontrada: %s", estacao_alvo$estacao))
    
  } else {
    stop("Você deve fornecer o 'nome_estacao' ou as coordenadas ('lat_busca' e 'lon_busca').")
  }
  
  # 3. Ler e processar o histórico (Acumulado 96h)
  arquivos <- list.files(estacao_alvo$pasta, pattern = "\\.CSV$", ignore.case = TRUE, full.names = TRUE)
  message("=> Lendo histórico e calculando janela móvel de 96h...")
  
  dados <- map_dfr(arquivos, function(arq) {
    tryCatch({
      # O INMET sempre tem 8 linhas de cabeçalho, os dados começam na 9
      df <- suppressMessages(read_delim(arq, delim = ";", skip = 8, 
                       locale = locale(decimal_mark = ",", grouping_mark = "."), 
                       show_col_types = FALSE, name_repair = "minimal"))
      df <- df[, 1:3] # Pega apenas as colunas essenciais: Data, Hora UTC e Precipitação
      colnames(df) <- c("Data", "Hora", "Precipitacao")
      df$Precipitacao <- as.numeric(df$Precipitacao)
      df$Precipitacao[df$Precipitacao < 0] <- NA # Limpa falhas de sensor
      df
    }, error = function(e) NULL)
  })
  
  # Preenche pequenos buracos com 0 e calcula a soma móvel de 96 posições (horas)
  precip <- dados$Precipitacao
  precip[is.na(precip)] <- 0
  dados$chuva_acumulada_96h <- as.numeric(stats::filter(precip, rep(1, 96), sides = 1))
  
  # Pega apenas uma observação por dia (ex: meia-noite) para evitar autocorrelação no modelo estatístico
  dados_diarios <- dados |> 
    filter(grepl("00:00|0000", Hora)) |> 
    filter(!is.na(chuva_acumulada_96h))
  
  y <- dados_diarios$chuva_acumulada_96h
  if (all(y == 0) || length(unique(y)) < 2) stop("Dados insuficientes de precipitação na estação.")
  
  # Extração de Metadados (Tratamento de formato de datas de estações antigas e novas)
  datas_validas <- suppressWarnings(lubridate::parse_date_time(dados$Data, orders = c("ymd", "dmy", "Ymd", "dmY")))
  if (all(is.na(datas_validas))) {
    data_inicio <- NA; data_fim <- NA
  } else {
    data_inicio <- format(min(datas_validas, na.rm = TRUE), "%d/%m/%Y")
    data_fim <- format(max(datas_validas, na.rm = TRUE), "%d/%m/%Y")
  }
  n_dados <- nrow(dados)
  n_ausentes <- sum(is.na(dados$Precipitacao))

  # 4. Ajustar Tweedie e Extrair Limiares
  if (metodo_ajuste == "matematico") {
    message("=> Calculando parâmetros da distribuição Tweedie (Método Matemático)...")
    # Solução exata e super rápida para intercepto
    p_otimo <- 1.5
    mu_otimo <- mean(y)
    phi_otimo <- sum((y - mu_otimo)^2 / (mu_otimo^p_otimo)) / (length(y) - 1)
    
  } else {
    # Padrão: Ajuste via funções do pacote tweedie (glm + tweedie_profile)
    message("=> Ajustando o modelo Tweedie (Pacote: tweedie_profile + glm)... isso pode demorar um pouco.")
    data_df <- data.frame(y = y)
    
    power_profile <- suppressMessages(try(tweedie::tweedie_profile(y ~ 1, data = data_df, p.vec = seq(1.1, 1.9, by = 0.1), do.plot = FALSE, verbose = FALSE), silent = TRUE))
    p_otimo <- if (inherits(power_profile, "try-error")) 1.5 else power_profile$p.max
    
    # GLM pode apresentar warnings se houver muitos zeros ou demora na convergência
    modelo_glm <- suppressWarnings(glm(y ~ 1, data = data_df, family = tweedie(var.power = p_otimo, link.power = 0)))
    
    mu_otimo <- exp(coef(modelo_glm))
    phi_otimo <- summary(modelo_glm)$dispersion
  }
  
  limiares_mm <- tweedie::qtweedie(cuts, mu = mu_otimo, phi = phi_otimo, power = p_otimo)
  
  message("=> Concluído!")
  return(list(estacao = estacao_alvo$estacao, distancia_km = round(distancia_km, 2), 
              metadata = list(data_inicio = data_inicio, data_fim = data_fim, n_dados = n_dados, n_ausentes = n_ausentes),
              params = list(mu = unname(mu_otimo), phi = phi_otimo, power = p_otimo), 
              limiares = tibble(Nivel = c("Moderado", "Alto", "Muito Alto", "Altíssimo"), Percentil = cuts, Limiar_mm = round(limiares_mm, 2))))
}