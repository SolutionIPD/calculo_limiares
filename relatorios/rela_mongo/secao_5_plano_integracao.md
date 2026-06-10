
Para que a plataforma comece a consumir as novas modelagens estatísticas, **não será necessário alterar o schema do banco de dados ou a interface**.

O pipeline de dados gerará um formato 100% compatível com a coleção `limits` que já existe. As diferenças nos dados enviados serão:

1. **`station`**: Preenchido com a mesma identificação de cada ponto.
2. **`horas`**: Será fixado estritamente em **`96`** para todas as estações. (Essa padronização simplifica o alerta e demonstrou excelente confiabilidade na saturação do solo durante os novos testes).
3. **`r0`, `r1`, `r2`, `r3`**: As colunas receberão as novas estimativas em milímetros que determinam os patamares de alerta.
4. **Parâmetros Base**: `mu`, `phi` e `power` serão atualizados com os novos indicadores das equações.
5. Demais controles (`__v`, `createdAt`, `updatedAt`) seguem o mesmo padrão preenchido com datas atualizadas.

### 5.1 Frequência de Execução (Cronjob)
Como os limiares da distribuição de Tweedie são baseados no comportamento histórico de longo prazo, a variação de um único dia de chuva não causa mudanças bruscas nos gatilhos. 
Por conta disso, recomendamos que a rotina de re-treinamento e atualização dos limiares seja engatilhada **semanalmente** (ex: madrugadas de domingo).

### 5.2 Abordagem 1: Injeção Direta no Banco (Via R)
Nesta abordagem, o próprio script em R limpa a coleção e reinsere a matriz atualizada. É a forma mais rápida, operando diretamente via `mongolite`.

```r
#| eval: false
library(mongolite)

# 1. Conecta na coleção Limits
m_limits <- mongo(collection = "limits", db = Sys.getenv("MONGO_DB"), url = Sys.getenv("MONGO_URL"))

# 2. Remove os limites legados (Drop seguro)
m_limits$remove('{}')

# 3. Insere o novo dataframe com limites 96h calculados
m_limits$insert(df_novos_limites)
```

### 5.3 Abordagem 2: Webhook / API REST (Via cURL)
Caso a equipe de Engenharia de Software opte por não liberar acesso de escrita direto ao MongoDB por questões de arquitetura/segurança, o pipeline em R exportará um arquivo `.json` e fará um `POST` disparando a atualização para o Backend da plataforma via **cURL**.

```bash
# O R salva o df_novos_limites.json e notifica a API da plataforma
curl -X POST https://api.suaplataforma.com.br/v1/limits/sync \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer <SEU_TOKEN_DE_SERVICO>" \
     -d @df_novos_limites.json
```

Desta forma, o sistema fica completamente desacoplado: a estatística processa e notifica o backend, que por sua vez se encarrega de persistir a informação validada no MongoDB.
