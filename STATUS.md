# STATUS — CRM Valarian

**Atualizado:** 2026-07-16 · **No ar:** https://crm.valariangm.com.br

Fork do Chatwoot (MIT). Deploy: `push` → CI publica `ghcr.io/valarian-gm/valarian-crm:develop` (~4min) → **Deploy** no EasyPanel. Setup roda no boot: **zero console**.

## ✅ Feito

- **Infra** — 4 serviços no EasyPanel (pgvector · redis · web · worker), SSL, PT-BR
- **Poda** — `DISABLE_ENTERPRISE=true` (sem SLA/Audit/Custom Roles) + Central de Ajuda e Relatórios por flag
- **Compose auto-instalável** — [`docker-compose.easypanel.yml`](docker-compose.easypanel.yml): cola → 3 senhas → Deploy
- **Captura de lead** — canal API com **UTM** (`utm_source/medium/campaign` no contato), provado ao vivo
- **Kanban** — entrada automática (lead sem estágio cai em Novo) · drag-and-drop · ganho/perder · valor do contrato inline · soma por etapa · filtro por data de entrada · arquivados com filtro
- **Etapas** — criar, remover (travado se tiver lead), reordenar e **renomear** (chave estável, rótulo editável)
- **Conversa** — seletor de estágio sempre visível no painel do contato

## ⬜ Falta

| | O quê | Quem |
|---|---|---|
| **1** | **App na Meta** — destrava WhatsApp Cloud + Instagram + Facebook **e** o CAPI | **Tai** (1-3 dias, gargalo) |
| **2** | **CAPI** — lead vira Cliente → dispara `Purchase` com valor pra Meta (o loop de público) | depende de (1) |
| **3** | **WhatsApp Cloud + Instagram** — inbox nativo; envs `FB_APP_ID`/`FB_APP_SECRET`/`FB_VERIFY_TOKEN`/`IG_VERIFY_TOKEN` | depende de (1) |
| **4** | Branding Valarian (logo/cores) · disparo em massa (flag `whatsapp_campaign`) · calculadora de custo de envio | backlog |

## ⚠️ Armadilhas (custaram caro — não repetir)

1. **O Dockerfile do Chatwoot não tem `CMD` nem `ENTRYPOINT`.** Sem Command, o container sobe e sai com **exit 0** em silêncio (`Complete`, sem erro, log vazio).
2. **`currency` quebra o filtro.** `FilterService::ATTRIBUTE_TYPES` não mapeia currency → cast SQL vazio (`::`). Usar `number` e formatar R$ no front.
3. **`FilterService` concatena condições SEM parênteses.** `AND` tem precedência sobre `OR` → `A OR B AND C` vira `A OR (B AND C)`. Nunca misturar OR com AND no mesmo payload (a coluna Novo faz 2 queries por isso).
4. **A pasta `custom/` reativa o enterprise.** `ChatwootApp.extensions` checa `custom?` **antes** de `enterprise?` e devolve `%w[enterprise custom]` — só usar depois de remover `enterprise/` fisicamente.
5. **Shape dos dados:** `contacts/filter` devolve payload **cru**; `attributes/getAttributesByModel` **não cameliza**; chaves dentro de `custom_attributes` são snake_case de propósito (`stopPaths`).
6. **Allowlists no backend:** `custom_attributes_params` (controller) e `_account.json.jbuilder` fazem cherry-pick — sem abrir a chave, o dado salva e **nunca volta**.
7. **Proxy:** o domínio precisa apontar pra **porta 3000** (padrão é 80 → "Service is not reachable"). Sem domínio cadastrado: 404 + cert `CN=Easypanel`.

## Decisões de arquitetura

- **Fork raso** — core quase intocado, pra continuar puxando `upstream` (`git fetch upstream && git merge upstream/develop`).
- **Sem tabela nova** — o kanban usa custom attributes nativos: `stage` (list) · `valor_contrato` (number) · `arquivado` (checkbox).
- **Chave ≠ rótulo** — a chave do estágio é contrato (código depende de `novo`/`cliente`; contatos guardam em `custom_attributes.stage`); o rótulo vive em `accounts.custom_attributes.kanban_stage_labels` e é livre.
- **`arquivado` é ortogonal ao estágio** — um lead pode estar "qualificado" E perdido; ao restaurar volta pro lugar certo.
- **WhatsApp do cliente = Cloud API oficial** (sem risco de ban). Evolution fica só pro uso interno da ISIS.
