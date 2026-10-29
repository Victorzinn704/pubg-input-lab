# Histórico de alterações

## 1.5.0 — 2026-10-29

- Painel organizado em Usar, Ajustar e Diagnóstico, com seleção por arma/variante e busca na biblioteca.
- Última seleção e preferência por arma/modo persistidas; atalhos base resolvem a variante preferida ou uma referência com movimento. Atalhos diretos da biblioteca continuam exatos.
- Perfis vazios recusam ativação real; navegação real pula variantes sem movimento.
- Novo modo opcional `timeline`: integração do tempo acumulado com resíduos fracionários, parada por atraso/amplitude e sem fila de recuperação. Cópia por tempo disponível em um botão.
- Conversor explícito de tabela por disparo para curva temporal; mantém unidades, contexto e validação.
- Escala e duração SCHOOL visíveis; novas conversões exigem escala informada. Presets antigos preservados.
- Validação ampliada com testes de temporização irregular, limites, persistência, resolução de variantes, busca e conversão; revisão visual das interfaces.
- Sem calibração automática, reconhecimento de inimigos ou comprovação de eficácia no jogo.

## 1.4.1 — 2026-10-28

- 78 presets SCHOOL (FDCaffeine) prontos para seleção: 26 armas e três posturas, com origem e hipóteses de conversão preservadas.
- Ctrl+. avança e Ctrl+, volta entre presets da mesma arma/modo; navegação circular e ativação com soltura do gatilho.
- Origem/postura visíveis no indicador compacto; crédito completo no nome do preset.
- Importação incremental idempotente, sem substituir ajustes existentes, e biblioteca de exemplo reproduzível.

## 1.4.0 — 2026-10-28

- Biblioteca local com criação, cópia, renomeação, exclusão e importação/exportação de presets.
- Contexto explícito por arma, mira/zoom, postura, acessórios e condições do ensaio.
- Editor de segmentos X/Y com prévia; proteção contra substituição acidental de curvas por constantes.
- Editor de atalhos com aplicação imediata, números 1–9 adicionais e parada Ctrl+Alt+D preservada.
- Ponto central opcional, com tamanho/cor e Ctrl+Alt+0; sem foco ou captura de cliques.
- 26 referências SCHOOL atribuídas e licenciadas, com conversão explícita de intervalo e escala para rascunhos não validados.
- Esquema 1, gravação validada com backup, importação sem sobrescrita de IDs e compatibilidade com arquivos 1.3.0.
- Empacotamento portátil a partir do commit limpo, runtime oficial, licença e SHA-256.

## 1.3.0 — 2026-10-19

- Seleção e ativação por Ctrl+Alt+letra para os 15 perfis de arma.
- Ctrl+Alt+D como único atalho de parada; F12 continua encerrando o aplicativo.
- Validação dos atalhos e transição de perfil com preservação do prazo de sessão.
- Separação de configurações pessoais e exemplos versionados.
- Bootstrap do runtime com versão e checksum fixos, documentação de arquitetura e CI no Windows.

## 1.2.4 — 2026-10-15

- Indicador compacto de uma linha, reposicionado após estabilidade da janela.
- Ocultação fora do alvo e tratamento de fechamento/redimensionamento.

## 1.2.3 — 2026-10-15

- Instância única entre pastas, preservação dos ajustes locais e restauração das funções de Mouse4/Mouse5.
