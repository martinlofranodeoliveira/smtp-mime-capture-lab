# SMTP MIME Capture Lab

Versão de desenvolvimento **0.1.0**, por [Lofrano Tecnologia](https://lofranotecnologia.com.br). Capturador SMTP exclusivamente local para testes de integração offline, com inspeção MIME pelo gem `mail` em subprocesso limitado. Não envia mensagens externas, não resolve domínios de destinatários e não extrai anexos. Todos os exemplos são sintéticos; não há dependência de modelo/API em execução.

[English](README.md) · [Contrato preciso](docs/contract.md) · [Projeto](docs/design.md) · [Recuperação em português](docs/recovery.pt-BR.md)

## Instalar, testar e demonstrar

Use Ruby 3.4, Bundler e uma conta Linux sem privilégios. A instalação obtém gems do RubyGems; os cenários posteriores são offline.

```sh
bundle install
bundle exec ruby test/all_test.rb
bundle exec ruby bin/demo.rb
bundle exec ruby bin/demo.rb --json
```

A demonstração verifica os resultados: inicia capturador, cliente independente `net-smtp` e inspetor em processos próprios, em diretório temporário privado. O cenário tem prazo de 20 segundos, saída limitada e encerramento/coleta dos processos. Somente esse diretório temporário é removido. Date e Message-ID são valores explícitos da fixture, não relógios atuais.

Saída humana:

```text
SMTP MIME Capture Lab 0.1.0 (development)
delivery: 000001
recipients: alice@example.test, bob@example.test
text: "Olá\n.linha\n"
attachment: sample.bin (4 bytes, hex 00010203)
checks: passed
```

O modo JSON também fornece envelope, texto, hexadecimal dos anexos, tamanhos, SHA-256 e diagnósticos do parser. Não contém campos variáveis de horário.

## Uso local persistente

Escolha um caminho novo sob um diretório pai privado e confiável:

```sh
bundle exec ruby bin/sink.rb --mailbox ./synthetic-mailbox --port 2525
```

A primeira linha é um evento JSON `ready`. `--port 0` solicita porta escolhida pelo sistema. Não existe opção de endereço: somente o literal `127.0.0.1`. Encerre com Ctrl-C. Em outro terminal:

```sh
bundle exec ruby bin/send_fixture.rb --port 2525
bundle exec ruby bin/inspect.rb --mailbox ./synthetic-mailbox
bundle exec ruby bin/inspect.rb --mailbox ./synthetic-mailbox --id 000001
bundle exec ruby bin/inspect.rb --mailbox ./synthetic-mailbox --id 000001 --json
```

Cada envio idêntico gera uma entrega distinta. Nomes de anexos são dados, nunca caminhos para extração. A saída humana escapa nomes e texto como strings JSON.

API Ruby:

```ruby
require_relative 'lib/capture_lab'
reader = CaptureLab::MailboxReader.new('./synthetic-mailbox')
reader.list.each do |item|
  puts JSON.generate(CaptureLab::Inspector.delivery('./synthetic-mailbox', item.fetch('id')))
end
```

`reader.read('000001')` inclui os bytes brutos limitados. A inspeção retorna sucesso completo ou erro, sem esconder anexo rejeitado em resultado parcial.

## Subconjunto e decisões

Comandos: EHLO/HELO, MAIL FROM, RCPT TO, DATA, RSET, NOOP e QUIT. Somente SIZE é anunciado. É obrigatório CRLF, com remoção de um ponto inicial em DATA. São aceitos apenas destinatários com domínio literal minúsculo `example.test`; não há DNS. O caminho reverso vazio `<>` é permitido. A parte local ASCII preserva maiúsculas; os domínios devem ser minúsculos. Endereços entre aspas e literais IP não são suportados.

RSET limpa apenas a transação atual. Rejeitar um destinatário não apaga os já aceitos. DATA exige remetente e pelo menos um destinatário aceito. Um rename de diretório no mesmo sistema de arquivos publica mensagem e envelope juntos, sob lock exclusivo, antes do 250 final. A posse exclusiva durante toda a vida do capturador impede dois escritores. Reservas incluem estágios concorrentes.

Limites: 4 sessões; 16 comandos RCPT aceitos; DATA bruto após remoção de pontos até 256 KiB; 100 entregas confirmadas ou reservadas; 16 MiB de conteúdo lógico confirmado mais estágios. Há limites separados de linhas, cabeçalhos, bytes de fio, bytes MIME decodificados, partes, profundidade, saída e tempo. A inspeção permite texto UTF-8/US-ASCII e folhas 7bit/base64/quoted-printable validadas. Mensagens aninhadas e cabeçalhos encoded-word/parâmetros estendidos de nome não integram o subconjunto.

O parser `mail` pode trabalhar antes das guardas de travessia: não prometemos profundidade limitada antes do parse. O processo isolado recebe limites de memória/CPU onde disponíveis e prazo absoluto; a travessia direta é iterativa.

## Limitações e recuperação

Não é servidor de produção: não há AUTH, TLS, 8BITMIME, relay, antivírus, extração de arquivos, telemetria ou certificação de padrões. Aceitação SMTP guarda MIME opaco; inspeção posterior pode falhar. Reiniciar limpa no máximo quatro estágios órfãos reconhecidos, sem apagar caminhos estrangeiros. Desconexão após publicação e antes do 250 significa entrega incerta; uma repetição pode duplicar. A garantia documentada cobre cenários de queda do processo, não perda de energia ou entrega exatamente uma vez.

MIT, copyright 2026 Lofrano Tecnologia. Repositório: [martinlofranodeoliveira/smtp-mime-capture-lab](https://github.com/martinlofranodeoliveira/smtp-mime-capture-lab). Contato geral: [site oficial](https://lofranotecnologia.com.br). Relatos de segurança: [canal privado do GitHub](https://github.com/martinlofranodeoliveira/smtp-mime-capture-lab/security/advisories/new).
