# Auditoria 1.3.0 — 2026-10-19

Escopo: código da aplicação, configuração, atalhos, máquina de estados, persistência, análise de sessões, indicador e preparação de um repositório reproduzível. Não houve leitura de memória do jogo nem teste de anticheat.

## Achados tratados

| Problema | Mudança | Evidência exigida |
| --- | --- | --- |
| Seleção e ativação em comandos separados; sobreposição de atalhos antigos | Ctrl+Alt+letra seleciona e ativa; D para todos; tabela configurável | Testes de parser e transição, incluindo todas as armas |
| Trocas podiam recriar estado sem um contrato central explícito | Transição comum preserva início de sessão e invalida a geração anterior | Troca durante rajada, repetição idempotente e sessão expirada |
| Rearmar após F3/F4 podia descartar o ganho aplicado e recarregar o salvo | Rearmar a mesma arma preserva o ganho atual; outra arma carrega o salvo | Ajustar, desarmar e rearmar sem salvar |
| Amplitude e ganho aceitos separadamente podiam gerar valor efetivo acima do limite, truncado no motor | Validação comum antes de carregar/aplicar/salvar | Rejeitar Y=3, ganho=5, limite=12; aceitar o limite exato; salvar sem corromper o arquivo anterior |
| `StartProfile` inexistente era substituído silenciosamente pelo primeiro perfil | Rejeição explícita de referência inválida | Configuração com nome digitado incorretamente |
| Analisador aceitava cabeçalho incorreto quando o CSV não tinha eventos | Validação independente da existência de linhas de dados | Cabeçalho errado sem eventos rejeitado; sessão vazia válida aceita |
| Instalação dependia de runtime e arquivos locais já existentes | Download oficial com checksum e exemplos separados dos arquivos pessoais | Preparar e validar uma cópia limpa |
| Históricos, calibrações e artefatos misturados ao código de entrega | Regras de exclusão e inspeção da lista de arquivos versionados | Verificar conteúdo do commit antes de publicar |

## Limites mantidos explícitos

- Os 15 perfis de arma do exemplo têm curvas zeradas, identificadas como não medidas. Seleção automática do perfil não calibra a arma. Ajustes locais não são publicados nem considerados medições validadas.
- Os temporizadores do Windows não garantem intervalos exatos. No modo por tempo, o motor limita a integração de atraso para evitar concentrar movimento; isso pode reduzir o movimento acumulado quando há atrasos.
- O logger realiza operações síncronas de disco. Buffer limitado não implica limite de latência. Não foi medido desempenho dentro de uma partida nesta auditoria.
- Não existe reconhecimento de arma, acessórios, mira, aliados ou adversários. Não há controle adaptativo nem telemetria interna do PUBG.
- Testes sintéticos validam o software, não a resposta do jogo, a qualidade do spray ou a ausência de punições.

## Próximas melhorias, em ordem

1. Medir duração das gravações e distribuição de atrasos do ciclo em ensaios controlados. Só então decidir se separar o logger do caminho de envio.
2. Criar um protocolo de calibração reprodutível, com sensibilidade, resolução, mira e acessórios registrados; comparar resultados antes de adotar ajustes como referência.
3. Extrair a interface do controlador se novas telas ou modos justificarem a divisão. Manter motor e testes independentes do Windows.
4. Versionar o esquema dos arquivos de configuração antes de adicionar migrações automáticas. Migrações precisam de backup, validação e reversão.
5. Acrescentar exportação anonimizada de evidências antes de permitir anexos de logs em issues públicas.

Critério de conclusão desta entrega: testes locais, validação a partir de configuração de exemplo, código publicado no SHA revisado e execução correspondente do CI verificada no GitHub. A aceitação visual e funcional dentro do jogo permanece um ensaio separado.
