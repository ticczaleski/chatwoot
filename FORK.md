# Arquitetura e Guia de Manutenção do Fork (WhatsApp Web Edition)

Este documento descreve a estrutura técnica, decisões de design, pipelines de CI/CD e procedimentos operacionais para manter o fork **`ticczaleski/chatwoot`** sincronizado com o repositório oficial do Chatwoot (`chatwoot/chatwoot`).

---

## 1. Motivação e Escopo

- **Problema de Negócio:** Resistência de equipes operacionais e setores internos em adotar o Chatwoot em substituição ao WhatsApp Web convencional em canais corporativos compartilhados.
- **Solução Técnica:** Adaptação da interface web do dashboard para um padrão visual fiel ao WhatsApp Web, mantendo integralmente todas as capacidades de atendimento omnichannel, automações, relatórios e permissões do Chatwoot.
- **Escopo das Modificações:** Exclusivamente na camada de apresentação frontend (`app/javascript/dashboard/`, estilos Tailwind e assets estáticos). **Nenhum endpoint de API, WebSocket ou schema de banco de dados foi alterado.**

---

## 2. Compatibilidade Mobile (Android & iOS)

Os aplicativos móveis oficiais do Chatwoot comunicam-se com a instância através da API REST pública (`/api/v1/...`) e canais WebSocket do Action Cable.
Como este fork preserva 100% dos controllers Rails, rotas e payloads, **a compatibilidade com os aplicativos Android e iOS permanece intacta**. Os atendentes podem alternar livremente entre o app móvel oficial e o dashboard web personalizado.

---

## 3. Arquivos Customizados no Fork

Abaixo está o mapa de todos os arquivos modificados ou adicionados neste fork. Mantenha esta lista em mente ao revisar atualizações do upstream:

| Arquivo | Tipo | Descrição |
|---|---|---|
| `CHANGELOG.md` | Documentação | Registro cronológico detalhado de todas as alterações, correções e versões do fork. |
| `tailwind.config.js` | Configuração | Paleta `wa:*`, import de `defaultColors.amber` e definição de background `wa-doodle`. |
| `public/dashboard/images/wa-chat-bg.png` | Asset | Papel de parede oficial com doodles do WhatsApp Web. |
| `app/javascript/dashboard/components-next/message/bubbles/Base.vue` | Componente | Balões de mensagem com cantos assimétricos (cauda), espaçamentos e metadados. |
| `app/javascript/dashboard/components-next/message/MessageList.vue` | Componente | Área de mensagens com background do WhatsApp Web via classes Tailwind. |
| `app/javascript/dashboard/components-next/message/MessageStatus.vue` | Componente | Ticks de confirmação (cinza para entregue, azul WhatsApp `#53bdeb` para lido). |
| `app/javascript/dashboard/components-next/Conversation/ConversationCard/ConversationCard.vue` | Componente | Card de conversa com avatares de 48px, tipografia e espaçamentos do WhatsApp Web. |
| `app/javascript/dashboard/components-next/Conversation/ConversationCard/UnreadBadge.vue` | Componente | Badge de mensagens não lidas no tom verde `#25d366`. |
| `app/javascript/dashboard/components-next/Conversation/ConversationCard/CardMessagePreview.vue` | Componente | Preview de mensagem com estilo WhatsApp. |
| `app/javascript/dashboard/components-next/Conversation/ConversationCard/CardMessagePreviewWithMeta.vue` | Componente | Preview com metadados ajustados. |
| `app/javascript/dashboard/components/ChatList.vue` | Componente | Estrutura e plano de fundo da coluna de conversas. |
| `app/javascript/dashboard/components/ChatListHeader.vue` | Componente | Cabeçalho da lista de conversas com botão de Nova Conversa (`ComposeConversation`). |
| `app/javascript/dashboard/components/widgets/conversation/ConversationBox.vue` | Componente | Painel principal de conversa com bordas e cores alinhadas. |
| `app/javascript/dashboard/components/widgets/conversation/ConversationHeader.vue` | Componente | Barra de título da conversa aberta (avatar, nome e status). |
| `app/javascript/dashboard/components/widgets/conversation/MessagesView.vue` | Componente | Container das mensagens e ocultação de banner 24h para canais de API. |
| `app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue` | Componente | Caixa de digitação sem bloqueio de janela 24h para API inboxes e com min-height seguro. |
| `app/javascript/dashboard/components/widgets/WootWriter/ReplyBottomPanel.vue` | Componente | Botão de envio em tom teal `#00a884`. |
| `app/services/conversations/message_window_service.rb` | Backend | Suporte a `ignore_messaging_window` e compatibilidade com conversas outbound. |
| `app/services/contacts/contactable_inboxes_service.rb` | Backend | Roteamento de número de telefone do contato para canais de API (Evolution API). |
| `docker-compose.production.yaml` | Infra | Aponta para a imagem `ticczaleski/chatwoot:latest`. |
| `.github/workflows/docker-build.yml` | CI/CD | Pipeline automatizado de build e publicação no Docker Hub. |
| `.github/workflows/sync-upstream.yml` | CI/CD | Checagem semanal de novidades do repositório upstream com PR automático. |

