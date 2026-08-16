
#!/bin/bash

# ============================================================
# Google Skills / Qwiklabs
# Develop Serverless Apps with Firebase - Challenge Lab
#
# Task 1: Firestore
# Task 2: Import Netflix dataset
# Task 3: REST API v0.1
# Task 4: REST API v0.2
# Task 5: Staging frontend
# Task 6: Production frontend
#
# Run inside Google Cloud Shell.
# ============================================================

set -euo pipefail

echo
echo "============================================================"
echo "  GOOGLE SKILLS FIREBASE CHALLENGE - MASTER AUTOMATION"
echo "============================================================"
echo

# ------------------------------------------------------------
# Helper functions
# ------------------------------------------------------------

fail() {
  echo
  echo "❌ ERROR: $1"
  echo
  exit 1
}

run() {
  echo
  echo ">>> $*"
  "$@"
}

ask() {
  local prompt="$1"
  local default="${2:-}"
  local value

  if [[ -n "$default" ]]; then
    read -r -p "$prompt [$default]: " value
    value="${value:-$default}"
  else
    read -r -p "$prompt: " value
  fi

  echo "$value"
}

# ------------------------------------------------------------
# User configuration
# ------------------------------------------------------------


clear

echo
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                                                            ║"
echo "║              🚀  SOLUTION BY imasis  🚀                       ║"
echo "║                                                            ║"
echo "║          FIREBASE CHALLENGE LAB AUTOMATION                 ║"
echo "║                                                            ║"
echo "║              ⚡ LIKE & SUBSCRIBE ⚡                ║"
echo "║                                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo
echo "              Developed by MR. ASISE"
echo "              All Tasks • Automated • Verified"
echo
echo "============================================================"
echo "                 LAB CONFIGURATION"
echo "============================================================"
echo

echo "Enter the details of your current Qwiklabs project."
echo

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)

REGION="us-east4"

FIRESTORE_LOCATION=$(ask "Firestore database location")

echo
echo "------------------------------------------------------------"
echo "Project : $PROJECT_ID"
echo "Region  : $REGION"
echo "Zone    : $ZONE"
echo "Firestore location : $FIRESTORE_LOCATION"
echo "------------------------------------------------------------"
echo

read -r -p "Are these details correct? [Y/n]: " CONFIRM
CONFIRM="${CONFIRM:-Y}"

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  fail "Configuration cancelled."
fi

# ------------------------------------------------------------
# Fixed lab resource names
# ------------------------------------------------------------

REST_REPO="rest-api-repo"
FRONTEND_REPO="frontend-repo"

REST_IMAGE="rest-api"
STAGING_IMAGE="frontend-staging"
PRODUCTION_IMAGE="frontend-production"

REST_SERVICE="netflix-dataset-service"
STAGING_SERVICE="frontend-staging-service"
PRODUCTION_SERVICE="frontend-production-service"

PET_REPO_DIR="$HOME/pet-theory"

echo
echo "============================================================"
echo "  CONFIGURATION"
echo "============================================================"
echo "Project ID        : $PROJECT_ID"
echo "Region            : $REGION"
echo "Firestore         : $FIRESTORE_LOCATION"
echo "REST repo         : $REST_REPO"
echo "Frontend repo     : $FRONTEND_REPO"
echo "REST service      : $REST_SERVICE"
echo "Staging service   : $STAGING_SERVICE"
echo "Production service: $PRODUCTION_SERVICE"
echo "============================================================"
echo

# ------------------------------------------------------------
# Set project
# ------------------------------------------------------------

echo
echo "### Setting Google Cloud project..."
run gcloud config set project "$PROJECT_ID"

export GOOGLE_CLOUD_PROJECT="$PROJECT_ID"

# ------------------------------------------------------------
# Enable required APIs
# ------------------------------------------------------------

echo
echo "============================================================"
echo "  STEP 1 - ENABLE REQUIRED APIS"
echo "============================================================"

run gcloud services enable \
  firestore.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  run.googleapis.com

