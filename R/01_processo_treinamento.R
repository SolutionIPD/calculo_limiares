# ==============================================================================
# Script: 01_processo_treinamento.R
# Objetivo: Rodar a extração de parâmetros para todas as estações INMET
#           disponíveis e salvar os resultados em um arquivo RDS.
# ==============================================================================

# 1. Carregar as funções
source("/home/thiago/calculo_limiares/R/funcoes_calculo.R")

# 2. Diretórios de entrada e saída
dir_brutos <- "/home/thiago/calculo_limiares/dados/inmet_brutos"
dir_params <- "/home/thiago/calculo_limiares/dados/parametros"

# Cria a pasta de destino (dados/parametros) caso não exista
dir.create(dir_params, recursive = TRUE, showWarnings = FALSE)

# 3. Obter todas as estações disponíveis
cat("Mapeando estações disponíveis no diretório...\n")
meta <- obter_metadados_estacoes(dir_brutos)
lista_estacoes <- unique(meta$estacao)
cat(sprintf("=> Encontradas %d estações para processamento.\n\n", length(lista_estacoes)))

# 4. Processar cada estação (Loop)
resultados_treinamento <- purrr::map_dfr(lista_estacoes, function(est) {
  cat(sprintf("Processando: %s... ", est))
  
  # O tryCatch impede que o erro em uma estação com dados ruins trave todo o script
  resultado <- tryCatch({
    # Usamos o método matemático pela extrema velocidade!
    res <- suppressMessages(calcular_limiares_estacao(nome_estacao = est, dir_brutos = dir_brutos, metodo_ajuste = "matematico"))
    
    # Retornamos uma linha de dataframe estruturada
    tibble(
      station = res$estacao,
      horas = 96,
      mu = res$params$mu,
      phi = res$params$phi,
      power = res$params$power,
      data_inicio = res$metadata$data_inicio,
      data_fim = res$metadata$data_fim,
      n_dados = res$metadata$n_dados,
      n_ausentes = res$metadata$n_ausentes
    )
  }, error = function(e) {
    cat(sprintf("[ERRO: %s] ", e$message))
    return(NULL)
  })
  
  cat("OK\n")
  return(resultado)
})

# 5. Salvar os parâmetros no formato esperado pelo dashboard
arquivo_saida <- file.path(dir_params, "tb_params_atual.rds")
saveRDS(resultados_treinamento, arquivo_saida)

cat("\n=======================================================\n")
cat("Treinamento Concluído!\n")
cat(sprintf("Parâmetros gerados para %d estações.\n", nrow(resultados_treinamento)))
cat(sprintf("Arquivo salvo em: %s\n", arquivo_saida))
cat("=======================================================\n")