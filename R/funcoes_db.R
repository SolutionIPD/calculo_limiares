# ==============================================================================
# FUNCOES_DB.R
#
#
# Descrição:
# Este arquivo contém as funções core para o cálculo de limiares de alerta
# de deslizamentos, adaptadas para consumir dados de um banco de dados
# PostgreSQL/PostGIS.
#
# Funções Principais:
# - conectar_db(): Estabelece e retorna uma conexão com o banco de dados.
# - obter_metadados_estacoes_db(): Busca os metadados de todas as estações do banco.
# - ler_dados_estacao_db(): Lê a série histórica de precipitação para uma estação.
# - calcular_limiares_estacao_db(): Orquestra o processo de cálculo de limiares
#   para uma estação, buscando por código ou pela estação mais próxima a uma
#   coordenada (usando PostGIS).
# ==============================================================================

library(DBI)
library(RPostgres)
library(tidyverse)
library(lubridate)
library(tweedie)
library(statmod)

#' Conecta ao banco de dados PostgreSQL.
#'
#' Utiliza variáveis de ambiente para as credenciais de conexão.
#' @return Um objeto de conexão DBI.
conectar_db <- function() {
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
  
  con <- DBI::dbConnect(
    RPostgres::Postgres(),
    host = Sys.getenv("DB_HOST", "127.0.0.1"),
    port = Sys.getenv("DB_PORT", 5432),
    dbname = Sys.getenv("DB_NAME"),
    user = Sys.getenv("DB_USER"),
    password = Sys.getenv("DB_PASSWORD")
  )
  
  # Garante que o banco está populado. Se 'estacoes' não existir, roda a carga.
  if (!DBI::dbExistsTable(con, "estacoes")) {
    message("Tabela 'estacoes' não encontrada. Iniciando carga automática do banco (ETL)...")
    source("/home/thiago/calculo_limiares/R/02_carga_banco.R", local = new.env())
    message("Carga automática concluída com sucesso!")
  }
  
  return(con)
}

#' Obtém metadados de todas as estações do banco de dados.
#'
#' @param con Objeto de conexão com o banco de dados.
#' @return Um tibble com os metadados das estações.
obter_metadados_estacoes_db <- function(con) {
  dbGetQuery(con, "SELECT codigo, nome, lat, lon FROM estacoes ORDER BY codigo") %>%
    as_tibble()
}

#' Lê a série histórica de precipitação para uma estação do banco de dados.
#'
#' @param codigo_estacao O código da estação (ex: 'A840_BENTO GONCALVES').
#' @param con Objeto de conexão com o banco de dados.
#' @return Um tibble com a série histórica (data_hora, precipitacao_mm).
ler_dados_estacao_db <- function(codigo_estacao, con) {
  query <- "
    SELECT l.data_hora, l.precipitacao_mm
    FROM leituras_horarias l
    JOIN estacoes e ON l.estacao_id = e.id
    WHERE e.codigo = $1
    ORDER BY l.data_hora;
  "
  dbGetQuery(con, query, params = list(codigo_estacao)) %>%
    as_tibble()
}

