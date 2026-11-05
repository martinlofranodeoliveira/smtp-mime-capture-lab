# Subconjunto de protocolo e recuperação — Português

A versão 0.1.0 é um capturador loopback de desenvolvimento, não hospedagem de e-mail. O [contrato](contract.md) define limites e APIs precisamente.

## Exemplo de transação

Cada linha abaixo representa uma linha de fio terminada por CRLF:

```text
EHLO synthetic.test
MAIL FROM:<fixture@example.test>
RCPT TO:<alice@example.test>
RCPT TO:<someone@outside.invalid>
DATA
```

Os destinatários recebem 250 e 550. DATA continua permitido: alice permanece aceita. Após 354, envie cabeçalhos ASCII, linha vazia, conteúdo e terminador de ponto único. A linha de corpo `..linha` no fio armazena `.linha`. O 250 final só ocorre após publicação. RSET depois de MAIL/RCPT responde 250; DATA passa a responder 503 até completar um novo envelope. Repetir os mesmos bytes produz outro identificador.

Existem apenas EHLO/HELO, MAIL FROM com SIZE opcional, RCPT TO, DATA, RSET, NOOP e QUIT. Não há DNS, envio externo, AUTH, TLS ou 8BITMIME. Endereços seguem o subconjunto ASCII dot-atom restrito; o domínio destinatário deve ser exatamente example.test minúsculo. `MAIL FROM:<>` é válido. A parte local preserva maiúsculas. Falhas de tempo, enquadramento ou limite de DATA encerram a sessão, sem drenagem ilimitada.

## Resultados após reinício

| Última operação concluída | Visibilidade após reiniciar |
| --- | --- |
| Sem estágio / transação rejeitada | Nenhuma entrega nova |
| Estágio gravado, antes do rename | Nenhuma entrega nova; órfão reconhecido removido |
| Diretório renomeado, antes do 250 final | Uma entrega nova; resultado do cliente incerto |
| Cliente observou o 250 final | Uma entrega confirmada |

Se o cliente repetir uma entrega incerta, dois IDs podem conter mensagens iguais. É a ambiguidade esperada de SMTP, não uma promessa de deduplicação. Ausência de 250 não significa ausência de entrega.

O reinício adquire posse exclusiva vitalícia antes da limpeza. Valida no máximo quatro estágios órfãos, contagem de entradas, marcador e arquivos reconhecidos, proprietário e tamanhos antes de remover qualquer um. Não apaga entradas desconhecidas. Marcador ausente, arquivo extra, proprietário estrangeiro, link simbólico, estado acima da cota ou sequência confirmada inválida impedem a inicialização. Preserve o diretório para análise local manual; nunca use um diretório com outros dados. Não há comando de reparo ou limpeza recursiva. Não edite/remova entregas confirmadas enquanto o capturador funciona.

As opções `--fault before-publish` e `--fault after-publish` são controles explícitos para testes locais. Um evento JSON sinaliza a pausa; os testes encerram o processo e reiniciam sem a opção. Esses pontos suspendem deliberadamente um checkpoint e não fazem parte da operação normal. A suíte verifica 0 entregas antes da publicação, 1 depois e 2 após repetição de resposta perdida.

Arquivos sincronizados e rename de diretório cobrem os cenários documentados de queda do processo em sistema de arquivos local. Não prometemos resistência a perda de energia, falha física, sistema de arquivos remoto, esgotamento de blocos ou entrega exatamente uma vez. Queda entre criar o diretório de estágio e escrever seu marcador pode exigir revisão manual em vez de limpeza automática.
