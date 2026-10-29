# Biblioteca de presets — 1.5.0

Abra **Usar → Editar na biblioteca** no painel. Busque por arma, mira, postura ou nome no campo à esquerda. Abrir a biblioteca desarma o perfil. Salvar ou escolher um preset não dispara nem ativa movimento; a ativação continua pelo atalho da arma ou pelo painel.

## Alternar durante o jogo

Selecione a arma normalmente, por exemplo Ctrl+Alt+A para M416. **Ctrl+.** seleciona e ativa o próximo preset dessa arma; **Ctrl+,** volta ao anterior. A lista é circular entre as variantes da mesma arma/modo. Em entrada real, perfis vazios são pulados; em simulação, também podem ser selecionados. Outros presets pessoais da mesma arma/modo também participam, na ordem da biblioteca.

Atalhos de arma base lembram a variante com movimento escolhida, inclusive entre reinicializações. Sem preferência, um original vazio resolve para a primeira variante compatível com movimento. Atalhos associados diretamente a presets `User_` permanecem exatos. Excluir uma variante preferida faz a resolução voltar a uma alternativa válida; referências de outra arma/modo são ignoradas.

A comparação usa nomes equivalentes (Beryl M762/BerylM762, SCAR-L/SCARL, Tommy Gun/Thompson etc.) e preserva o modo de disparo. Mk14 tiro único não é misturado ao Mk14 automático. Se não houver outra variante, a navegação não altera nem ativa o perfil. Fora do jogo esses atalhos não são capturados. Solte o gatilho após trocar; a troca não produz movimento por si só.

O indicador compacto identifica `SCHOOL/PE`, `SCHOOL/AG` ou `SCHOOL/DEI`. O nome completo inclui **SCHOOL (FDCaffeine)** no painel/biblioteca. O ganho mostrado é o do preset selecionado; os atalhos não alteram a sensibilidade configurada dentro do PUBG. Ao retornar ao preset original, seu ganho salvo é recarregado; use F5 para preservar ajustes antes de trocar.

Instalações novas recebem 78 presets em `presets.local.ini` a partir de `presets.example.ini`. Em uma instalação com biblioteca existente, feche o aplicativo e execute `Importar-SCHOOL.cmd`: somente IDs ausentes são acrescentados. A operação pode ser repetida e preserva edições locais de presets já instalados. Os dados têm intervalo assumido de 16 ms, escala 0,1 e duração de 3 s. Ajuste essas hipóteses pela aba de referências se necessário; não representam medições do seu jogo.

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

**Tempo acumulado** (`timeline`) integra toda a taxa entre duas amostras dentro dos limites, inclusive quando o intervalo real oscila. Não produz pulso inicial nem recupera uma fila após travamentos. Uma amostra que ultrapassaria o movimento máximo por chamada encerra a rajada com `rate_limit`; atraso excessivo encerra com `scheduler_late`. A soltura do gatilho continua obrigatória para retomar. O prazo da rajada pode descartar a última fração de intervalo.

**Tempo limitado (legado)** (`elapsed`) mantém o comportamento anterior, que descarta o tempo além do intervalo nominal. **Por passo** (`step`) produz movimentos nos intervalos programados, sujeitos ao temporizador. Alterar a temporização pode mudar a resposta; use uma cópia para comparar.

**Ajustar → Criar variante por tempo**, no painel principal, faz essa cópia preservando valores, ganho, crédito e contexto. A cópia é selecionada e salva, mas permanece desarmada.

**Criar curva por disparo**, na aba Curva X/Y, recebe linhas `ultima_bala,X,Y` e o intervalo entre tiros. X/Y são contagens do mouse por disparo, não pixels medidos da tela. Cada linha define o incremento por tiro até a última bala informada. A conversão distribui esse incremento no intervalo, mantendo a área nominal da curva. Ela gera um rascunho contínuo em `timeline`, com ganho 1, e recusa tabelas inválidas, curvas acima de 10 segundos ou taxas além dos limites.

 Tiro único exige **Por passo** e valores inteiros. Intervalo entre cliques é uma proteção para tiro único, não um gerador de disparos.

## Importar, exportar e referências

**Exportar INI** salva o preset selecionado com contexto, origem, ganho e curva. **Importar INI** aceita bibliotecas no esquema 1. IDs repetidos recebem uma nova identidade; nenhum preset existente é sobrescrito pela importação. Arquivos inválidos são rejeitados antes da gravação. Configurações podem conter informações pessoais digitadas pelo usuário; revise antes de compartilhar.

A aba **Referências SCHOOL** contém 26 armas e três posturas. A conversão pede intervalo assumido, escala e duração, mostra a curva como rascunho e registra as hipóteses. O campo de escala começa vazio para exigir uma escolha explícita: 1 significa amplitude de referência, 0,1 significa 10%. A duração inicial acompanha o limite local da rajada. Os 78 presets já distribuídos permanecem como referências de 10%/16 ms/3 s, com essas condições visíveis no painel; não são atualizados silenciosamente. Ela não sobrescreve sua calibração. Consulte o [modelo e a licença](../references/school/README.md).

## Atalhos e ponto central

- Ctrl+Alt+A–Z ou Ctrl+Alt+1–9: associação editável por perfil; **D** é reservada.
- Ctrl+Alt+D: parada global, mesmo fora do jogo.
- Ctrl+. / Ctrl+,: próximo/anterior preset da mesma arma e modo de disparo; seleciona e ativa.
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
| `selection.local.ini` / `.bak` | Última seleção e preferência por arma/modo |

Esses arquivos não são versionados. Feche o aplicativo antes de restaurar uma cópia `.bak`. Copie o backup sobre o arquivo correspondente e reabra. A validação continua ativa; uma versão de esquema desconhecida não é reinterpretada silenciosamente.

As sessões incluem snapshots da biblioteca na inicialização e a cada gravação. As evidências descrevem o software e o envio ao Windows. A qualidade do spray exige ensaios comparáveis com as condições registradas.
