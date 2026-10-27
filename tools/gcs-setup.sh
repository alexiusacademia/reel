#!/bin/bash
# One-time setup of the place Reel's releases are kept: a Google Cloud
# Storage bucket anyone can read (the website's download buttons fetch from it)
# and only you can write.
#
#   gcloud auth login            # first, if you aren't signed in
#   tools/gcs-setup.sh
#
# The project, bucket and region come from packaging/publish.env.
#
# Author: Alexius Academia
# Date: 2026-10-27
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source packaging/publish.env; set +a
: "${REEL_GCS_PROJECT:?}" "${REEL_GCS_BUCKET:?}" "${REEL_GCS_REGION:?}"

echo "==> bucket gs://$REEL_GCS_BUCKET in project $REEL_GCS_PROJECT ($REEL_GCS_REGION)"
if gcloud storage buckets describe "gs://$REEL_GCS_BUCKET" --project "$REEL_GCS_PROJECT" > /dev/null 2>&1; then
    echo "→ it's there already"
else
    gcloud storage buckets create "gs://$REEL_GCS_BUCKET" --project "$REEL_GCS_PROJECT" \
        --location "$REEL_GCS_REGION" --uniform-bucket-level-access
fi
echo "→ letting everyone read it"
gcloud storage buckets add-iam-policy-binding "gs://$REEL_GCS_BUCKET" \
    --member=allUsers --role=roles/storage.objectViewer > /dev/null
echo "→ done: $REEL_PUBLIC_BASE"