---

## 4. Pipeline de CI/CD e Docker Hub

### Publicação Automática da Imagem (`.github/workflows/docker-build.yml`)
- **Gatilho:** Pushes na branch `develop` ou tags com padrão `X.Y.Z-wa`.
- **Imagem de Destino:** `ticczaleski/chatwoot` no Docker Hub.
- **Tags Geradas:**
  - `latest`: Atualizada a cada push em `develop`.
  - `sha-<commit>`: Tag pontual para rastreabilidade de commits.
  - `X.Y.Z-wa`: Tag oficial de versão estável (ex: `4.18.0-wa`).
- **Segurança:** Autenticação via GitHub Secrets (`DOCKER_USERNAME` e `DOCKER_PASSWORD`).

### Otimização de Minutos de Execução
Para evitar consumo excessivo de minutos no GitHub Actions:
- `run_foss_spec.yml` (testes de Ruby/RSpec) está configurado com `paths-ignore` para ignorar commits de frontend.
- `frontend-fe.yml` está configurado com `paths` para rodar apenas quando arquivos relevantes de frontend forem modificados.

---

## 5. Guia de Sincronização com o Chatwoot Oficial (Upstream)

O workflow `.github/workflows/sync-upstream.yml` executa semanalmente toda segunda-feira às 09:00 UTC. Se houver novas atualizações no repositório oficial, ele abre um Pull Request automaticamente.

### Procedimento Manual de Sincronização:

```bash
# 1. Certifique-se de que o remote upstream existe
git remote add upstream https://github.com/chatwoot/chatwoot.git

# 2. Busque as novidades
git fetch upstream develop

# 3. Crie uma branch temporária para a atualização
git checkout -b sync/upstream-$(date +%Y%m%d)

# 4. Faça o rebase ou merge das alterações
git merge upstream/develop

# 5. Resolva eventuais conflitos focando principalmente em:
#    - tailwind.config.js
#    - ReplyBox.vue
#    - Base.vue

# 6. Teste o build e o lint localmente:
pnpm eslint
node ./node_modules/vite/bin/vite.js build

# 7. Conclua o merge na branch develop e gere nova tag
git checkout develop
git merge sync/upstream-$(date +%Y%m%d)
git tag 4.X.X-wa
git push origin develop --tags
```

---

## 6. Comandos Úteis de Desenvolvimento

```bash
# Instalar dependências
pnpm install

# Rodar linting
pnpm eslint

# Corrigir linting automaticamente
pnpm eslint:fix

# Compilar assets de produção com Vite
node ./node_modules/vite/bin/vite.js build

# Subir ambiente de produção com Docker Compose
docker compose -f docker-compose.production.yaml up -d
```
