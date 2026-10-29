# Referências SCHOOL

Dados de [FDCaffeine/School-Recoil-Control](https://github.com/FDCaffeine/School-Recoil-Control), revisão fixa `4c2d56a276a9592d69102ee842c8f1b52d742abf` (2025-05-23).

`school_presets.ini` é uma cópia textual normalizada em UTF-8 dos 26 presets originais. A licença MIT e o aviso de copyright de FDCaffeine estão preservados em [LICENSE](LICENSE). Nenhum executável ou código de despacho de entrada do projeto foi incorporado.

Esses números não são medições do PUBG Input Lab. A aba **Referências SCHOOL** converte uma arma/postura em rascunho, sem alterar perfis existentes. É preciso salvar o rascunho e escolher sua associação de atalho para utilizá-lo.

Desde 1.4.1, `presets.example.ini` distribui 78 conversões com IDs estáveis e crédito **SCHOOL (FDCaffeine)**: 26 armas × 3 posturas, usando 16 ms assumidos, escala 0,1 e 3000 ms. O arquivo é reproduzido por `scripts/Install-SchoolPresets.ahk --generate-example` e verificado contra a referência pelos testes. `--install` acrescenta somente IDs ausentes na biblioteca pessoal e exige o aplicativo fechado.

## Modelo da conversão

Para o pulso `n`, iniciando em 1, o modelo publicado calcula `min(1000, round(base + n * (strength / 1000)^2))`. A base vem de `normal`, `ctrl` ou `prone`. O importador aplica uma escala explícita ao resultado e agrupa valores iguais em segmentos temporais. O motor do laboratório mantém suas próprias regras de foco, atraso, quantização e limites.

O intervalo do loop é uma hipótese informada pelo usuário, entre 10 e 1000 ms. O `delay` original é preservado como informação de origem, mas não é tratado como intervalo efetivamente observado. Os valores iniciais de **16 ms** e **0,1 de escala** são parâmetros conservadores de demonstração, não calibrações. A referência de 1 ms não garante pulsos de 1 ms: consulte a [documentação do AutoHotkey](https://www.autohotkey.com/docs/v2/lib/Sleep.htm).

A curva resultante permanece `external_unvalidated`. Valores acima de `MaxStep` são rejeitados, sem truncamento silencioso. Não se aplica o boost global do SCHOOL: cada combinação usa seu ganho explícito, validado e salvo. O comportamento real depende da configuração e precisa de avaliação separada.
