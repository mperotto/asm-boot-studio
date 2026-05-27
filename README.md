# ASM Boot Studio

Ambiente web para escrever bootloaders NASM `bin`, montar com NASM em WebAssembly no navegador e executar localmente com `v86`.

## Autoria

Concepcao do projeto:

- MSc. Marcelo Antonio Perotto
- Professor de Ciencia da Computacao
- `mperotto@gmail.com`

Os creditos tecnicos dos projetos open source usados pelo app aparecem mais abaixo e tambem na propria interface.

Idiomas da interface:

- `pt-BR`
- `en`
- `zh-CN`

## Arquivos principais

- `asm-boot-studio.html`: interface, editor e integracao com `v86`
- `nasm-worker.js`: worker que roda o NASM em WebAssembly
- `src/codemirror-asm.js`: fonte do editor CodeMirror com sintaxe e autocomplete NASM/x86
- `vendor/codemirror/asm-editor.js`: bundle local do editor usado pelo navegador
- `vendor/nasm-wasm/`: artefatos gerados do NASM (`nasm.js` e `nasm.wasm`)
- `vendor/v86/`: runtime do `v86` e BIOS locais (`libv86.js`, `v86.wasm`, `seabios.bin`, `vgabios.bin`)
- `server.mjs`: servidor estatico simples para desenvolvimento local
- `scripts/build-nasm-wasm.sh`: regenera o NASM WASM a partir do release oficial

## Rodar localmente

Instale Node.js 20+.

```bash
npm start
```

Abra `http://localhost:3000`.

O `server.mjs` agora serve apenas os arquivos estaticos. Nao existe dependencia de NASM instalado no sistema para usar o app.

## Editor

O editor usa CodeMirror 6 empacotado localmente em `vendor/codemirror/asm-editor.js`.

Recursos atuais:

- destaque de sintaxe para NASM/x86
- numeros de linha
- busca no codigo
- historico de desfazer/refazer
- autocomplete local para instrucoes, registradores, diretivas e chamadas BIOS comuns
- snippets didaticos, como boot sector, rotina de print e leitura de setor

O autocomplete nao usa IA nem nuvem. Tudo roda no navegador.

Para regenerar o bundle do editor depois de alterar `src/codemirror-asm.js`:

```bash
npm run build:editor
```

## Creditos

Projetos e ferramentas utilizados neste app:

- NASM: https://www.nasm.us/
- v86: https://github.com/copy/v86
- CodeMirror 6: https://codemirror.net/
- SeaBIOS: https://seabios.org/SeaBIOS
- Emscripten: https://emscripten.org/
- esbuild: https://esbuild.github.io/

## Arquivos locais e projetos salvos

O editor permite:

- abrir um arquivo `.asm` da maquina do usuario
- baixar o fonte atual como arquivo `.asm`
- salvar projetos no armazenamento local do navegador
- listar os projetos salvos
- carregar ou excluir um projeto salvo

Nada disso usa nuvem ou backend. Os projetos ficam apenas no navegador atual, neste dispositivo.

Os projetos e o rascunho atual sao guardados em `IndexedDB`, que e mais adequado do que `localStorage` para varios trabalhos e codigos maiores.

Fluxo rapido:

1. Use o menu `Arquivo` / `File` / `文件`.
2. Use `Abrir arquivo` para carregar um `.asm` local, se quiser.
3. Use `Salvar fonte .asm` se quiser baixar o codigo atual para a maquina.
4. Edite o codigo.
5. Diga um nome no campo de projeto.
6. Clique em `Salvar local`.
7. Use `Salvar como` se quiser duplicar o projeto aberto com outro nome.
8. Depois use a lista de salvos para `Carregar` ou `Excluir`.

O rascunho atual tambem fica guardado localmente no navegador.

## Exemplo didatico em dois estagios

O exemplo `Dois estagios` mostra a ideia basica de um sistema operacional real:

- a BIOS carrega somente o primeiro setor do disco em `0000:7C00`
- esse primeiro setor e pequeno, entao ele age como `stage 1`
- o `stage 1` usa a BIOS (`int 13h`) para ler o setor 2 do disco
- o setor 2 e carregado em `0000:8000`
- depois o `stage 1` salta para `0000:8000`, onde comeca o `stage 2`

