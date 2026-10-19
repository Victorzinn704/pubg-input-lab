# Contribuição

1. Prepare o runtime e os arquivos locais conforme o README.
2. Crie uma branch para uma alteração com escopo definido.
3. Mantenha lógica de estado independente das APIs do Windows. Novos perfis e letras devem ser dados de configuração, não casos novos no controlador.
4. Cubra alterações de estado com testes determinísticos. Testes de interface usam somente janelas sintéticas e nunca registram hooks nem enviam entrada ao jogo.
5. Execute `Validar.ps1`. Documente o que foi validado e os limites da evidência.
6. Abra um pull request com problema, comportamento resultante e validação.

Não inclua calibrações pessoais, logs reais, dumps, credenciais ou executáveis no commit. Atualizações de dependências exigem versão e checksum conferidos no fornecedor oficial. Alterações de atalhos devem atualizar o arquivo de exemplo, o painel e o README.

Preserve a parada global, a instância única, os controles de foco, a invalidação de movimentos antigos e o prazo original da sessão. Não use sucesso de `SendInput` como prova de que o jogo recebeu ou aplicou o movimento.