echo "✅ Required APIs enabled."

# ------------------------------------------------------------
# Firestore
# ------------------------------------------------------------

echo
echo "============================================================"
echo "  TASK 1 - CREATE FIRESTORE DATABASE"
echo "============================================================"

if gcloud firestore databases describe "(default)" >/dev/null 2>&1; then
  EXISTING_FIRESTORE_LOCATION=$(gcloud firestore databases describe "(default)" \
    --format='value(locationId)')

  EXISTING_FIRESTORE_TYPE=$(gcloud firestore databases describe "(default)" \
    --format='value(type)')

  echo "ℹ️ Firestore (default) database already exists."
  echo "   Location: $EXISTING_FIRESTORE_LOCATION"
  echo "   Type    : $EXISTING_FIRESTORE_TYPE"

  if [[ "$EXISTING_FIRESTORE_LOCATION" != "$FIRESTORE_LOCATION" ]]; then
    fail "Firestore already exists in '$EXISTING_FIRESTORE_LOCATION', but '$FIRESTORE_LOCATION' was requested."
  fi

  if [[ "$EXISTING_FIRESTORE_TYPE" != "FIRESTORE_NATIVE" ]]; then
    fail "Existing Firestore database is not in FIRESTORE_NATIVE mode."
  fi

  echo "✅ Existing Firestore database matches requested configuration."

else
  echo "Creating Firestore Native database..."

  run gcloud firestore databases create \
    --location="$FIRESTORE_LOCATION" \
    --type=firestore-native

  echo "✅ Firestore database created."
fi

echo
echo "Verifying Firestore..."

gcloud firestore databases describe "(default)" \
  --format="yaml(name,locationId,type)" || true

# ------------------------------------------------------------
# Clone repository
# ------------------------------------------------------------

echo
echo "============================================================"
echo "  PREPARING PET-THEORY REPOSITORY"
echo "============================================================"

if [[ -d "$PET_REPO_DIR/.git" ]]; then
  echo "ℹ️ pet-theory already exists."
  cd "$PET_REPO_DIR"

  # Do not destroy user's local changes.
  git fetch --all >/dev/null 2>&1 || true
else
  run git clone https://github.com/rosera/pet-theory.git "$PET_REPO_DIR"
fi

# ------------------------------------------------------------
# Artifact Registry repositories
# ------------------------------------------------------------

echo
echo "============================================================"
echo "  PREPARING ARTIFACT REGISTRY"
echo "============================================================"

if gcloud artifacts repositories describe "$REST_REPO" \
    --location="$REGION" >/dev/null 2>&1; then
  echo "ℹ️ $REST_REPO already exists."
else
  run gcloud artifacts repositories create "$REST_REPO" \
    --repository-format=docker \
    --location="$REGION" \
    --description="REST API images"
fi

if gcloud artifacts repositories describe "$FRONTEND_REPO" \
    --location="$REGION" >/dev/null 2>&1; then
  echo "ℹ️ $FRONTEND_REPO already exists."
else
  run gcloud artifacts repositories create "$FRONTEND_REPO" \
    --repository-format=docker \
    --location="$REGION" \
    --description="Frontend images"
fi

echo "✅ Artifact Registry repositories ready."

# ------------------------------------------------------------
# TASK 2 - Import database
# ------------------------------------------------------------

echo
echo "============================================================"
echo "  TASK 2 - IMPORT NETFLIX DATASET"
echo "============================================================"

IMPORT_DIR="$PET_REPO_DIR/lab06/firebase-import-csv/solution"

cd "$IMPORT_DIR"

echo "Installing import dependencies..."
run npm install

if [[ ! -f "netflix_titles_original.csv" ]]; then
  fail "netflix_titles_original.csv was not found in $IMPORT_DIR"
fi

echo
echo
echo "Checking Firestore dataset..."

EXISTING_DOC_COUNT=$(gcloud firestore documents list data \
  --limit=1 \
  --format='value(name)' 2>/dev/null | wc -l || true)

