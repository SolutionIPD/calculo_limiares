#!/bin/bash

# Diretórios de origem e destino
DIR_ZIPS="$HOME"
DIR_ORIGEM="$HOME/datasets-landslides/dados"
DIR_DESTINO="$HOME/calculo_limiares/dados/inmet_brutos"

# Cria a pasta base de destino
mkdir -p "$DIR_DESTINO"

echo "Procurando arquivos ZIP do INMET e extraindo apenas dados do RS..."

# Busca por arquivos .zip de anos (ex: 2017.zip até 2026.zip) na sua pasta home
for zip_file in "$DIR_ZIPS"/[0-9][0-9][0-9][0-9].zip; do
    if [ -f "$zip_file" ]; then
        echo "-> Extraindo RS de: $(basename "$zip_file")..."
        # O curinga de extração contempla subpastas (*/*) e raiz.
        # Redirecionamos a saída para /dev/null para esconder os avisos de "caution" inofensivos.
        unzip -q -j -o "$zip_file" '*/*_RS_*.CSV' '*/*_RS_*.csv' '*_RS_*.CSV' '*_RS_*.csv' -d "$DIR_ORIGEM" > /dev/null 2>&1
    fi
done

echo "Buscando e organizando arquivos do INMET..."

# Encontra todos os arquivos que começam com INMET_ (case-insensitive)
find "$DIR_ORIGEM" -type f -iname "INMET_*.CSV" | while read -r arquivo; do
    nome_arquivo=$(basename "$arquivo")
    
    # O formato dos arquivos do INMET é: INMET_REGIAO_UF_CODIGO_NOME_DATA_A_DATA.CSV
    uf_estacao=$(echo "$nome_arquivo" | cut -d'_' -f3)
    
    # Mantém apenas as estações do Rio Grande do Sul (RS)
    if [ "$uf_estacao" != "RS" ]; then
        continue
    fi
    
    codigo_estacao=$(echo "$nome_arquivo" | cut -d'_' -f4)
    nome_estacao=$(echo "$nome_arquivo" | cut -d'_' -f5)
    
    pasta_estacao="$DIR_DESTINO/${codigo_estacao}_${nome_estacao}"
    mkdir -p "$pasta_estacao"
    
    cp "$arquivo" "$pasta_estacao/"
done

echo "Concluído! Arquivos organizados por estação em $DIR_DESTINO"