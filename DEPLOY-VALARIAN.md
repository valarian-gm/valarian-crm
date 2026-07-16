# Deploy — CRM Valarian no EasyPanel (VPS)

> Fork do Chatwoot (`valarian-gm/valarian-crm`). Domínio alvo: `crm.valariangm.com.br`.
> Estratégia em 2 fases: **F0** valida infra com a imagem oficial; **F1** troca pra imagem do NOSSO fork (mesmo banco, sem perder nada). A troca é só o campo "Image".

## Arquitetura (4 serviços no mesmo projeto EasyPanel)

| Serviço | Imagem | Papel |
|---|---|---|
| `crm-web` | (fase 0) `chatwoot/chatwoot:latest` → (fase 1) `ghcr.io/valarian-gm/valarian-crm:develop` | Rails web (porta 3000) |
| `crm-worker` | a MESMA do web | Sidekiq (jobs) |
| `crm-db` | `pgvector/pgvector:pg16` | Postgres (pgvector é obrigatório) |
| `crm-redis` | `redis:7-alpine` | fila/cache |

## Fase 0 — subir e validar (~15 min)

1. **EasyPanel → New Project** `valarian-crm`.
2. **Postgres:** New Service → Postgres. Se o EasyPanel não oferecer pgvector, criar como App com a imagem `pgvector/pgvector:pg16`, env `POSTGRES_DB=chatwoot`, `POSTGRES_USER=chatwoot`, `POSTGRES_PASSWORD=<gerar forte>`, volume em `/var/lib/postgresql/data`.
3. **Redis:** New Service → Redis (ou App `redis:7-alpine`, volume em `/data`).
4. **App `crm-web`:** imagem `chatwoot/chatwoot:latest`, porta **3000**, domínio `crm.valariangm.com.br` (DNS A → IP da VPS; EasyPanel emite o SSL).
   - **Start command:** `bundle exec rails s -p 3000 -b 0.0.0.0`
   - Volume: `/app/storage` (uploads/avatars).
5. **App `crm-worker`:** MESMA imagem e MESMAS envs do web.
   - **Start command:** `bundle exec sidekiq -C config/sidekiq.yml`
   - Sem domínio/porta.
6. **Env vars (web E worker, idênticas):**

```env
RAILS_ENV=production
NODE_ENV=production
INSTALLATION_ENV=docker
SECRET_KEY_BASE=<gerar na VPS: openssl rand -hex 64 — NUNCA colar em chat>
FRONTEND_URL=https://crm.valariangm.com.br
DEFAULT_LOCALE=pt_BR
FORCE_SSL=true
ENABLE_ACCOUNT_SIGNUP=false
# — banco (usar host interno do EasyPanel, ex: valarian-crm_crm-db) —
POSTGRES_HOST=<host interno do serviço postgres>
POSTGRES_PORT=5432
POSTGRES_DATABASE=chatwoot
POSTGRES_USERNAME=chatwoot
POSTGRES_PASSWORD=<a mesma do passo 2>
# — redis —
REDIS_URL=redis://<host interno do redis>:6379
# — storage local (v1; S3 depois se precisar) —
ACTIVE_STORAGE_SERVICE=local
# — A NOSSA PODA —
DISABLE_ENTERPRISE=true
```

7. **Preparar o banco (só na 1ª vez):** no console/terminal do serviço `crm-web` (EasyPanel → service → Console):
   ```bash
   bundle exec rails db:chatwoot_prepare
   ```
8. Abrir `https://crm.valariangm.com.br` → cria a conta admin (o signup público fica fechado pelo env; o 1º acesso via onboarding funciona).

### Validação F0
- [ ] Login ok, painel abre em PT-BR.
- [ ] Criar uma conta/inbox de teste.
- [ ] Confirmar que features enterprise NÃO aparecem (SLA, Audit Logs, Custom Roles) — efeito do `DISABLE_ENTERPRISE=true`.

## Fase 1 — trocar pra imagem do fork

1. No GitHub, o workflow `build-image.yml` publica `ghcr.io/valarian-gm/valarian-crm:develop` a cada push (Actions → conferir build verde).
2. A imagem é **privada**: no EasyPanel, em Registry/Credentials, adicionar `ghcr.io` com usuário GitHub + um PAT com escopo `read:packages`.
3. Nos serviços `crm-web` e `crm-worker`: trocar Image → `ghcr.io/valarian-gm/valarian-crm:develop` → Redeploy. Banco/Redis/envs intocados.
4. A partir daqui: **push no repo = nova imagem = Redeploy** puxa a poda/kanban.

## WhatsApp (Cloud API oficial — depois do CRM no ar)

Chatwoot tem inbox "WhatsApp Cloud" nativo: Inbox → New → WhatsApp → Provider "WhatsApp Cloud", com `Phone number ID`, `Business Account ID` e `API Key` (token permanente do app Meta). Pré-requisito Meta Business: app com produto WhatsApp + número verificado (número vira API-only). O webhook URL/verify token o próprio Chatwoot mostra na criação do inbox.

## Notas
- **Evolution API:** segue na VPS para uso interno da ISIS. O canal do cliente final no CRM é a Cloud API oficial (sem risco de ban).
- **Upgrades do upstream:** `git fetch upstream && git merge upstream/develop` no repo local → push → imagem nova.
- **Backup:** volume do Postgres é o dado que importa (leads/conversas). Configurar backup do volume no EasyPanel/VPS.