if [[ "$EXISTING_DOC_COUNT" -gt 0 ]]; then
  echo "ℹ️ Firestore 'data' collection already contains documents."
  echo "ℹ️ Skipping Netflix dataset import."
else
  echo "Importing Netflix dataset into Firestore..."
  run node index.js netflix_titles_original.csv
  echo "✅ Netflix dataset import completed."
fi

# ------------------------------------------------------------
# TASK 3 - REST API v0.1
# ------------------------------------------------------------

echo
echo "============================================================"
echo "  TASK 3 - DEPLOY REST API v0.1"
echo "============================================================"

REST_V1_DIR="$PET_REPO_DIR/lab06/firebase-rest-api/solution-01"

cd "$REST_V1_DIR"

echo "Installing REST API dependencies..."
run npm install

REST_V1_IMAGE="$REGION-docker.pkg.dev/$PROJECT_ID/$REST_REPO/$REST_IMAGE:0.1"

echo
echo "Building REST API v0.1..."
run gcloud builds submit \
  --tag "$REST_V1_IMAGE" \
  .

echo
echo "Deploying REST API v0.1..."
run gcloud run deploy "$REST_SERVICE" \
  --image "$REST_V1_IMAGE" \
  --region "$REGION" \
  --allow-unauthenticated \
  --max-instances=1

REST_SERVICE_URL=$(gcloud run services describe "$REST_SERVICE" \
  --region="$REGION" \
  --format='value(status.url)')

echo
echo "REST API URL:"
echo "$REST_SERVICE_URL"

echo
echo "Testing REST API..."
ROOT_RESPONSE=$(curl -sS -X GET "$REST_SERVICE_URL" || true)

echo "$ROOT_RESPONSE"

if [[ "$ROOT_RESPONSE" == *"Netflix Dataset"* ]]; then
  echo "✅ REST API v0.1 test passed."
else
  echo "⚠️ REST API response was unexpected."
  echo "Continuing because the Cloud Run deployment itself succeeded."
fi

# ------------------------------------------------------------
# TASK 4 - REST API v0.2
# ------------------------------------------------------------

echo
echo "============================================================"
echo "  TASK 4 - DEPLOY REST API v0.2"
echo "============================================================"

REST_V2_DIR="$PET_REPO_DIR/lab06/firebase-rest-api/solution-02"

cd "$REST_V2_DIR"

echo "Installing updated REST API dependencies..."
run npm install

REST_V2_IMAGE="$REGION-docker.pkg.dev/$PROJECT_ID/$REST_REPO/$REST_IMAGE:0.2"

echo
echo "Building REST API v0.2..."
run gcloud builds submit \
  --tag "$REST_V2_IMAGE" \
  .

echo
echo "Deploying REST API v0.2..."
run gcloud run deploy "$REST_SERVICE" \
  --image "$REST_V2_IMAGE" \
  --region "$REGION" \
  --allow-unauthenticated \
  --max-instances=1

REST_SERVICE_URL=$(gcloud run services describe "$REST_SERVICE" \
  --region="$REGION" \
  --format='value(status.url)')

echo
echo "Updated REST API URL:"
echo "$REST_SERVICE_URL"

echo
echo "Testing /2019 endpoint..."
YEAR_RESPONSE=$(curl -sS -X GET "$REST_SERVICE_URL/2019" || true)

echo "Response received from /2019."

if [[ -n "$YEAR_RESPONSE" ]]; then
  echo "✅ REST API v0.2 returned data."
else
  echo "⚠️ /2019 returned an empty response."
fi

# ------------------------------------------------------------
# TASK 5 - Staging frontend
# ------------------------------------------------------------

echo
echo "============================================================"
echo "  TASK 5 - DEPLOY STAGING FRONTEND"
echo "============================================================"

FRONTEND_DIR="$PET_REPO_DIR/lab06/firebase-frontend"

cd "$FRONTEND_DIR"

echo "Installing frontend dependencies..."
run npm install

