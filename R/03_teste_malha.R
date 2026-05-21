
# ==============================================================================
# 03_TESTE_MALHA.R
#
# Objetivo: Dividir o estado do Rio Grande do Sul (RS) em uma malha de ~100x100km.
# Para cada célula da malha, calcular os limiares de deslizamento agregando 
# todas as estações presentes no polígono (Precipitação Média Areal).
# ==============================================================================

library(tidyverse)
library(sf)

source("R/funcoes_db.R")

cat("Gerando malha de testes sobre o Rio Grande do Sul...\n")

# 1. Define uma Bounding Box (caixa) aproximada do RS
# Longitude: -57.7 a -49.6 | Latitude: -33.7 a -27.0
bbox_rs <- st_sfc(st_polygon(list(matrix(c(
  -57.7, -33.7,
  -49.6, -33.7,
  -49.6, -27.0,
  -57.7, -27.0,
  -57.7, -33.7
), ncol = 2, byrow = TRUE))), crs = 4326)

# 2. Cria o Grid
# cellsize = 0.9 graus equivale grosseiramente a ~100km
malha <- st_make_grid(bbox_rs, cellsize = c(0.9, 0.9), square = TRUE) %>%
  st_sf(id_celula = 1:length(.), geometry = .)

cat(sprintf("Malha gerada com %d células.\n", nrow(malha)))

# Conecta ao banco de dados
con <- conectar_db()

# 3. Calcula os Limiares para cada Célula (Polígono)
resultados_malha <- purrr::map_dfr(1:nrow(malha), function(i) {
  
  celula <- malha[i, ]
  wkt_geom <- st_as_text(st_geometry(celula))
  
  # A função vai retornar NULL se o polígono cair no mar, na Argentina, ou num buraco sem estação
  res <- calcular_limiares_poligono_db(con, wkt_poligono = wkt_geom)
  
  if (is.null(res)) {
    return(NULL)
  }
  
  cat(sprintf("Célula %d: Encontrou dados! Calculando limiares regionais...\n", celula$id_celula))
  
  tibble(
    id_celula = celula$id_celula,
    max_estacoes_poligono = res$metadata$max_estacoes_simultaneas,
    mu = res$params$mu,
    phi = res$params$phi,
    limiar_moderado = res$limiares$Limiar_mm[res$limiares$Nivel == "Moderado"],
    limiar_alto = res$limiares$Limiar_mm[res$limiares$Nivel == "Alto"],
    limiar_muito_alto = res$limiares$Limiar_mm[res$limiares$Nivel == "Muito Alto"],
    limiar_altissimo = res$limiares$Limiar_mm[res$limiares$Nivel == "Altíssimo"]
  )
})

dbDisconnect(con)

cat("===================================================\n")
cat(sprintf("Teste concluído. %d células possuíam estações ativas.\n", nrow(resultados_malha)))
cat("===================================================\n")

# 4. Junta os resultados à malha e plota os mapas
cat("Baixando contorno do RS para o fundo do mapa...\n")
rs_geom <- geobr::read_state(code_state = "RS", showProgress = FALSE)

cat("Gerando plot dos 4 limiares (salvando em 'mapa_limiares_malha.png')...\n")

malha_resultados <- malha %>%
  left_join(resultados_malha, by = "id_celula")

malha_long <- malha_resultados %>%
  pivot_longer(
    cols = starts_with("limiar_"),
    names_to = "Nivel",
    values_to = "Limiar_mm"
  ) %>%
  mutate(
    Nivel = factor(Nivel, 
                   levels = c("limiar_moderado", "limiar_alto", "limiar_muito_alto", "limiar_altissimo"), 
                   labels = c("Moderado", "Alto", "Muito Alto", "Altíssimo"))
  )

p <- ggplot(malha_long) +
  geom_sf(data = rs_geom, fill = "gray90", color = "black", linewidth = 0.4) +
  geom_sf(aes(fill = Limiar_mm), color = "gray20", linewidth = 0.2, alpha = 0.8) +
  scale_fill_viridis_c(option = "turbo", name = "Limiar (mm)", na.value = NA) +
  facet_wrap(~ Nivel, ncol = 2) +
  theme_void() +
  labs(
    title = "Limiares de Precipitação por Região (Acumulado 96h)",
    subtitle = "Média Areal em malha de ~100x100 km no RS",
    caption = "Fonte de Dados: INMET | Metodologia: Distribuição Tweedie / MAP"
  ) +
  theme(
    plot.title = element_text(face = "bold", size = 16, hjust = 0.5, margin = margin(b = 10)),
    plot.subtitle = element_text(size = 12, hjust = 0.5, margin = margin(b = 20)),
    strip.text = element_text(face = "bold", size = 14, margin = margin(b = 10)),
    legend.position = "right",
    plot.background = element_rect(fill = "white", color = NA)
  )

ggsave("relatorios/mapa_limiares_malha.png", plot = p, width = 12, height = 10, dpi = 300)
cat("Mapa gerado com sucesso! Você pode visualizar o arquivo 'relatorios/mapa_limiares_malha.png'.\n")
