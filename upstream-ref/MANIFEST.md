# artemis-edge-demo Catalog Manifest
Source: https://github.com/tosin2013/artemis-edge-demo/tree/master
Raw base: https://raw.githubusercontent.com/tosin2013/artemis-edge-demo/master/

## Topology for Helm conversion
- 2 hub brokers (hub-01, hub-02) - OCP ActiveMQArtemis CRs
- 3 spoke brokers (spoke-01 on OCP; spoke-02/03 appear external via EndpointSlice/static scrape)
- AMQP federation spoke→hub with regional address prefixes: NY (spoke-01), NJ (spoke-02), CT (spoke-03), ALL, and hop-limited 5604
- Keycloak OIDC (JAAS DirectAccessGrants) for broker auth; PropertiesLoginModule sufficient fallback
- Prometheus Operator + ServiceMonitors + Grafana Operator dashboard
- Quarkus Camel clients: amqp-client, mqtt-client, amqp-bridge; artemis-extensions StaticHeaderPlugin

## Template placeholders
- `${KC_DOMAIN}`, `${HUB01_DOMAIN}`, `${HUB02_DOMAIN}`, `${TRUSTSTORE_PATH}`, `${KC_CLIENT_SECRET}`, `${BEARER_KC_CONFIG}`, `${DIRECT_KC_CONFIG}`

## Files on disk
All fetched contents live under this directory mirroring upstream paths.
Large files: keycloak/realm-export.json (74KB), grafana/grafana-amq-dashboard.yaml (21KB)