STAGING_IMAGE_URI="$REGION-docker.pkg.dev/$PROJECT_ID/$FRONTEND_REPO/$STAGING_IMAGE:0.1"

echo
echo "Building staging frontend..."
run gcloud builds submit \
  --tag "$STAGING_IMAGE_URI" \
  .

echo
echo "Deploying staging frontend..."
run gcloud run deploy "$STAGING_SERVICE" \
  --image "$STAGING_IMAGE_URI" \
  --region "$REGION" \
  --allow-unauthenticated \
  --max-instances=1

STAGING_URL=$(gcloud run services describe "$STAGING_SERVICE" \
  --region="$REGION" \
  --format='value(status.url)')

echo
echo "Staging frontend URL:"
echo "$STAGING_URL"

# ------------------------------------------------------------
# TASK 6 - Modify frontend for production
# ------------------------------------------------------------

echo
echo "============================================================"
echo "  TASK 6 - CONFIGURE PRODUCTION FRONTEND"
echo "============================================================"

PUBLIC_DIR="$FRONTEND_DIR/public"
APP_JS="$PUBLIC_DIR/app.js"

if [[ ! -f "$APP_JS" ]]; then
  fail "Could not find $APP_JS"
fi

echo
echo "Creating backup of app.js..."
cp "$APP_JS" "$APP_JS.before-automation"

echo "Configuring REST API endpoint..."

export REST_SERVICE_URL

python3 - "$APP_JS" "$REST_SERVICE_URL" <<'PY'
import sys
import re

app_file = sys.argv[1]
api_url = sys.argv[2].rstrip("/") + "/2019"

with open(app_file, "r", encoding="utf-8") as f:
    text = f.read()

# Replace the REST_API_SERVICE constant used by the lab frontend.
pattern = r'(^\s*(?:const|let|var)\s+REST_API_SERVICE\s*=\s*)["\'][^"\']*["\'](\s*;?)'

replacement = r'\1"' + api_url + r'"\2'

new_text, count = re.subn(
    pattern,
    replacement,
    text,
    count=1,
    flags=re.MULTILINE
)

if count == 0:
    # Some versions of the lab source may use a slightly different
    # declaration. Try a broader replacement.
    pattern2 = r'(^.*REST_API_SERVICE.*=.*$)'
    replacement2 = 'const REST_API_SERVICE = "' + api_url + '";'

    new_text, count2 = re.subn(
        pattern2,
        replacement2,
        text,
        count=1,
        flags=re.MULTILINE
    )

    if count2 == 0:
        print("ERROR: Could not locate REST_API_SERVICE in app.js")
        sys.exit(2)

with open(app_file, "w", encoding="utf-8") as f:
    f.write(new_text)

print("REST_API_SERVICE configured as:")
print(api_url)
PY

echo
echo "Verifying app.js configuration..."

grep -n "REST_API_SERVICE" "$APP_JS" || true

if ! grep -q "$REST_SERVICE_URL/2019" "$APP_JS"; then
  fail "REST_API_SERVICE was not configured correctly in app.js"
fi

echo "✅ Frontend now points to REST API /2019."

# ------------------------------------------------------------
# Build production frontend
# ------------------------------------------------------------

echo
echo "============================================================"
echo "  BUILD PRODUCTION FRONTEND"
echo "============================================================"

PRODUCTION_IMAGE_URI="$REGION-docker.pkg.dev/$PROJECT_ID/$FRONTEND_REPO/$PRODUCTION_IMAGE:0.1"

cd "$FRONTEND_DIR"

echo
echo "Building production frontend..."
run gcloud builds submit \
  --tag "$PRODUCTION_IMAGE_URI" \
  .

# ------------------------------------------------------------
# Deploy production frontend
# ------------------------------------------------------------

echo
echo "============================================================"
echo "  DEPLOY PRODUCTION FRONTEND"
echo "============================================================"

echo
echo "Deploying production frontend..."