#' Calcula os limiares de precipitação para uma região/polígono (Precipitação Média Areal)
#'
#' @param con Objeto de conexão com o banco de dados.
#' @param wkt_poligono String em formato WKT (Well-Known Text) representando o polígono (SRID 4326).
#' @param cortes Vetor de quantis para os limiares.
#' @return Uma lista contendo os limiares regionais, parâmetros e metadados.
calcular_limiares_poligono_db <- function(con, wkt_poligono, cortes = c(0.65, 0.85, 0.95, 0.99)) {
  
  # Query espacial que extrai todas as estações contidas no polígono e já
  # retorna a Precipitação Média Areal por hora (ignorando as estações com falha na referida hora)
  query_regional <- "
    SELECT 
      l.data_hora, 
      AVG(l.precipitacao_mm) as precipitacao_mm,
      COUNT(l.precipitacao_mm) as estacoes_operantes
    FROM leituras_horarias l
    JOIN estacoes e ON l.estacao_id = e.id
    WHERE ST_Intersects(ST_GeomFromText($1, 4326), e.geom)
    GROUP BY l.data_hora
    ORDER BY l.data_hora;
  "
  
  dados_horarios <- dbGetQuery(con, query_regional, params = list(wkt_poligono)) %>%
    as_tibble()

  if (nrow(dados_horarios) < 96) {
    return(NULL) # Polígono sem nenhuma estação ou com série muito curta (< 96h)
  }

  # Limpeza e tratamento de falhas (agora aplicado à média regional)
  dados_horarios <- dados_horarios %>%
    mutate(precipitacao_mm = ifelse(precipitacao_mm < 0, 0, precipitacao_mm)) %>%
    replace_na(list(precipitacao_mm = 0))

  # Engenharia de dados: acumulado de 96h e amostragem diária
  dados_diarios <- dados_horarios %>%
    arrange(data_hora) %>%
    mutate(chuva_acumulada_96h = stats::filter(precipitacao_mm, rep(1, 96), sides = 1, method = "convolution")) %>%
    filter(hour(data_hora) == 0, minute(data_hora) == 0) %>%
    select(data_hora, chuva_acumulada_96h) %>%
    drop_na()

  chuva_positiva <- dados_diarios$chuva_acumulada_96h[dados_diarios$chuva_acumulada_96h > 0]

  if (length(chuva_positiva) < 2) {
    return(NULL)
  }

  # ---- Cálculo dos Parâmetros Tweedie (Método Matemático Exato) ----
  params <- list()
  params$p <- 1.5
  params$mu <- mean(dados_diarios$chuva_acumulada_96h)
  params$phi <- var(dados_diarios$chuva_acumulada_96h) / (params$mu^params$p)

  # ---- Cálculo dos Limiares ----
  limiares <- tibble(
    Nivel = c("Moderado", "Alto", "Muito Alto", "Altíssimo"),
    Percentil = cortes,
    Limiar_mm = round(qtweedie(cortes, power = params$p, mu = params$mu, phi = params$phi), 2)
  )
  
  meta <- list(
    data_inicio = min(dados_diarios$data_hora),
    data_fim = max(dados_diarios$data_hora),
    max_estacoes_simultaneas = max(dados_horarios$estacoes_operantes, na.rm = TRUE)
  )

  return(list(
    limiares = limiares,
    params = params,
    metadata = meta
  ))
}


