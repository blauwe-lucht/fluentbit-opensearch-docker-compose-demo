#!/bin/sh
# One-shot setup: wait for OpenSearch, install the index template, and create
# the "fluentbit-logs" data stream so Fluent Bit can write to it.
#
# Runs in a small curl container (see the opensearch-setup service in
# docker-compose.yml) and exits when done. Fluent Bit waits for a successful
# exit before starting.
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

echo "Creating data stream '$DATA_STREAM' (ignored if it already exists)..."
# 200/201 when created; a 400 "resource_already_exists" is fine on re-runs.
curl -sk -u "$AUTH" -X PUT "$OS_URL/_data_stream/$DATA_STREAM"
echo

echo "Setup complete."
