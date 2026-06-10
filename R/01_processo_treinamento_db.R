# ==============================================================================
# 01_PROCESSO_TREINAMENTO_DB.R
#
# Autor: Gemini Code Assist
#
# Descrição:
# Este script orquestra o processo de treinamento em lote (batch) para
# calcular os limiares de alerta de todas as estações disponíveis no banco
# de dados PostGIS.
#
# O script executa as seguintes etapas:
# 1. Carrega as funções de cálculo que acessam o banco de dados.
# 2. Conecta-se ao banco de dados.
# 3. Obtém a lista de todas as estações cadastradas.
# 4. Itera sobre cada estação, chamando a função `calcular_limiares_estacao_db`
#    para obter os parâmetros e limiares.
# 5. Consolida os resultados de todas as estações em um único tibble.
# 6. Salva o tibble resultante como um arquivo .rds, que serve como o "banco
#    de dados" de parâmetros para a aplicação ou API.
#
# Como usar:
# Execute o script a partir da raiz do projeto: source("R/01_processo_treinamento_db.R")
# ==============================================================================

library(tidyverse)

# Carrega as novas funções que interagem com o banco de dados
source("R/funcoes_db.R")

# Conecta ao banco
con <- conectar_db()

# Obtém a lista de estações diretamente do banco
lista_estacoes <- obter_metadados_estacoes_db(con)

# Roda o processo de cálculo para todas as estações e salva o resultado
tb_parametros_limiares <- purrr::map_dfr(lista_estacoes$codigo, function(est) {
  cat(sprintf("Processando estação %s... ", est))
  
  tryCatch({
    res <- suppressWarnings(calcular_limiares_estacao_db(con, nome_estacao = est, metodo_ajuste = "matematico"))
    
    if (is.null(res)) {
      cat("Ignorada (Dados Insuficientes)\n")
      return(NULL)
    }
    
    cat("OK\n")
    tibble(
      station = res$estacao,
      horas = 96,
      mu = res$params$mu,
      phi = res$params$phi,
      power = res$params$p,
      data_inicio = res$metadata$data_inicio,
      data_fim = res$metadata$data_fim,
      n_dados = res$metadata$n_dados,
      n_ausentes = res$metadata$n_ausentes
    )
  }, error = function(e) {
    cat(sprintf("[ERRO: %s]\n", e$message))
    return(NULL)
  })
})

# Garante que o diretório de destino exista antes de salvar
dir.create("dados/parametros", recursive = TRUE, showWarnings = FALSE)

saveRDS(tb_parametros_limiares, "dados/parametros/tb_params_atual.rds")

cat("\nProcesso de treinamento concluído. Arquivo 'tb_params_atual.rds' foi salvo.\n")

# Desconecta do banco
DBI::dbDisconnect(con)