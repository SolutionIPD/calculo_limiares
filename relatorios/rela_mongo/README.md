# Exploração e Proposta de Mudanças - Integração MongoDB

Esta pasta é dedicada à análise do banco de dados legado (MongoDB) da plataforma e ao planejamento das integrações da nova metodologia de limiares.

## Objetivos
1. **Mapeamento do Legado**: Documentar a estrutura atual das coleções de alertas e limiares (ex: coleção `limits`).
2. **Avaliação de Impacto**: Analisar o impacto da mudança da metodologia antiga (que possuía múltiplas janelas de horas) para a nova (focada na janela de 96 horas).
3. **Exploração de Novos Dados (Sensores Locais)**: Investigar os dados de estações/pluviômetros próprios armazenados no MongoDB para avaliar a viabilidade de utilizá-los no treinamento de modelos estatísticos (Tweedie).
4. **Proposta de Arquitetura**: Definir a melhor abordagem para atualizar a plataforma (sincronizar PostGIS -> Mongo via R, ou refatorar a plataforma para consumir uma nova API do PostGIS).

## Arquivos
- `proposta_mudancas.qmd`: Relatório técnico iterativo detalhando as descobertas e levantando questões arquiteturais.

## Como compilar o relatório
`quarto preview relatorios/rela_mongo/proposta_mudancas.qmd`