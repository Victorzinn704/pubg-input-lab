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
| `lib/LabPresets.ahk` | Esquema versionado, validação, persistência, importação e conversão de referências |
| `lib/LabPresetWorkbench.ahk` | Editor de contexto, segmentos, biblioteca e associações |
| `lib/LabCurvePreview.ahk` | Prévia nativa de curvas; sem entrada no sistema |
| `lib/LabReticle.ahk` | Ponto central opcional; geometria estável, sem foco ou cliques |
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

Reinicie o aplicativo depois de editar os arquivos externamente. O editor valida e aplica biblioteca/atalhos imediatamente, sempre desarmando primeiro. Não existe recarga automática de arquivo durante uma rajada. Os comandos de ajuste do painel persistem pelo fluxo de gravação validado.

## Biblioteca contextual

`presets.local.ini` usa esquema 1. O parser rejeita seções/chaves duplicadas, referências desconhecidas de formato e valores fora dos limites. Gravações são preparadas em arquivo temporário no mesmo diretório, validadas novamente, mantêm `.bak` e substituem o destino após sucesso. As bibliotecas importadas nunca sobrescrevem IDs existentes: colisões geram novas identidades.

Os perfis base são carregados com suas calibrações 1.3.0 e depois combinados com a biblioteca. Salvar um perfil base no editor cria uma cópia; não migra ou reescreve os arquivos antigos. Contexto é parte do preset, não uma heurística de reconhecimento. Cada combinação pode ter sua própria curva e ganho.

Trocas de biblioteca preservam o início da sessão e invalidam a geração anterior. Callbacks de atalhos resolvem nomes no catálogo atual, evitando índices obsoletos após exclusões. Reconfigurar atalhos valida todos os nomes/teclas antes de registrar; falhas restauram as associações anteriores. A parada global não participa dessa substituição.

Excluir um preset ainda associado é recusado. O painel simples recusa converter uma curva composta em constante. F5 persiste um preset da biblioteca pelo mesmo esquema, preservando curva e contexto. Snapshots de biblioteca acompanham os eventos locais de gravação.

`LabCyclePresetIndex` resolve a próxima/anterior variante por identidade normalizada da arma e modo de disparo. É uma função pura; o controlador delega a mudança à mesma transição de ativação já validada. Não usa reconhecimento de tela nem gera uma fila de entrada. Catálogos sem variante são operações vazias. `presets.example.ini` é um produto determinístico dos dados SCHOOL; a instalação incremental usa IDs estáveis e a mesma exclusão mútua do runtime.

O arquivo de calibrações é separado dos exemplos versionados. Uma atualização de código preserva os arquivos locais. Uma instalação nova usa simulação e não importa os ajustes de outro usuário.

## Limites de arquitetura

AutoHotkey e os temporizadores do Windows não oferecem tempo real rígido. A aplicação mede atraso e aplica limites; uma frequência configurada não garante a mesma frequência observada. Os perfis não identificam arma, mira, acessórios ou inimigos automaticamente. Os logs são do laboratório, não telemetria interna nem evidência de detecção do PUBG.

Uma separação futura de toda a interface e do adaptador de entrada deve ser motivada por manutenção ou medições. A máquina de estados, o parser de atalhos, o armazenamento e o indicador já têm fronteiras próprias; criar serviços de rede ou adicionar IA não resolve calibração ausente.
