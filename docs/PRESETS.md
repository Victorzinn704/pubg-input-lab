# Biblioteca de presets — 1.4.0

Abra **Biblioteca: presets, contexto, curvas e atalhos** no painel. Abrir a biblioteca desarma o perfil. Salvar ou escolher um preset não dispara nem ativa movimento; a ativação continua pelo atalho da arma ou pelo painel.

## Criar uma configuração

1. Selecione um perfil existente e use **Duplicar**, ou clique em **Novo**.
2. Preencha nome, arma, mira, zoom, postura, acessórios e condições de sensibilidade/DPI/resolução.
3. Na aba **Curva X/Y**, informe os tempos finais acumulados e os movimentos por intervalo. Os tempos devem crescer. X positivo aponta para a direita; Y positivo aponta para baixo.
4. Clique em **Salvar preset**. A gravação preserva todos os segmentos e mantém uma cópia `.bak` da biblioteca anterior.
5. Em **Atalhos e tela**, associe o perfil salvo a uma tecla. Se a tecla já estiver ocupada, remova a associação antiga antes de substituí-la.

As combinações são explícitas e selecionadas manualmente. Escolher “6x” ou “Agachado” registra o contexto da curva; não inventa um multiplicador nem detecta automaticamente o estado no jogo. Duplique um preset para criar outra combinação e ajuste sua curva/ganho separadamente.

Os perfis originais de `profiles.ini` e `calibrations.ini` permanecem protegidos no editor: salvar um deles cria uma cópia local com outro ID. O ganho de uma cópia pode ser alterado com F3/F4 e persistido com F5, incluindo a curva completa. No painel simples, **Salvar ajuste constante** não substitui curvas compostas: use o editor de segmentos.

## Curvas e prévia

O gráfico usa azul para X e verde para Y, tempo no eixo horizontal e escala vertical automática. A tabela contém os valores exatos editáveis; a apresentação numérica usa seis algarismos significativos. O gráfico aplica o ganho salvo no rascunho, não representa impactos medidos nem a trajetória observada no jogo. Alterações de ganho são refletidas após salvar ou aplicar uma edição na curva.

**Por tempo** distribui a taxa pelo tempo decorrido; **Por passo** produz movimentos nos intervalos programados, sujeitos ao temporizador. Tiro único exige **Por passo** e valores inteiros. Intervalo entre cliques é uma proteção para tiro único, não um gerador de disparos.

## Importar, exportar e referências

**Exportar INI** salva o preset selecionado com contexto, origem, ganho e curva. **Importar INI** aceita bibliotecas no esquema 1. IDs repetidos recebem uma nova identidade; nenhum preset existente é sobrescrito pela importação. Arquivos inválidos são rejeitados antes da gravação. Configurações podem conter informações pessoais digitadas pelo usuário; revise antes de compartilhar.

A aba **Referências SCHOOL** contém 26 armas e três posturas. A conversão pede intervalo assumido, escala e duração, mostra a curva como rascunho e registra as hipóteses. Ela não sobrescreve sua calibração. Consulte o [modelo e a licença](../references/school/README.md).

## Atalhos e ponto central

- Ctrl+Alt+A–Z ou Ctrl+Alt+1–9: associação editável por perfil; **D** é reservada.
- Ctrl+Alt+D: parada global, mesmo fora do jogo.
- Ctrl+Alt+0: alternar ponto central, com o jogo em foco.
- Ponto central: desativado por padrão, tamanho de 3 a 9 pixels e cor hexadecimal. Aparece apenas na janela alvo com foco, após a geometria estabilizar. Não captura cliques nem foco.
- Mouse4 e Mouse5 continuam sem associação pelo laboratório.

Mudanças de atalho feitas pelo editor são aplicadas imediatamente e desarmam o perfil. Edição externa dos arquivos ainda exige reiniciar o aplicativo. Um preset associado não pode ser excluído antes de remover sua associação.

## Arquivos e recuperação

| Arquivo | Conteúdo |
| --- | --- |
| `presets.local.ini` | Biblioteca pessoal, esquema 1, até 256 presets e 1000 segmentos por preset |
| `presets.local.ini.bak` | Revisão anterior à última gravação |
| `hotkeys.ini` / `.bak` | Associações e revisão anterior |
| `display.local.ini` / `.bak` | Preferências do ponto central |

Esses arquivos não são versionados. Feche o aplicativo antes de restaurar uma cópia `.bak`. Copie o backup sobre o arquivo correspondente e reabra. A validação continua ativa; uma versão de esquema desconhecida não é reinterpretada silenciosamente.

As sessões incluem snapshots da biblioteca na inicialização e a cada gravação. As evidências descrevem o software e o envio ao Windows. A qualidade do spray exige ensaios comparáveis com as condições registradas.
