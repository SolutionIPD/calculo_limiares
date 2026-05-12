# ==============================================================================
# Script: exemplos_uso.R
# Objetivo: Demonstrar o uso da função de cálculo de limiares (Tweedie)
# ==============================================================================

# 1. Carregar as funções criadas
# (Nota: carregando a partir do diretório onde o arquivo foi salvo)
source("/home/thiago/calculo_limiares/R/funcoes_calculo.R")

# ------------------------------------------------------------------------------
# Exemplo 1: Busca pelo Nome da Estação (Rede INMET)
# ------------------------------------------------------------------------------
cat("\n=======================================================\n")
cat("EXEMPLO 1: Busca por Nome com Pacote Tweedie (Padrão)\n")
cat("=======================================================\n")

# A função aceita parte do nome. Se os dados existirem na pasta inmet_brutos, ela fará o cálculo.
resultado_bento_pacote <- calcular_limiares_estacao(nome_estacao = "BENTO GONCALVES") # metodo_ajuste = "pacote" por padrão

cat("\n=> Limiares (Acumulado 96h):\n")
print(resultado_bento_pacote$limiares)

cat("\n=> Parâmetros da Distribuição Tweedie Ajustada:\n")
print(resultado_bento_pacote$params)


# ------------------------------------------------------------------------------
# Exemplo 2: Busca por Coordenadas (Ex: Estação Externa / Cemaden)
# ------------------------------------------------------------------------------
cat("\n=======================================================\n")
cat("EXEMPLO 2: Busca por Coordenadas (Veranópolis)\n")
cat("=======================================================\n")

# Passando as coordenadas aproximadas de Veranópolis (que não possui CSV histórico no INMET)
resultado_vdt <- calcular_limiares_estacao(lat_busca = -28.93, lon_busca = -51.55)

cat(sprintf("\n=> A estação INMET mais próxima utilizada como base foi a %s (%.2f km de distância).\n", 
            resultado_vdt$estacao, resultado_vdt$distancia_km))

cat("\n=> Limiares Sugeridos:\n")
print(resultado_vdt$limiares)


# ------------------------------------------------------------------------------
# Exemplo 3: Comparação com o Método Matemático Exato (Mais rápido)
# ------------------------------------------------------------------------------
cat("\n=======================================================\n")
cat("EXEMPLO 3: Busca por Nome com Método Matemático (Bento Gonçalves)\n")
cat("=======================================================\n")

resultado_bento_mat <- calcular_limiares_estacao(nome_estacao = "BENTO GONCALVES", metodo_ajuste = "matematico")

cat("\n=> Limiares usando a matemática do professor (Acumulado 96h):\n")
print(resultado_bento_mat$limiares)

cat("\n=> Parâmetros Calculados Matematicamente:\n")
print(resultado_bento_mat$params)