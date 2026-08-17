# FluentBit & OpenSearch and OpenSearch Dashboards demo

This repository provides a simple setup to run [OpenSearch](https://opensearch.org/docs/latest/getting-started/intro/)
and [OpenSearch Dashboards](https://www.opensearch.org/docs/latest/dashboards/) 
with [FluentBit](https://fluentbit.io/) as log parser & forwarder
using [Docker Compose](https://docs.docker.com/compose/),
based on the [official example docker-compose.yml](https://opensearch.org/docs/latest/install-and-configure/install-opensearch/docker/#deploy-an-opensearch-cluster-using-docker-compose).

## Prerequisites

Before you begin, ensure you have the following installed on your machine:

- [Docker](https://docs.docker.com/get-docker/)
- [Docker Compose](https://docs.docker.com/compose/install/)

Also make sure you configure your host settings according to the [OpenSearch documentation](https://opensearch.org/docs/latest/install-and-configure/install-opensearch/docker/#configure-important-host-settings).

## Getting Started

1. **Clone the repository**:

   ```bash
   git clone https://github.com/blauwe-lucht/fluentbit-opensearch-docker-compose-demo.git
   cd fluentbit-opensearch-docker-compose-demo
   ```

2. **Start the OpenSearch and OpenSearch Dashboards**:

    ```bash
    docker compose up -d
    ```

    This will start the OpenSearch server and the OpenSearch Dashboards interface.

3. **Access the OpenSearch Dashboards**:

    Once the services are up and running, you can access the OpenSearch Dashboards by navigating to <http://localhost:5601>.
    Use admin/T!mberW0lf#92 to login.

## Parsing log files with Fluent Bit

The stack includes a [Fluent Bit](https://fluentbit.io/) container that tails
log files, parses them, and ships the structured records into OpenSearch.

### Expected log format

Fluent Bit expects each line to look like:

```text
yyyy-mm-dd HH:MM:SS.mmm LOGLEVEL MSG
```

for example:

```text
2026-08-12 14:30:42.123 INFO Service started successfully
```

Each line is split into three fields:

- `@timestamp` — parsed from `yyyy-mm-dd HH:MM:SS.mmm` (millisecond precision).
  **The timestamp is interpreted as UTC.** To use a different timezone, add a
  `Time_Offset` line (e.g. `Time_Offset +0200`) to the parser in
  [`fluent-bit/parsers.conf`](fluent-bit/parsers.conf).
- `level` — the log level (`INFO`, `DEBUG`, `WARN`, `ERROR`, ...).
- `message` — the rest of the line.

The parsing rules live in [`fluent-bit/parsers.conf`](fluent-bit/parsers.conf)
and the inputs/outputs in [`fluent-bit/fluent-bit.conf`](fluent-bit/fluent-bit.conf).
Both files are mounted read-only into the container.

### How it works

- Before Fluent Bit starts, a one-shot `opensearch-setup` container waits for
  the cluster to be healthy, installs an index template, and creates the
  **`fluentbit-logs`** [data stream](https://opensearch.org/docs/latest/im-plugin/data-streams/).
  The template ([`opensearch/index-template.json`](opensearch/index-template.json))
  defines the `data_stream` and the field mappings (`@timestamp` as a date,
  `level` as a keyword, `message` as text). Fluent Bit only starts once this
  container has exited successfully (`service_completed_successfully`).
- Fluent Bit tails every `*.log` file in the [`logs/`](logs/) directory, which
  is mounted into the container at `/logs`.
- Parsed records are written to the **`fluentbit-logs`** data stream over HTTPS
  as `admin` (TLS verification is disabled because the cluster uses a
  self-signed certificate — fine for this demo, not for production). Because
  data streams only accept the `create` bulk operation, the output sets
  `Write_Operation create`.
- Fluent Bit records how far it has read in a small SQLite database, so
  restarts don't re-ingest the same lines. This state lives in the dedicated
  `fluent-bit-state` Docker volume (mounted at `/var/lib/fluent-bit`).

Using a data stream (instead of a plain auto-created index) gives you an
append-only, time-series-friendly target with a fixed mapping and easy
rollover via Index State Management. The underlying backing indices are named
`.ds-fluentbit-logs-*` and are managed by OpenSearch for you.

The `opensearch-setup` container also installs an
[Index State Management (ISM)](https://opensearch.org/docs/latest/im-plugin/ism/index/)
policy ([`opensearch/ism-policy.json`](opensearch/ism-policy.json)) that gives
the data stream **30-day retention**: each backing index rolls over once it is a
day old **or** reaches 10 GB (whichever comes first) and is deleted once it is
30 days old. The policy is attached automatically via
its `ism_template` (matching `fluentbit-logs*`), which is why it must be created
before the data stream. You can check the policy status per index with:

```bash
curl -sk -u admin:'T!mberW0lf#92' \
  "https://localhost:9200/_plugins/_ism/explain/fluentbit-logs?pretty"
```

### Try it

1. **Start the stack**:

   ```bash
   docker compose up -d && docker compose logs -f opensearch-setup
   ```

   OpenSearch starts first, the `opensearch-setup` container creates the data
   stream, and then Fluent Bit starts automatically. The committed
   [`logs/sample.log`](logs/sample.log) is picked up right away, so you'll have
   some records within a few seconds.

   You can watch the setup step complete with:

   ```bash
   docker compose logs -f opensearch-setup
   ```

2. **Log lines are generated automatically**: a `log-generator` container runs
   [`generate-logs.sh`](generate-logs.sh) continuously (one line per second),
   appending correctly-formatted lines to `logs/generated.log` so there's a
   steady stream of data to view in Dashboards. Stop it with:

   ```bash
   docker compose stop log-generator
   ```

   You can also run the script manually (e.g. from another machine, or to
   generate a fixed batch instead of an endless stream):

   ```bash
   ./generate-logs.sh          # one line per second until you press Ctrl-C
   ./generate-logs.sh 20       # 20 lines, then stop
   ./generate-logs.sh 20 0.2   # 20 lines, one every 0.2s
   ```

   You can also just drop your own `*.log` files into the `logs/` directory.

3. **View the logs in OpenSearch Dashboards**:

   1. Open <http://localhost:5601> and log in (admin/T!mberW0lf#92).
   2. One time setup:
      1. Go to **Dashboards Management → Index patterns → Create index pattern**.
      2. Enter `fluentbit-logs` as the pattern, then press 'Next step'.
      3. Select `@timestamp` as the time field. Press 'Create index pattern'.
   3. Open **Discover** to browse the parsed `level` and `message` fields. Select 2026-08-12 whole day to see the sample log entries.

4. **Check Fluent Bit's own logs** if records don't show up:

   ```bash
   docker compose logs fluent-bit
   ```

   or see generated log entries being processed live:

   ```bash
   docker compose logs -f fluent-bit
   ```

## Clean up

```bash
docker compose down -v
```

Note: this will also clean up the data that you have imported. If you want to keep that data, leave out the '-v' from the command.
