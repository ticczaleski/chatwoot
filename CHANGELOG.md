# Changelog

Todas as alterações notáveis no fork **`ticczaleski/chatwoot`** (WhatsApp Web Edition) serão documentadas neste arquivo.

O formato é baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/),
e este projeto adere ao [Versionamento Semântico](https://semver.org/lang/pt-BR/) com o sufixo `-wa`.

---

## [4.19.0-wa.1] - 2026-09-19

### ✨ Adicionado (Added)
- **Reações do WhatsApp (Evolution API), atrás de capability por inbox:**
  - Nova tabela independente `message_reactions` (sem enum novo em `Message`, sem coluna nova em `messages`): uma reação por `(mensagem, actor)`, substituição de emoji na mesma linha, cascata de exclusão com a mensagem-pai. Nunca cria uma mensagem de chat nem altera contagem de mensagens, não lidas, `last_activity_at`, SLA ou dispara automações de `message_created`.
  - `PUT /api/v1/accounts/:account_id/conversations/:conversation_id/messages/:id/reaction` — emoji vazio remove a reação. Reações originadas pelo provider (`message_type: 'incoming'`) são atribuídas ao contato da conversa e exigem a capability `reactions` no inbox.
  - Eventos aditivos `message_reaction_created/updated/deleted` via webhook (para a Evolution, condicionado à capability `reactions`) e via ActionCable (para o dashboard, sempre que há reação em qualquer inbox).
  - Controles de reação no dashboard Web: gatilho por hover/foco/toque-longo com os 6 emojis padrão do WhatsApp, pills agregadas abaixo da mensagem com atualização otimista e reconciliação (sem duplicar pill mesmo se o tempo real chegar antes da resposta HTTP).
  - Ponte bidirecional com a Evolution API: reação do agente é enviada ao WhatsApp via `reactionMessage`; reação do contato no WhatsApp é aplicada como reação no Chatwoot (nunca mais como mensagem de texto solta com o emoji como conteúdo).
- **Contrato de capabilities por inbox da Evolution:** `Channel::Api#evolution?` e `#provider_capability?(nome)`, lidos de `additional_attributes.provider`/`provider_capabilities`, validados no modelo (rejeita provider fora da allowlist ou capability desconhecida, sem coerção silenciosa). Habilita `delivery_status`, `quoted_reply` e `reactions` de forma independente por inbox.
- **Registro de IDs externos para respostas citadas:** `PATCH .../messages/:id` agora aceita `source_id` (só inboxes API, único por inbox, validado por índice único parcial), permitindo que a Evolution registre a chave do WhatsApp de uma mensagem enviada pelo agente — antes disso, citar uma mensagem de saída pelo lado do WhatsApp nunca resolvia o pai.

### 🐛 Corrigido (Fixed)
- **Papel de parede opaco (substitui o ajuste de opacidade da 4.18.0-wa.5):** o `wa-chat-bg.png` era uma imagem preta opaca; qualquer ajuste de `opacity`/`invert` sobre ela mistura o fundo preto junto com o desenho. Trocado por SVGs transparentes (`wa-doodle.svg`/`wa-doodle-dark.svg`) com a opacidade já embutida nos próprios traços — resolve definitivamente o problema nos dois temas sem depender de ajuste fino de opacidade em runtime.
- **Envio duplicado em reentrega de webhook (Evolution API):** removido um `sleep` cego de 500ms que mascarava (sem corrigir) uma condição de corrida a custo de latência em todo webhook. Adicionada uma claim atômica de idempotência por `(instância, ID da mensagem no Chatwoot, operação)`, evitando reenviar a mesma mensagem ao WhatsApp em caso de reentrega.
- **Falha de envio virava nota privada em vez de marcar a mensagem como falha:** substituído por uma chamada ao endpoint de atualização de status que já existe no Chatwoot (`status: failed`, `external_error`), mantendo a mensagem original re-tentável em vez de criar uma segunda mensagem solta na conversa.

Ver `docs/evolution-api-compatibility.md` para a matriz de versões, o modelo de capabilities, os checklists de verificação manual (matriz de mensagens ponta a ponta, smoke test mobile, carga/ordenação) e o procedimento de habilitação em estágios e rollback.

---

## [4.18.0-wa.5] - 2026-09-18

### 🐛 Corrigido (Fixed)
- **Papel de parede invisível em modo claro e escuro (regressão da 4.18.0-wa.3):**
  - Na correção anterior, a opacidade do doodle em modo escuro foi reduzida para `8%` visando imitar o contraste discreto do WhatsApp Web real. Como o asset usado (`wa-chat-bg.png`) é um PNG **opaco** (não um SVG transparente), aplicar `opacity` de CSS sobre ele mistura a imagem inteira com a cor de fundo — a 8%, a diferença entre o traço do doodle e o fundo quase preto cai para ~6/255, imperceptível na prática.
  - Ajustado para `30%` em ambos os temas (antes: `35%` claro / `8%` escuro), valor que mantém contraste visível sem repetir o excesso de opacidade (100%) da implementação original.
  - Pesquisado como referência o repositório `Luizcc87/wacrm-multi-ling`, que resolve isso de forma mais robusta com um SVG transparente com opacidade já calibrada no próprio traço (`stroke-opacity`), evitando por completo a necessidade de ajustar `opacity`/`filter` em runtime — fica registrado como possível melhoria futura (trocar o PNG opaco por um SVG com fundo transparente).

---

## [4.18.0-wa.4] - 2026-09-18

### 🐛 Corrigido (Fixed)
- **Rolagem da conversa quebrada (regressão da 4.18.0-wa.3):**
  - A correção do papel de parede (4.18.0-wa.3) passou a controlar a altura do `<ul>` da lista de mensagens via `absolute inset-0` (aplicado pelo componente pai), mas o próprio `<ul>` ainda tinha a classe `relative` fixada em `MessageList.vue` — como as duas definem `position` no mesmo elemento, o Tailwind aplicava `relative` por cima de `absolute` (ordem das utilities no CSS gerado, não a ordem no atributo `class`), fazendo o `<ul>` perder a altura/posicionamento que a rolagem interna dependia. A barra de rolagem sumia e não era possível rolar a conversa.
  - Corrigido removendo o `relative` redundante de `MessageList.vue` (não é mais necessário ali — o papel de parede que precisava dele já foi movido para o wrapper estático na 4.18.0-wa.3).

---

## [4.18.0-wa.3] - 2026-09-18

### 🐛 Corrigido (Fixed)
- **Caixa de resposta colapsada (Evolution API / API Inboxes):**
  - Substituído o hack de CSS customizado (`min-height` fixo em `.reply-box`/`.reply-box__top`, fora do padrão Tailwind-only do projeto) por `shrink-0` no rodapé de resposta em `MessagesView.vue` e `ReplyBox.vue`, garantindo que o elemento mantenha sua altura natural de conteúdo e não seja espremido pelo item `flex-grow` (lista de mensagens).
- **Papel de parede piscando/sumindo em modo escuro:**
  - O `::before` decorativo do papel de parede vivia DENTRO do `<ul>` que é o próprio contêiner com rolagem (`overflow-y-auto`) da lista de mensagens. Como elementos posicionados de forma absoluta dentro de um contêiner com rolagem rolam junto com o conteúdo (não ficam fixos na tela), o papel de parede desaparecia conforme o atendente rolava a conversa, deixando só a cor de fundo sólida.
  - Corrigido movendo o papel de parede (cor de fundo + `::before` com o doodle) para um `<div>` wrapper estático (sem rolagem, `overflow-hidden`) que envolve o `<MessageList>`; a lista de mensagens agora rola de forma independente (`absolute inset-0 overflow-y-auto`) por cima do papel de parede, que permanece fixo — mesmo comportamento visual do WhatsApp Web real.
  - Opacidade do papel de parede em modo escuro reduzida de `100%` para `8%`, alinhada ao padrão real do WhatsApp Web (contraste suave/discreto, não um padrão em opacidade máxima).

---

## [4.18.0-wa.2] - 2026-09-18

### 🐛 Corrigido (Fixed)
- **Desbloqueio da Caixa de Resposta (Evolution API / API Inboxes):**
  - Removido o bloqueio restritivo da janela de 24 horas (`isEditorDisabled`) para caixas de entrada de API (`isAPIInbox`) em `ReplyBox.vue`. Agora os atendentes conseguem digitar e enviar mensagens normalmente em canais pareados com Evolution API.
  - Eliminado o colapso visual de altura na caixa de digitação através de `min-height: 5.5rem` em `.reply-box` e `min-height: 2.5rem` em `.reply-box__top`.
  - Ocultado o banner de alerta vermelho de restrição de 24h em `MessagesView.vue` para canais de API (`!isAPIInbox`).
  - Corrigida a lógica de cálculo de tempo em `Conversations::MessageWindowService`: Quando uma conversa não possui mensagens de entrada ainda (`last_incoming_message.nil?`, ex: nova conversa iniciada pelo atendente), o sistema agora considera a data de criação da conversa (`@conversation.created_at + time`), evitando que o chat nasça bloqueado.
  - Adicionado suporte ao atributo `ignore_messaging_window` nos atributos adicionais do canal para permitir liberação total via configuração.
  - Atualizado teste unitário `ReplyBox.spec.js` para validar a isenção de inboxes de API da regra restritiva.

### ✨ Adicionado (Added)
- **Botão "Começar Nova Conversa" no Cabeçalho (WhatsApp Web Style):**
  - Adicionado botão de nova mensagem (`i-lucide-square-pen`) diretamente no topo da lista de conversas (`ChatListHeader.vue`), com o mesmo posicionamento e usabilidade do WhatsApp Web.
  - Integração com o popover oficial `ComposeConversation`, permitindo pesquisar contatos, criar novos e disparar mensagens para inboxes da Evolution API com facilidade.
  - Chave de internacionalização `CHAT_LIST.COMPOSE_CONVERSATION` adicionada aos arquivos de i18n.
- **Roteamento de Número de Telefone para Evolution API:**
  - Ajustado `Contacts::ContactableInboxesService` (`api_contactable_inbox`): Ao iniciar uma conversa em canal de API com um novo contato, o Chatwoot agora utiliza o telefone do contato (`@contact.phone_number.delete('+')`) como `source_id` em vez de gerar um UUID aleatório, garantindo que a Evolution API saiba exatamente para qual número enviar a mensagem.
- **Plano de Fundo Oficial do WhatsApp Web:**
  - Baixado e integrado o papel de parede com doodles oficial do WhatsApp Web (`public/dashboard/images/wa-chat-bg.png`).
  - Configurada camada de fundo via Tailwind CSS em `MessageList.vue` com pseudo-elementos `before:`:
    - **Tema Escuro:** Papel de parede dark oficial em fidelidade 100% (`opacity: 1`), com repetição contínua em proporção 420px.
    - **Tema Claro:** Inversão automática com opacidade calibrada a 35% sobre o fundo creme `#efeae2`.
    - Elementos e balões de mensagem preservados na camada superior (`z-10`).
  - Configuração do asset `wa-doodle` atualizada em `tailwind.config.js` e asset duplicado em `app/javascript/dashboard/assets/images/` para garantir resolução pelo Vite e Rails.
- **Otimização Extrema de Minutos do GitHub Actions:**
  - `Frontend Lint & Test` (`frontend-fe.yml`): Configurado para executar o Vitest seletivamente (`vitest related`) apenas sobre os arquivos `.js` / `.vue` modificados no commit, reduzindo o tempo de teste de ~6 minutos para menos de 30 segundos.
  - `Run Chatwoot CE spec` (`run_foss_spec.yml`): Desativada a execução automática em todo push/PR que consumia 25 minutos de runner; transformado em acionamento manual sob demanda (`workflow_dispatch`).
  - Removidos workflows redundantes do upstream (`test_docker_build.yml`, `logging_percentage_check.yml`, `run_mfa_spec.yml`) que queimavam mais de 30 minutos em builds duplicados.
- **Tags de Versão Automáticas nas Imagens Docker (`docker-build.yml`):**
  - O pipeline de build e push agora gera automaticamente tags de versão ricas no Docker Hub (`ticczaleski/chatwoot`), permitindo fixar versões estáveis em stacks de produção (`chatwoot-ti.yml`):
    - `latest`: Mantida para deploys automáticos da branch `develop`.
    - `4.18.0`: Versão base extraída de `package.json`.
    - `4.18.0-wa`: Identificador da edição WhatsApp Web.
    - `4.18.0-wa.2`: Tag de release extraída diretamente de `CHANGELOG.md`.
    - Tags SemVer e git tags (`v*`, `*.*.*`, `*.*.*-*`).
    - Input de tag customizada sob demanda via `workflow_dispatch`.

---

## [4.18.0-wa.1] - 2026-09-18

### ✨ Adicionado (Added)
- **Pipeline de CI/CD para Docker Hub (`.github/workflows/docker-build.yml`):**
  - Automação completa para build e push da imagem privada `ticczaleski/chatwoot:latest` a cada commit na branch `develop` e tags versionadas `*-wa`.
  - Cache avançado do Docker Buildx no GitHub Actions para acelerar compilações subsequentes.
- **Automação de Sincronização Upstream (`.github/workflows/sync-upstream.yml`):**
  - Verificação semanal programada contra o repositório oficial `chatwoot/chatwoot`.
  - Abertura automática de Pull Request com checklist de revisão de impacto sempre que houver novidades no upstream.
- **Customização Visual WhatsApp Web Edition:**
  - Balões de mensagem redesenhados em `Base.vue` com cantos arredondados assimétricos (efeito "cauda de balão" do WhatsApp), espaçamentos de 8px e cores oficiais (`#d9fdd3` / `#ffffff` no claro, `#005c4b` / `#202c33` no escuro).
  - Ícones de status de mensagem em `MessageStatus.vue`: Ticks duplos azuis oficiais (`#53bdeb`) para mensagens lidas e cinzas para enviadas/entregues.
  - Cards de conversa na barra lateral (`ConversationCard.vue`) com avatares de 48px, badges verdes de mensagens não lidas (`#25d366`), e metadados alinhados ao estilo WhatsApp Web.
  - Cabeçalho de conversa (`ConversationHeader.vue`) e painel de digitação (`ReplyBox.vue` e `ReplyBottomPanel.vue`) com botões na cor teal `#00a884`.
- **Documentação de Engenharia:**
  - Criação do documento [FORK.md](file:///c:/Repositorio-Projetos-TI/chatwoot/FORK.md) detalhando a arquitetura, motivação, compatibilidade móvel (iOS/Android) e lista de arquivos customizados.
  - Atualização do [README.md](file:///c:/Repositorio-Projetos-TI/chatwoot/README.md) com apresentação da WhatsApp Web Edition.
  - Economia de minutos de GitHub Actions através da adição de `paths-ignore` nos fluxos de testes de backend para alterações restritas ao frontend e documentação.

### 🐛 Corrigido (Fixed)
- Inclusão da paleta de cores `amber` no `tailwind.config.js` e adição de dependência `postcss-import` para resolver falhas de pré-compilação de assets com o Vite em modo de produção.
- Resolução de avisos e erros de ESLint nos componentes Vue customizados.
