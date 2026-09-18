# Changelog

Todas as alterações notáveis no fork **`ticczaleski/chatwoot`** (WhatsApp Web Edition) serão documentadas neste arquivo.

O formato é baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/),
e este projeto adere ao [Versionamento Semântico](https://semver.org/lang/pt-BR/) com o sufixo `-wa`.

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