#' Calcula os limiares de precipitação para uma estação usando dados do banco.
#'
#' @param con Objeto de conexão com o banco de dados.
#' @param nome_estacao O código da estação. Se nulo, lat/lon devem ser fornecidos.
#' @param lat Latitude para busca da estação mais próxima.
#' @param lon Longitude para busca da estação mais próxima.
#' @param metodo_ajuste 'matematico' (rápido) ou 'pacote' (lento).
#' @param cortes Vetor de quantis para os limiares (ex: c(0.65, 0.85, 0.95, 0.99)).
#' @return Uma lista contendo os limiares, parâmetros e metadados do cálculo.
calcular_limiares_estacao_db <- function(con, nome_estacao = NULL, lat = NULL, lon = NULL, metodo_ajuste = "matematico", cortes = c(0.65, 0.85, 0.95, 0.99)) {
  
  # Se lat/lon forem fornecidos, encontra a estação mais próxima via PostGIS
  if (is.null(nome_estacao) && !is.null(lat) && !is.null(lon)) {
    query_dist <- "
      SELECT codigo
      FROM estacoes
      ORDER BY geom <-> ST_SetSRID(ST_MakePoint($1, $2), 4326)
      LIMIT 1;
    "
    resultado <- dbGetQuery(con, query_dist, params = list(lon, lat))
    if (nrow(resultado) == 0) {
      stop("Nenhuma estação encontrada no banco de dados.")
    }
    nome_estacao <- resultado$codigo[1]
    cat(paste("Coordenadas fornecidas. Estação mais próxima encontrada:", nome_estacao, "\n"))
  }
  
  if (is.null(nome_estacao)) {
    stop("Deve ser fornecido 'nome_estacao' ou 'lat'/'lon'.")
  }

  # Lê os dados da estação do banco
  dados_horarios <- ler_dados_estacao_db(nome_estacao, con)

  if (nrow(dados_horarios) < 96) {
    warning(paste("Nenhum dado encontrado (ou dados insuficientes para 96h) para a estação", nome_estacao))
    return(NULL)
  }

  # Limpeza e tratamento de falhas
  dados_horarios <- dados_horarios %>%
    mutate(precipitacao_mm = ifelse(precipitacao_mm < 0, 0, precipitacao_mm)) %>%
    replace_na(list(precipitacao_mm = 0))

  # Engenharia de dados: acumulado de 96h e amostragem diária
  dados_diarios <- dados_horarios %>%
    arrange(data_hora) %>%
    mutate(chuva_acumulada_96h = stats::filter(precipitacao_mm, rep(1, 96), sides = 1, method = "convolution")) %>%
    filter(hour(data_hora) == 0, minute(data_hora) == 0) %>%
    select(data_hora, chuva_acumulada_96h) %>%
    drop_na()

  # Filtra apenas os dias com chuva para o ajuste do modelo
  chuva_positiva <- dados_diarios$chuva_acumulada_96h[dados_diarios$chuva_acumulada_96h > 0]

  if (length(chuva_positiva) < 2) {
    warning(paste("Sem dias de chuva suficientes para o ajuste matemático em", nome_estacao))
    return(NULL)
  }

  # ---- Cálculo dos Parâmetros Tweedie ----
  params <- list()
  if (metodo_ajuste == "matematico") {
    params$p <- 1.5
    params$mu <- mean(dados_diarios$chuva_acumulada_96h)
    params$phi <- var(dados_diarios$chuva_acumulada_96h) / (params$mu^params$p)
  } else { # Método "pacote"
    invisible(capture.output(fit <- tweedie.profile(chuva_acumulada_96h ~ 1, data = dados_diarios, p.vec = seq(1.1, 1.9, 0.1), do.plot = FALSE)))
    params$p <- fit$p.max
    params$phi <- fit$phi.max
    modelo_glm <- glm(chuva_acumulada_96h ~ 1, data = dados_diarios, family = tweedie(var.power = params$p, link.power = 0))
    params$mu <- exp(coef(modelo_glm)[1])
  }

  # ---- Cálculo dos Limiares ----
  limiares <- tibble(
    Nivel = c("Moderado", "Alto", "Muito Alto", "Altíssimo"),
    Percentil = cortes,
    Limiar_mm = round(qtweedie(cortes, power = params$p, mu = params$mu, phi = params$phi), 2)
  )
  
  # ---- Metadados do Processo ----
  meta <- list(
    estacao = nome_estacao,
    data_inicio = min(dados_diarios$data_hora),
    data_fim = max(dados_diarios$data_hora),
    anos = as.numeric(difftime(max(dados_diarios$data_hora), min(dados_diarios$data_hora), units = "days")) / 365.25,
    n_dados = nrow(dados_horarios),
    n_ausentes = sum(is.na(dados_horarios$precipitacao_mm)),
    pct_ausentes = sum(is.na(dados_horarios$precipitacao_mm)) / nrow(dados_horarios)
  )
  meta$status <- case_when(
      meta$pct_ausentes > 0.10 ~ "Muitos Faltantes",
      meta$anos < 10 ~ "Série Curta",
      TRUE ~ "Adequada"
  )

  return(list(
    estacao = nome_estacao,
    limiares = limiares,
    params = params,
    metadata = meta,
    dados = dados_diarios # Opcional: retornar os dados para visualização
  ))
}