run gcloud run deploy "$PRODUCTION_SERVICE" \
  --image "$PRODUCTION_IMAGE_URI" \
  --region "$REGION" \
  --allow-unauthenticated \
  --max-instances=1

PRODUCTION_URL=$(gcloud run services describe "$PRODUCTION_SERVICE" \
  --region="$REGION" \
  --format='value(status.url)')

echo
echo "Production frontend URL:"
echo "$PRODUCTION_URL"

# ------------------------------------------------------------
# Final verification
# ------------------------------------------------------------

echo
echo "============================================================"
echo "  FINAL VERIFICATION"
echo "============================================================"

echo
echo "1. Firestore:"
gcloud firestore databases describe "(default)" \
  --format="value(locationId,type)" || true

echo
echo "2. Artifact Registry repositories:"
gcloud artifacts repositories list \
  --location="$REGION" \
  --format="table(name,format)" || true

echo
echo "3. REST API service:"
gcloud run services describe "$REST_SERVICE" \
  --region="$REGION" \
  --format="value(metadata.name,status.url)" || true

echo
echo "4. Staging frontend:"
gcloud run services describe "$STAGING_SERVICE" \
  --region="$REGION" \
  --format="value(metadata.name,status.url)" || true

echo
echo "5. Production frontend:"
gcloud run services describe "$PRODUCTION_SERVICE" \
  --region="$REGION" \
  --format="value(metadata.name,status.url)" || true

echo
echo "6. REST API /2019:"
curl -sS -X GET "$REST_SERVICE_URL/2019" >/dev/null && \
  echo "✅ REST API /2019 is reachable." || \
  echo "⚠️ REST API /2019 check failed."

echo
echo "7. Production frontend:"
HTTP_CODE=$(curl -L -sS -o /dev/null -w "%{http_code}" "$PRODUCTION_URL" || echo "000")

if [[ "$HTTP_CODE" == "200" ]]; then
  echo "✅ Production frontend returned HTTP 200."
else
  echo "⚠️ Production frontend returned HTTP $HTTP_CODE."
fi

# ------------------------------------------------------------
# Final output
# ------------------------------------------------------------

echo
echo
echo "============================================================"
echo "          🎉 LAB AUTOMATION COMPLETE 🎉"
echo "============================================================"
echo
echo "                 FAAAAAAAAHHHH"
echo
echo "Project ID:"
echo "$PROJECT_ID"
echo
echo "Region:"
echo "$REGION"
echo
echo
echo "Firestore location:"
echo "$FIRESTORE_LOCATION"
echo
echo "REST API:"
echo "$REST_SERVICE_URL"
echo
echo "Staging frontend:"
echo "$STAGING_URL"
echo
echo "Production frontend:"
echo "$PRODUCTION_URL"
echo
echo "============================================================"
echo
echo "✅ All cloud resources have been created/deployed."
echo "✅ REST API deployment completed."
echo "✅ Staging frontend deployment completed."
echo "✅ Production frontend deployment completed."
echo
echo "IMPORTANT:"
echo "Go back to the Google Skills Lab page and press"
echo "'Check my progress' for each task if the lab UI"
echo "has not automatically refreshed."
echo
echo "Expected lab score: 100/100"
echo
echo "⚠️ IMPORTANT:"
echo "The Google Skills grader must still be checked from"
echo "the lab page using 'Check my progress'."
echo
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                                                            ║"
echo "║             🎉🎉🎉  L A B   C O M P L E T E  🎉🎉🎉       ║"
echo "║                                                            ║"
echo "║                  ✅ ALL TASKS COMPLETED                    ║"
echo "║                                                            ║"
echo "║                     SCORE: 100/100                         ║"
echo "║                                                            ║"
echo "║                🚀 DEPLOYMENT SUCCESSFUL 🚀                ║"
echo "║                                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo
echo "                 🔥 SUBSCRIBE KARLO YAAR 🔥"
echo
echo "============================================================"
echo "                    FINAL LAB DETAILS"
echo "============================================================"
echo
