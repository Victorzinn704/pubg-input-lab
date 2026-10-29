# Avaliação técnica — 1.5.0

Revisão de código e documentação em 29/10/2026. Esta comparação não executou programas externos nem mediu o spray no jogo. As implementações desta versão são próprias; não incorporam código dos projetos abaixo.

| Referência examinada | Conceito útil | Decisão |
| --- | --- | --- |
| [Soldier76, revisão 1b5a2bc](https://github.com/kiccer/Soldier76/blob/1b5a2bc630361b7954fbc7805c1ac94e587e4a94/Soldier76.lua) | Separar curva por disparo, tempo decorrido e contexto | Adotar conversão explícita por disparo e integração temporal opcional, sem transportar coeficientes não medidos. Código GPL não copiado. |
| [hqzqaq, calibrador na revisão 191c6ad](https://github.com/hqzqaq/pubg-gun-control/blob/191c6ad3d6a9688137e9f48f7722bf4f73ed2d3d/src/pubg_gun_control/recoil_calibrator.py) | Medir erro residual antes de afirmar eficácia | Manter separado o estado do programa e a eficácia observada. Captura/calibração automática fica fora desta entrega. |
| [Ryanshuai, modelo na revisão b05ba80](https://github.com/Ryanshuai/pubg_derecoil/blob/b05ba809e146da67d7e79941b61a72c6404769ed/MODEL.md) | Unidades explícitas, latência, validade das amostras e contexto completo | Mostrar duração efetiva, origem e condições ainda não registradas. Não importar constantes dependentes de hardware. |
| [UniversalAntiRecoil, revisão caa095e](https://github.com/4ug3r/Universal-Anti-Recoil-Script/blob/caa095e14dc7b1b0da6b54275636374d0ae62dd1/UniversalAntiRecoil.ahk) | Controles simples | Não adotar o movimento horizontal aleatório: ele não observa o erro a corrigir. |

O calibrador hqzqaq merece investigação adicional antes de reutilização: `cumulative_recoil` retorna zeros se não restarem sessões utilizáveis; o fluxo de rodadas pode interpretar RMS zero como convergência. A curva final também passa por transformação depois da última medição. São riscos inferidos da leitura do código, não falhas reproduzidas no jogo. Não foi identificado arquivo de licença em hqzqaq ou Ryanshuai nas revisões examinadas.

## Correções do próprio produto

- Uma seleção nominal de arma podia ativar uma curva vazia. O modo real agora recusa esse estado e a resolução de atalhos base procura uma variante compatível com movimento.
- Uma lista única misturava exemplos, armas e posturas. O painel passa a separar arma e variante; a biblioteca tem busca com índices independentes dos atalhos.
- A biblioteca SCHOOL é uma conversão de referência com escala 0,1, intervalo assumido 16 ms e duração 3 s. A interface agora mostra essas hipóteses e exige escala explícita para novas conversões. Os arquivos pessoais não são multiplicados nem substituídos.
- `timeline` mantém a área nominal sob pequenas variações do intervalo de amostragem. Os testes cobrem mudança de segmento, resíduos, perdas de foco, rejeição de atraso e amplitude, sem filas. Isso não comprova a curva adequada para uma arma.

## Validação e próximo limite

O conjunto local e o CI usam timestamps e botões sintéticos. A revisão visual usa janelas de teste e não instala hooks. Os logs de entrada descrevem tentativas e aceitação pelo Windows, não recepção pelo jogo.

Para demonstrar melhoria de spray ainda é necessário comparar ensaios repetidos na mesma arma, mira/zoom, postura e acessórios, com sensibilidade registrada e medida externa do erro. Amostras ausentes, perda do referencial ou movimentação manual não devem ser classificadas como erro zero. Nenhuma alegação de calibração automática é feita nesta versão.
