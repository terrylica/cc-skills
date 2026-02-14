---
name: infra-deploy
description: Cal.com self-hosted deployment to GCP Cloud Run with Supabase PostgreSQL. Docker Compose for local dev. TRIGGERS - deploy calcom, cloud run, self-hosted, docker compose, supabase, gcp deploy, infrastructure, cal.com hosting.
allowed-tools: Read, Bash, Grep, Glob, Write, AskUserQuestion
---

# Infrastructure Deployment

Deploy Cal.com self-hosted to GCP Cloud Run with Supabase PostgreSQL, or run locally via Docker Compose.

## Mandatory Preflight

### Step 1: Check GCP Project Configuration

```bash
echo "CALCOM_GCP_PROJECT: ${CALCOM_GCP_PROJECT:-NOT_SET}"
echo "CALCOM_GCP_ACCOUNT: ${CALCOM_GCP_ACCOUNT:-NOT_SET}"
echo "CALCOM_GCP_REGION: ${CALCOM_GCP_REGION:-us-central1}"
```

**If NOT_SET**: These must be configured in `.mise.local.toml`. Run the setup command.

### Step 2: Verify GCP Authentication

```bash
gcloud auth list --filter="status=ACTIVE" --format="value(account)" 2>/dev/null
```

### Step 3: Check Supabase Configuration

```bash
echo "SUPABASE_PROJECT_REF: ${SUPABASE_PROJECT_REF:-NOT_SET}"
echo "SUPABASE_DB_URL_REF: ${SUPABASE_DB_URL_REF:-NOT_SET}"
```

### Step 4: Verify Cal.com Secrets

```bash
echo "CALCOM_NEXTAUTH_SECRET_REF: ${CALCOM_NEXTAUTH_SECRET_REF:-NOT_SET}"
echo "CALCOM_ENCRYPTION_KEY_REF: ${CALCOM_ENCRYPTION_KEY_REF:-NOT_SET}"
echo "CALCOM_CRON_API_KEY_REF: ${CALCOM_CRON_API_KEY_REF:-NOT_SET}"
```

**All 1Password references must be SET.** Secrets are stored in Claude Automation vault.

---

## Deploy Target: GCP Cloud Run

### Step 1: Verify GCP APIs Enabled

```bash
gcloud services list --enabled \
  --project="$CALCOM_GCP_PROJECT" \
  --account="$CALCOM_GCP_ACCOUNT" 2>/dev/null | grep -E "run|artifact|build"
```

Required APIs: Cloud Run, Artifact Registry, Cloud Build.

### Step 2: Build Container

```bash
# From the cal.com fork directory
cd ~/fork-tools/cal.com

# Build Docker image
docker build -t calcom-self-hosted .
```

### Step 3: Push to Artifact Registry

```bash
# Tag for Artifact Registry
docker tag calcom-self-hosted \
  "${CALCOM_GCP_REGION}-docker.pkg.dev/${CALCOM_GCP_PROJECT}/calcom/calcom:latest"

# Push
docker push \
  "${CALCOM_GCP_REGION}-docker.pkg.dev/${CALCOM_GCP_PROJECT}/calcom/calcom:latest"
```

### Step 4: Deploy to Cloud Run

```bash
# Resolve secrets from 1Password
NEXTAUTH_SECRET=$(op read "$CALCOM_NEXTAUTH_SECRET_REF")
ENCRYPTION_KEY=$(op read "$CALCOM_ENCRYPTION_KEY_REF")
CRON_API_KEY=$(op read "$CALCOM_CRON_API_KEY_REF")
DATABASE_URL=$(op read "$SUPABASE_DB_URL_REF")

gcloud run deploy calcom \
  --image="${CALCOM_GCP_REGION}-docker.pkg.dev/${CALCOM_GCP_PROJECT}/calcom/calcom:latest" \
  --region="$CALCOM_GCP_REGION" \
  --project="$CALCOM_GCP_PROJECT" \
  --account="$CALCOM_GCP_ACCOUNT" \
  --platform=managed \
  --allow-unauthenticated \
  --port=3000 \
  --memory=512Mi \
  --cpu=1 \
  --min-instances=0 \
  --max-instances=2 \
  --set-env-vars="DATABASE_URL=${DATABASE_URL}" \
  --set-env-vars="NEXTAUTH_SECRET=${NEXTAUTH_SECRET}" \
  --set-env-vars="CALENDSO_ENCRYPTION_KEY=${ENCRYPTION_KEY}" \
  --set-env-vars="CRON_API_KEY=${CRON_API_KEY}" \
  --set-env-vars="NEXT_PUBLIC_WEBAPP_URL=https://calcom-${CALCOM_GCP_PROJECT}.run.app" \
  --set-env-vars="NEXT_PUBLIC_API_V2_URL=https://calcom-${CALCOM_GCP_PROJECT}.run.app/api/v2"
```

---

## Deploy Target: Docker Compose (Local Dev)

### docker-compose.yml Template

```yaml
version: "3.9"
services:
  calcom:
    image: calcom/cal.com:latest
    restart: unless-stopped
    ports:
      - "3000:3000"
    env_file:
      - .env
    depends_on:
      database:
        condition: service_healthy

  database:
    image: postgres:15
    restart: unless-stopped
    volumes:
      - calcom-db:/var/lib/postgresql/data
    environment:
      POSTGRES_USER: calcom
      POSTGRES_PASSWORD: calcom
      POSTGRES_DB: calcom
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U calcom"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  calcom-db:
```

### Local .env Template

```bash
DATABASE_URL=postgresql://calcom:calcom@database:5432/calcom
NEXTAUTH_SECRET=<generate-with-openssl>
CALENDSO_ENCRYPTION_KEY=<generate-with-openssl>
CRON_API_KEY=<generate-with-openssl>
NEXT_PUBLIC_WEBAPP_URL=http://localhost:3000
NEXT_PUBLIC_API_V2_URL=http://localhost:3000/api/v2
```

---

## Supabase Database Management

### Check Connection

```bash
DATABASE_URL=$(op read "$SUPABASE_DB_URL_REF")
psql "$DATABASE_URL" -c "SELECT version();"
```

### Run Migrations

```bash
cd ~/fork-tools/cal.com
DATABASE_URL=$(op read "$SUPABASE_DB_URL_REF") npx prisma migrate deploy
```

## 1Password Secret References

All secrets in Claude Automation vault (biometric-free access):

| Secret                    | 1Password Reference                                        |
| ------------------------- | ---------------------------------------------------------- |
| `NEXTAUTH_SECRET`         | `op://Claude Automation/<item-id>/NEXTAUTH_SECRET`         |
| `CALENDSO_ENCRYPTION_KEY` | `op://Claude Automation/<item-id>/CALENDSO_ENCRYPTION_KEY` |
| `CRON_API_KEY`            | `op://Claude Automation/<item-id>/CRON_API_KEY`            |
| `DATABASE_URL`            | `op://Claude Automation/<item-id>/DATABASE_URL`            |
| `DATABASE_DIRECT_URL`     | `op://Claude Automation/<item-id>/DATABASE_DIRECT_URL`     |

## Post-Change Checklist

- [ ] YAML frontmatter valid (no colons in description)
- [ ] Trigger keywords current
- [ ] Path patterns use $HOME not hardcoded paths
- [ ] 1Password references are agnostic (no hardcoded UUIDs)
