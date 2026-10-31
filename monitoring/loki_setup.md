# Log aggregation with Grafana Loki

This stack ships the NGINX container's logs (deployed by Nomad) into Loki and lets me query them from Grafana.

## Stack

| Service  | Image                     | Purpose                                   |
|----------|---------------------------|-------------------------------------------|
| Loki     | grafana/loki:3.4.2      | Stores and indexes the logs               |
| Promtail | grafana/promtail:3.4.2  | Finds the NGINX container and ships logs  |
| Grafana  | grafana/grafana:11.5.2  | Explore UI, Loki is provisioned as the default data source |

Files in this folder:

- docker-compose.yaml runs the three services with host networking.
- loki-config.yaml is the Loki configuration (filesystem storage, TSDB schema v13).
- promtail-config.yaml is the Promtail configuration (Docker service discovery and labels).

## How I started the stack

1. Consul and Nomad run in dev mode and the Nomad job is deployed (see the Nomad section of the README):

   bash
   nohup consul agent -dev > /tmp/consul.log 2>&1 &
   sudo nohup nomad agent -dev > /tmp/nomad.log 2>&1 &
   nomad job run nomad/nginx-app.nomad.hcl
   

2. Start Loki, Promtail and Grafana:

   bash
   docker compose -f monitoring/docker-compose.yaml up -d
   docker compose -f monitoring/docker-compose.yaml ps
   curl -s http://localhost:3100/ready
   

   Right after startup /ready answers Ingester not ready: waiting for 15s after being ready. About 20 seconds later it answers ready.

3. Find the host port that Nomad assigned to the NGINX container and send some traffic, including a deliberately missing path:

   bash
   PORT=$(docker ps --filter "name=nginx-" --format '{{.Ports}}' | grep -o '127.0.0.1:[0-9]*->8080/tcp' | head -1 | cut -d: -f2 | cut -d- -f1)
   for i in 1 2 3 4 5; do curl -s -o /dev/null http://localhost:$PORT/; done
   for i in 1 2 3; do curl -s -o /dev/null -w "%{http_code}\n" http://localhost:$PORT/does-not-exist; done
   

   The missing path returned 404 three times.

4. Open Grafana on port 3000 (Ports tab, Open in Browser), then Explore, data source Loki, time range Last 1 hour.

## How Promtail finds the logs

Promtail uses docker_sd_configs on the Docker socket. A keep rule only passes containers whose name looks like a Nomad allocation container (nginx-<alloc-id>), so Loki, Promtail and Grafana logs are not mixed in.

## Label set

| Label            | Value                          | Where it comes from                       |
|------------------|--------------------------------|-------------------------------------------|
| job            | nginx-app                    | static, set in promtail-config.yaml     |
| service        | nginx-app                    | static, set in promtail-config.yaml     |
| container      | nginx-<allocation id>        | Docker container name                     |
| nomad_alloc_id | <allocation id>              | taken from the container name            |

Loki also added service_name and detected_level on its own.

## LogQL queries and results

*1. All logs of the application*


{job="nginx-app"}


Result: 16 lines. That was 5 requests for GET / with status 200, 3 requests for GET /does-not-exist with status 404, and the NGINX container startup messages. The labels container, job, nomad_alloc_id and service showed up as common labels.

*2. Only the non-200 access log lines*


{job="nginx-app"} |~ "HTTP/1.1\" [45][0-9]{2} "


Result: 3 lines, all GET /does-not-exist HTTP/1.1" 404. The 200 requests and the startup messages are filtered out, which confirms that ingestion works and that the stream can be narrowed down to error responses.

Screenshot of this query in Grafana Explore:

![Grafana Explore non-200 query](../docs/screenshots/grafana-explore-non200.png)

## Problems I hit and how I resolved them

1. *Loki returned empty results at first.*
   - Promtail logged error sending batch ... context deadline exceeded when pushing to http://loki:3100.
   - From the host, Loki worked: /ready returned ready, a manual push returned 204, and the pushed test line came back from a query.
   - A test container on the compose network timed out reaching http://loki:3100/ready (curl exit code 28).
   - Fix: I switched the three services to network_mode: host and changed the Promtail client URL to http://localhost:3100/loki/api/v1/push. After that, no more push errors, and the NGINX logs showed up in Loki.
   - I did not find the root cause of the compose network timeout in Codespaces.

2. */ready said Ingester not ready: waiting for 15s after being ready.*
   - This is Loki's normal start delay. Waiting about 20 seconds fixed it.

3. *After a Codespace restart docker compose up -d failed with RWLayer of container ... is unexpectedly nil.*
   - The old monitoring containers were left in a broken state after the restart.
   - Fix: removed them with docker rm -f monitoring-loki-1 monitoring-promtail-1 monitoring-grafana-1, pulled the three images again and ran docker compose up -d.

4. *The first non-200 query in Grafana failed with parse error ... unexpected <, expecting STRING.*
   - I had used the pattern parser and its template was not wrapped in backticks.
   - Fix: replaced it with a plain regex line filter (query 2 above).

## Known limitations

- Host networking and anonymous admin access in Grafana are fine for a demo, not for production.
- Loki uses local filesystem storage with no retention policy configured.
- Nomad runs in dev mode, so jobs are gone after a restart and have to be started again.