#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TLS_DIR="${PROJECT_ROOT}/artemis/tls"
KC_TLS_DIR="${PROJECT_ROOT}/keycloak/tls"

mkdir -p "$TLS_DIR" "$KC_TLS_DIR"

: "${KC_DOMAIN:?KC_DOMAIN must be set}"
: "${HUB01_DOMAIN:?HUB01_DOMAIN must be set}"
: "${HUB02_DOMAIN:=${HUB01_DOMAIN}}"
: "${SPOKE01_DOMAIN:=${HUB01_DOMAIN}}"
: "${SPOKE02_DOMAIN:=${HUB01_DOMAIN}}"
: "${SPOKE03_DOMAIN:=${HUB01_DOMAIN}}"

echo "=== Generating TLS certificates ==="
echo "KC_DOMAIN:     ${KC_DOMAIN}"
echo "HUB01_DOMAIN:  ${HUB01_DOMAIN}"
echo "HUB02_DOMAIN:  ${HUB02_DOMAIN}"
echo "SPOKE01_DOMAIN: ${SPOKE01_DOMAIN}"
echo "SPOKE02_DOMAIN: ${SPOKE02_DOMAIN}"
echo "SPOKE03_DOMAIN: ${SPOKE03_DOMAIN}"

# --- Keycloak TLS ---
CN="keycloak-service"
SAN=""
SAN+="DNS:keycloak-service.svc,"
SAN+="DNS:keycloak-service.svc.cluster.local,"
SAN+="DNS:keycloak-service.keycloak.svc,"
SAN+="DNS:keycloak-service.keycloak.svc.cluster.local,"
SAN+="DNS:keycloak-ingress-keycloak.${KC_DOMAIN}"
openssl req -subj "/CN=${CN}/C=US" -addext "subjectAltName = ${SAN}" \
  -newkey rsa:2048 -nodes -keyout "${KC_TLS_DIR}/key.pem" -x509 -days 365 \
  -out "${KC_TLS_DIR}/certificate.pem"
echo "[OK] Keycloak TLS certificate"

generate_broker_tls() {
  local NAME="$1" DOMAIN="$2" BROKER_COUNT="${3:-0}"

  CN="${NAME}-broker-*-svc-rte-artemis.${DOMAIN}"
  SAN=""
  for i in $(seq 0 "${BROKER_COUNT}"); do
    SAN+="DNS:${NAME}-broker-cores-acceptor-${i}-svc-rte-artemis.${DOMAIN},"
    SAN+="DNS:${NAME}-broker-amqps-acceptor-${i}-svc-rte-artemis.${DOMAIN},"
    SAN+="DNS:${NAME}-broker-mqtts-acceptor-${i}-svc-rte-artemis.${DOMAIN},"
  done

  keytool -genkeypair -alias "broker" -keyalg RSA -dname "CN=${CN}" \
    -ext "SAN=${SAN}" \
    -keystore "${TLS_DIR}/${NAME}-broker-keystore.jks" -storepass "password" 2>/dev/null
  keytool -export -alias "broker" \
    -keystore "${TLS_DIR}/${NAME}-broker-keystore.jks" -storepass "password" \
    -file "${TLS_DIR}/${NAME}-broker-certificate.crt" 2>/dev/null
  keytool -import -noprompt -alias "keycloak" \
    -keystore "${TLS_DIR}/${NAME}-broker-truststore.jks" -storepass "password" \
    -file "${KC_TLS_DIR}/certificate.pem" 2>/dev/null
  echo "[OK] ${NAME} broker TLS"
}

# --- Hub brokers ---
generate_broker_tls "hub-01" "$HUB01_DOMAIN"
generate_broker_tls "hub-02" "$HUB02_DOMAIN"

# --- Spoke brokers ---
generate_broker_tls "spoke-01" "$SPOKE01_DOMAIN"
generate_broker_tls "spoke-02" "$SPOKE02_DOMAIN"
generate_broker_tls "spoke-03" "$SPOKE03_DOMAIN"

# Import hub certs into spoke truststores
for SPOKE in spoke-01 spoke-02 spoke-03; do
  for HUB in hub-01 hub-02; do
    keytool -import -noprompt -alias "${HUB}-broker" \
      -keystore "${TLS_DIR}/${SPOKE}-broker-truststore.jks" -storepass "password" \
      -file "${TLS_DIR}/${HUB}-broker-certificate.crt" 2>/dev/null
  done
done
echo "[OK] Hub certificates imported into spoke truststores"

# --- Client truststore ---
for BROKER in hub-01 hub-02 spoke-01 spoke-02 spoke-03; do
  keytool -import -noprompt -alias "${BROKER}-broker" \
    -keystore "${TLS_DIR}/client-truststore.jks" -storepass "password" \
    -file "${TLS_DIR}/${BROKER}-broker-certificate.crt" 2>/dev/null
done
echo "[OK] Client truststore"

echo ""
echo "=== TLS generation complete ==="
echo "Artifacts in: ${TLS_DIR}"
echo "Keycloak TLS in: ${KC_TLS_DIR}"
