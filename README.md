# AudioProbe — prova técnica descartável

Experimento local para investigar volume por processo com Core Audio taps, sem driver. **Não é o produto final e não foi compilado nem executado em macOS neste ambiente Linux.** Sonoma 14.2+, Sequoia e Tahoe são alvos de investigação, não compatibilidade já comprovada.

## Rodar no Mac

Requer Xcode Command Line Tools (`xcode-select --install`). No Terminal, dentro desta pasta:

```sh
bash scripts/build.sh
open build/AudioProbe.app
```

O ícone de alto-falante aparece na barra de menus. A assinatura local ad hoc serve para desenvolvimento; não é uma distribuição assinada/notarizada. O macOS pode pedir permissão de gravação de áudio do sistema: o tap recebe áudio para processá-lo localmente, sem gravar arquivos ou usar rede. Se negar, pare o teste; revise a permissão em Ajustes do Sistema > Privacidade e Segurança e reabra o app.

1. Escolha os alto-falantes internos como saída. Comece com o volume geral baixo.
2. Toque Spotify e um vídeo no navegador simultaneamente.
3. Abra o painel, clique Refresh e selecione o processo do Spotify.
4. Clique Start test e autorize a captura quando solicitado.
5. Compare 100%, 50% e 0%. Apenas o processo escolhido deve mudar.
6. Clique Stop / restore. O som original deve voltar.
7. Repita com navegador e Discord, mantendo outra fonte tocando para comparação.
8. Teste negar permissão e encerrar o app; confirme que o som original volta.

**Se ficar sem som, clique Stop / restore ou encerre AudioProbe.** Não interprete um retorno bem-sucedido da API como evidência de áudio funcionando. Não troque dispositivos durante uma rota ativa: pare primeiro. Não teste inicialmente durante uma chamada importante.

## Limites deliberados

- Um processo por vez, com atualização manual. Navegadores e Discord podem usar processos auxiliares; ainda não há agrupamento por aplicativo.
- A lista indica processos com saída em execução, não detecção de energia sonora: um processo que envia silêncio pode aparecer.
- A rota aceita apenas PCM Float32 e saídas sem buffers de entrada. Layouts diferentes podem resultar em silêncio; use Stop para restaurar.
- Sem suporte implementado para troca de saída, suspensão, reinício de processo, áudio protegido, persistência, múltiplas rotas, latência medida ou tratamento completo de falhas.
- O ganho é suavizado por amostra como aproximação experimental; sincronização multicanal e taxa de suavização precisam ser refinadas no produto.
- AudioProbe é um nome provisório. A licença do produto ainda será escolhida; esta publicação é uma prova técnica para avaliação.

## Registro da validação

Preencha para cada máquina/versão. Não marque aprovação sem escutar e comparar a outra fonte.

| Sistema / hardware | Compila | Permissão | Spotify isolado | Navegador isolado | Discord isolado | Stop restaura | Quit restaura |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Sonoma 14.2+ | Pendente | Pendente | Pendente | Pendente | Pendente | Pendente | Pendente |
| Sequoia 15 | Pendente | Pendente | Pendente | Pendente | Pendente | Pendente | Pendente |
| Tahoe 26 | Pendente | Pendente | Pendente | Pendente | Pendente | Pendente | Pendente |

Critério para seguir: captura autorizada com áudio real, ganho independente perceptível em 100/50/0%, outra fonte inalterada e restauração após Stop/Quit. Depois investigar agrupamento por app, saídas Bluetooth/USB e recuperação automática. Esta prova não valida ainda mostrar exclusivamente apps audivelmente ativos.

## Fontes

- [Apple: Capturing system audio with Core Audio taps](https://developer.apple.com/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps): captura por processo, mute, aggregate device, requisito 14.2 e permissão.
- [Apple: CATapMuteBehavior](https://developer.apple.com/documentation/coreaudio/catapmutebehavior).

A arquitetura experimental usa tap → aggregate device com saída física → callback de cópia com ganho. A documentação confirma as primitivas; o funcionamento desta composição precisa ser comprovado em hardware.
