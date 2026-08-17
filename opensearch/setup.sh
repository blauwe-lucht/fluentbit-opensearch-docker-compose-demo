#!/bin/sh
# One-shot setup: wait for OpenSearch, install the index template and ISM
# retention policy, and create the "fluentbit-logs" data stream so Fluent Bit
# can write to it.
#
# Runs in a small curl container (see the opensearch-setup service in
# docker-compose.yml) and exits when done. Fluent Bit waits for a successful
# exit before starting.
#
# Order matters: the ISM policy (with its ism_template) must exist *before* the
# data stream is created, so the first backing index automatically picks it up.
set -eu

OS_URL="https://opensearch-node1:9200"
AUTH="admin:T!mberW0lf#92"
DATA_STREAM="fluentbit-logs"

echo "Waiting for OpenSearch to be ready (status yellow or green)..."
until curl -sk -u "$AUTH" \
    "$OS_URL/_cluster/health?wait_for_status=yellow&timeout=5s" 2>/dev/null \
    | grep -q '"status":"\(yellow\|green\)"'; do
    echo "  ...not ready yet, retrying in 3s"
    sleep 3
done
echo "OpenSearch is ready."

echo "Installing index template 'fluentbit-logs-template'..."
curl -fsSk -u "$AUTH" -X PUT \
    "$OS_URL/_index_template/fluentbit-logs-template" \
    -H 'Content-Type: application/json' \
    --data-binary @/opensearch/index-template.json
echo

echo "Installing ISM retention policy 'fluentbit-logs-retention' (30-day retention)..."
# PUT is idempotent for the initial policy; on re-runs OpenSearch returns a 409
# "version conflict" because the policy already exists, which is fine here.
curl -sk -u "$AUTH" -X PUT \
    "$OS_URL/_plugins/_ism/policies/fluentbit-logs-retention" \
    -H 'Content-Type: application/json' \
    --data-binary @/opensearch/ism-policy.json
echo

echo "Creating data stream '$DATA_STREAM' (ignored if it already exists)..."
# 200/201 when created; a 400 "resource_already_exists" is fine on re-runs.
curl -sk -u "$AUTH" -X PUT "$OS_URL/_data_stream/$DATA_STREAM"
echo

echo "Setup complete."