Nesse projeto, o NASM gera uma imagem de 1024 bytes para esse exemplo: 512 bytes do setor de boot e 512 bytes do segundo setor. O `v86` recebe essa imagem dentro de um floppy virtual completo para conseguir simular a leitura dos proximos setores.

## Regerar o NASM WASM

O projeto em si nao usa Docker.

Docker aparece apenas no script de manutencao que recompila o NASM em WebAssembly. Esse script baixa o tarball oficial do NASM e usa uma imagem com Emscripten para gerar os artefatos:

```bash
npm run build:nasm-wasm
```

Os artefatos finais vao para:

- `vendor/nasm-wasm/nasm.js`
- `vendor/nasm-wasm/nasm.wasm`

## Publicar sem backend

Como tudo roda no navegador, o deploy pode ser totalmente estatico:

- GitHub Pages
- Cloudflare Pages
- Netlify

O arquivo `.nojekyll` ja foi incluido para GitHub Pages servir a pasta `vendor/` sem interferencia.

### Cloudflare Pages

Este projeto esta pronto para ser publicado no Cloudflare Pages como site estatico.

Arquivos importantes para isso:

- `index.html`: entrada padrao da raiz do site
- `asm-boot-studio.html`: aplicacao principal
- `vendor/`: NASM WASM, CodeMirror, `v86` e BIOS locais

Passo a passo:

1. Envie o projeto para um repositorio no GitHub.
2. Entre em Cloudflare Pages.
3. Clique em `Create application` e depois `Pages`.
4. Conecte o repositorio.
5. Na configuracao do build, use:

```text
Framework preset: None
Build command: <vazio>
Build output directory: .
Root directory: /
```

6. Faça o deploy.

Depois disso, a raiz do dominio ja abrira o app normalmente por causa do `index.html`.

Observacoes:

- nao ha backend para subir
- nao ha dependencia de Docker
- o app carrega os arquivos `.wasm`, BIOS e scripts diretamente como arquivos estaticos
- os projetos dos alunos continuam sendo salvos localmente no navegador de cada um

## Gerar e gravar uma imagem bootavel

Depois de montar o codigo no navegador, use o botao `Baixar .img`. Ele baixa a ultima imagem gerada como `boot.img`.

Observacao:

- os exemplos simples geram um boot sector cru de 512 bytes
- o exemplo `Dois estagios` gera 1024 bytes, porque inclui o segundo setor
- gravar essa imagem sobrescreve o inicio do pendrive
- escolha o dispositivo correto com muito cuidado

### Linux

1. Gere a imagem no app e baixe `boot.img`.
2. Descubra o dispositivo do pendrive com `lsblk`.
3. Grave a imagem:

```bash
sudo dd if=boot.img of=/dev/sdX bs=512 conv=fsync status=progress
```

Troque `/dev/sdX` pelo dispositivo real do pendrive, como `/dev/sdb`.

4. Ejete com seguranca:

```bash
sync
udisksctl power-off -b /dev/sdX
```

### macOS

1. Gere a imagem no app e baixe `boot.img`.
2. Descubra o disco com:

```bash
diskutil list
```

3. Desmonte o pendrive:

```bash
diskutil unmountDisk /dev/diskN
```

4. Grave a imagem:

```bash
sudo dd if=boot.img of=/dev/rdiskN bs=512
```

Use `rdiskN` para gravacao mais rapida e troque `N` pelo numero correto.

5. Ejete:

```bash
diskutil eject /dev/diskN
```

### Windows

1. Gere a imagem no app e baixe `boot.img`.
2. Descubra a letra ou o disco do pendrive.
3. Grave a imagem com uma ferramenta de escrita bruta, como:

- Rufus
- balenaEtcher

No Rufus:

1. Abra o programa.
2. Selecione o pendrive.
3. Escolha a opcao para usar uma imagem e selecione `boot.img`.
4. Inicie a gravacao.

No balenaEtcher:

1. Selecione `Flash from file`.
2. Escolha `boot.img`.
3. Selecione o pendrive.
4. Clique em `Flash`.

Se preferir linha de comando no Windows, tambem da para usar WSL e seguir o fluxo de Linux, desde que o pendrive esteja acessivel corretamente no subsistema.
