#' ==============================================================================
#' API DE CONSULTAS ESPACIAIS E NOMINAIS (POSTGIS)
#' ==============================================================================

#' Consulta Limiares de Deslizamento via PostGIS
#'
#' Esta função é o motor central (roteador) para requisições de limiares. Ela delega o 
#' trabalho pesado de busca e cruzamento espacial para o banco de dados (PostGIS),
#' garantindo performance máxima.
#'
#' @param con Objeto de conexão ativa com o banco PostgreSQL.
#' @param metodo Caractere. Como você quer buscar as estações? 
#'               \itemize{
#'                 \item \code{"nome"}: Busca por parte do nome da estação.
#'                 \item \code{"coordenada"}: Busca por um ponto de latitude/longitude.
#'                 \item \code{"poligono"}: Busca por uma área fechada (Shapefile/sf convertido para WKT).
#'                 \item \code{"grade"}: Cria uma grade (quadrículas) sobre uma área e calcula os limiares 
#'                                       para cada célula usando a interseção espacial do PostGIS.
#'               }
#' @param nomes Vetor de caracteres. (Usado se \code{metodo = "nome"}). 
#'              Ex: \code{c("BENTO", "PORTO ALEGRE")}.
#' @param lon Numérico. Longitude em WGS84 decimal (Usado se \code{metodo = "coordenada"}).
#' @param lat Numérico. Latitude em WGS84 decimal (Usado se \code{metodo = "coordenada"}).
#' @param raio_km Numérico. (Usado se \code{metodo = "coordenada"}). Se for informado,
#'                busca todas as estações dentro desse raio. Se deixado como \code{NULL},
#'                busca magicamente a estação MAIS PRÓXIMA do ponto informado.
#' @param wkt_poligono Caractere. String Well-Known Text (Usado se \code{metodo = "poligono"}).
#'                     Pode ser facilmente obtida a partir de um shapefile lido com \code{sf}
#'                     usando \code{sf::st_as_text(sf::st_geometry(meu_shape))}.
#' @param tamanho_grade_km Numérico. Tamanho da célula em km (Usado se \code{metodo = "grade"}). Padrão: 100.
#' @param agregar_estacoes Lógico. Se \code{TRUE} (e a busca retornar mais de uma estação),
#'                         agrega os dados pluviométricos para calcular um único limiar médio areal.
#'                         Se \code{FALSE}, devolve uma lista com o limiar individual de cada uma.
#'
#' @return Uma lista contendo as estações encontradas e os limiares solicitados.
#' @export
#'
#' @examples
#' \dontrun{
#' con <- conectar_db()
#' 
#' # 1. Busca por nome (traz todas que contêm "BENTO" ou "CAXIAS")
#' res_nome <- consultar_limiares(con, metodo = "nome", nomes = c("BENTO", "CAXIAS"))
#' 
#' # 2. Busca por coordenada (Estação mais próxima do centro do RS)
#' res_coords <- consultar_limiares(con, metodo = "coordenada", lon = -53.5, lat = -29.5)
#' 
#' # 3. Busca por coordenada num raio de 50km (Média areal do entorno)
#' res_raio <- consultar_limiares(con, metodo = "coordenada", lon = -51.2, lat = -30.0, raio_km = 50)
#' 
#' # 4. Busca por Polígono (WKT)
#' wkt_ex <- sf::st_as_text(sf::st_geometry(meu_municipio_sf))
#' res_poly <- consultar_limiares(con, metodo = "poligono", wkt_poligono = wkt_ex)
#' 
#' # 5. Cria Grade de 100x100km sobre o RS
#' res_grade <- consultar_limiares(con, metodo = "grade", tamanho_grade_km = 100)
#' }
consultar_limiares <- function(con, 
                               metodo = c("nome", "coordenada", "poligono", "grade"),
                               nomes = NULL,
                               lon = NULL, lat = NULL, raio_km = NULL,
                               wkt_poligono = NULL,
                               tamanho_grade_km = 100,
                               agregar_estacoes = TRUE) {
  
  metodo <- match.arg(metodo)
  query_estacoes <- ""
  
  # ============================================================================
  # CONSTRUÇÃO DA QUERY SQL ESPACIAL
  # ============================================================================
  if (metodo == "nome") {
    if (is.null(nomes) || length(nomes) == 0) stop("Forneça pelo menos um nome para a busca.")
    nomes_like <- paste0("'%", toupper(nomes), "%'", collapse = ", ")
    
    query_estacoes <- sprintf("
      SELECT codigo, nome, ST_AsText(geom) as wkt_geom 
      FROM estacoes 
      WHERE UPPER(nome) LIKE ANY(ARRAY[%s]);
    ", nomes_like)
    
  } else if (metodo == "coordenada") {
    if (is.null(lon) || is.null(lat)) stop("Forneça 'lon' e 'lat' para a busca por coordenada.")
    
    if (!is.null(raio_km)) {
      # Usando geography para um raio perfeito sobre o globo (conversão KM -> Metros)
      query_estacoes <- sprintf("
        SELECT codigo, nome, ST_AsText(geom) as wkt_geom,
               ST_Distance(geom::geography, ST_SetSRID(ST_MakePoint(%f, %f), 4326)::geography) / 1000.0 as distancia_km
        FROM estacoes 
        WHERE ST_DWithin(geom::geography, ST_SetSRID(ST_MakePoint(%f, %f), 4326)::geography, %f)
        ORDER BY distancia_km ASC;
      ", lon, lat, lon, lat, raio_km * 1000)
    } else {
      # Operador <-> realiza busca indexada "K-Nearest Neighbor" no PostGIS (Otimização Extrema)
      query_estacoes <- sprintf("
        SELECT codigo, nome, ST_AsText(geom) as wkt_geom,
               ST_Distance(geom::geography, ST_SetSRID(ST_MakePoint(%f, %f), 4326)::geography) / 1000.0 as distancia_km
        FROM estacoes 
        ORDER BY geom <-> ST_SetSRID(ST_MakePoint(%f, %f), 4326) 
        LIMIT 1;
      ", lon, lat, lon, lat)
      agregar_estacoes <- FALSE # Se for apenas uma estação, não agregamos nada
    }
    
  } else if (metodo == "poligono") {
    if (is.null(wkt_poligono)) stop("Forneça uma string WKT válida no parâmetro 'wkt_poligono'.")
    query_estacoes <- sprintf("
      SELECT codigo, nome, ST_AsText(geom) as wkt_geom 
      FROM estacoes 
      WHERE ST_Intersects(geom, ST_GeomFromText('%s', 4326));
    ", wkt_poligono)
    
  } else if (metodo == "grade") {
    if (is.null(tamanho_grade_km)) stop("Forneça 'tamanho_grade_km' para o método 'grade'.")
    
    # Define a área de cobertura (padrão: Bounding Box do RS se wkt_poligono for NULL)
    wkt_bounds <- if (!is.null(wkt_poligono)) wkt_poligono else "POLYGON((-57.7 -33.7, -49.6 -33.7, -49.6 -27.0, -57.7 -27.0, -57.7 -33.7))"
    
    # 1 grau ~= 111.12 km no equador
    tamanho_graus <- tamanho_grade_km / 111.12
    
    # Otimização PostGIS 3.1+: ST_SquareGrid cria a malha perfeitamente no banco.
    # Em seguida, filtramos apenas as células que possuem estações.
    query_estacoes <- sprintf("
      WITH grade AS (
        SELECT i, j, geom 
        FROM ST_SquareGrid(%f, ST_GeomFromText('%s', 4326))
      )
      SELECT 
        g.i, g.j, ST_AsText(g.geom) as wkt_geom,
        COUNT(e.codigo) as num_estacoes,
        STRING_AGG(e.codigo, ', ') as ids_estacoes
      FROM grade g
      JOIN estacoes e ON ST_Intersects(e.geom, g.geom)
      WHERE ST_Intersects(g.geom, ST_GeomFromText('%s', 4326))
      GROUP BY g.i, g.j, g.geom;
    ", tamanho_graus, wkt_bounds, wkt_bounds)
  }
  
  # ============================================================================
  # RECUPERAÇÃO DAS ESTAÇÕES
  # ============================================================================
  estacoes_alvo <- DBI::dbGetQuery(con, query_estacoes)
  
  if (nrow(estacoes_alvo) == 0) {
    message("Nenhuma estação ou célula ativa encontrada para os critérios informados.")
    return(NULL)
  }
  
  message(sprintf("Sucesso! Encontrada(s) %d ocorrência(s) ativa(s).", nrow(estacoes_alvo)))
  
  resultados <- list(
    metadata = estacoes_alvo
  )
  
  # ============================================================================
  # INTEGRAÇÃO COM SEU CORE (ROTEAMENTO)
  # ============================================================================
  if (metodo == "grade") {
    message("-> Calculando Limiares para cada célula ativa da grade...")
    
    resultados$limiares_agregados <- purrr::map_dfr(1:nrow(estacoes_alvo), function(idx) {
      celula <- estacoes_alvo[idx, ]
      res_celula <- calcular_limiares_poligono_db(con, wkt_poligono = celula$wkt_geom)
      
      if (is.null(res_celula)) return(NULL)
      
      tibble::tibble(
        i = celula$i,
        j = celula$j,
        estacoes_ids = celula$ids_estacoes,
        limiar_moderado = res_celula$limiares$Limiar_mm[res_celula$limiares$Nivel == "Moderado"],
        limiar_alto = res_celula$limiares$Limiar_mm[res_celula$limiares$Nivel == "Alto"],
        limiar_muito_alto = res_celula$limiares$Limiar_mm[res_celula$limiares$Nivel == "Muito Alto"],
        limiar_altissimo = res_celula$limiares$Limiar_mm[res_celula$limiares$Nivel == "Altíssimo"]
      )
    })
    
  } else if (agregar_estacoes && nrow(estacoes_alvo) > 1) {
    message("-> Calculando Precipitação Média Areal (Tweedie) para a rede combinada...")
    
    if (metodo == "poligono") {
      resultados$limiares_agregados <- calcular_limiares_poligono_db(con, wkt_poligono = wkt_poligono)
    } else {
      # TODO: Implemente/Adapte em seu funcoes_db.R uma variação de
      # calcular_limiares_poligono_db() que faça a agregação recebendo um 
      # vetor de IDs exatos: estacoes_alvo$codigo.
      resultados$limiares_agregados <- list(aviso = "Executar agregacao por códigos de estação.")
    }
    
  } else {
    message("-> Recuperando parâmetros Tweedie e limiares quantílicos individuais...")
    
    # DICA: Aqui você pode dar um subset no seu banco ".rds" pre-treinado!
    # tb_params <- readRDS("dados/parametros/tb_params_atual.rds")
    # resultados$limiares_individuais <- tb_params[tb_params$codigo %in% estacoes_alvo$codigo, ]
    
    resultados$limiares_individuais <- list(aviso = "Carregar dados das estações individualmente.")
  }
  
  return(resultados)
}