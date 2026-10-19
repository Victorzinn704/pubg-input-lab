# Arquitetura

## Responsabilidades

| Componente | Responsabilidade |
| --- | --- |
| `RecoilLab.ahk` | Composição, interface, ciclo de atualização, comandos e guarda final do envio |
| `lib/LabHotkeys.ahk` | Leitura e validação dos atalhos; transição de perfil sem dependência da interface |
| `lib/RecoilEngine.ahk` | Estados, tempo, rajadas, limites e eventos de movimento; sem APIs do sistema operacional |
| `lib/LabConfig.ahk` | Perfis, calibrações, validação numérica e gravação por arquivo temporário |
| `lib/TrialLogger.ahk` | Eventos, snapshots, relógio monotônico e integridade das evidências |
| `lib/LabInstance.ahk` | Exclusão mútua entre instalações e comunicação com o painel existente |
| `lib/LabStatusOverlay.ahk` | Indicador, estabilidade da geometria e visibilidade |
| `Analisar-Sessao.ps1` | Análise posterior dos eventos; independente do envio |

## Invariantes de execução

- Existe somente uma instância do aplicativo e um motor ativo.
- A troca de perfil invalida a geração anterior. Um evento produzido antes da troca não pode ser enviado depois dela.
- Ativar novamente a mesma arma ligada não reinicia a rajada, o ganho em uso ou o prazo de sessão.
- Rearmar a mesma arma depois de ajustar preserva o ganho aplicado, mesmo antes de salvar. O ganho salvo é carregado ao trocar para outra arma.
- A troca carrega o ganho salvo do novo perfil e preserva o início da sessão e a sequência de rajadas.
- Ctrl+Alt+D cancela o estado ativo globalmente. A seleção de arma só é registrada no contexto da janela alvo.
- Ativação e retomada após perda de foco exigem soltura do disparo. Não há geração de cliques de tiro.
- A verificação imediatamente anterior ao envio confere geração, prazo, foco e botões físicos.
- Simulação produz registros sem chamar a função de envio.
- A tarja nunca participa do cálculo de movimento. Mudanças transitórias de janela ocultam a tarja.

## Extensão por configuração

Um novo perfil usa uma seção `[Profile:Nome]` em `profiles.ini`, com modo, intervalo e segmentos. Adicione `Nome=Letra` em `[Weapons]` de `hotkeys.ini`. O parser rejeita referências desconhecidas e letras repetidas. D permanece reservada.

Reinicie o aplicativo depois de editar os arquivos de configuração. Não existe recarga automática de arquivo durante uma rajada. Os comandos de ajuste do painel persistem pelo fluxo de gravação validado.

O arquivo de calibrações é separado dos exemplos versionados. Uma atualização de código preserva os arquivos locais. Uma instalação nova usa simulação e não importa os ajustes de outro usuário.

## Limites de arquitetura

AutoHotkey e os temporizadores do Windows não oferecem tempo real rígido. A aplicação mede atraso e aplica limites; uma frequência configurada não garante a mesma frequência observada. Os perfis não identificam arma, mira, acessórios ou inimigos automaticamente. Os logs são do laboratório, não telemetria interna nem evidência de detecção do PUBG.

Uma separação futura de toda a interface e do adaptador de entrada deve ser motivada por manutenção ou medições. A máquina de estados, o parser de atalhos, o armazenamento e o indicador já têm fronteiras próprias; criar serviços de rede ou adicionar IA não resolve calibração ausente.
