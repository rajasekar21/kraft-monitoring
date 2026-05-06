#!/usr/bin/env bash
set -euo pipefail

KAFKA_HOME="${KAFKA_HOME:-/opt/kafka}"
BOOTSTRAP_SERVERS="${BOOTSTRAP_SERVERS:-kafka-01.example.com:9093}"
ADMIN_CONFIG="${ADMIN_CONFIG:-/etc/kafka/admin-client.properties}"

KAFKA_ACLS="${KAFKA_HOME}/bin/kafka-acls.sh"

if [[ ! -x "${KAFKA_ACLS}" ]]; then
  echo "kafka-acls.sh not found or not executable: ${KAFKA_ACLS}" >&2
  exit 1
fi

"${KAFKA_ACLS}" --bootstrap-server "${BOOTSTRAP_SERVERS}" --command-config "${ADMIN_CONFIG}" \
  --add --allow-principal User:akhq_prod_viewer \
  --operation Describe \
  --topic 'prod.' --resource-pattern-type prefixed

"${KAFKA_ACLS}" --bootstrap-server "${BOOTSTRAP_SERVERS}" --command-config "${ADMIN_CONFIG}" \
  --add --allow-principal User:akhq_prod_viewer \
  --operation Describe \
  --group 'prod.' --resource-pattern-type prefixed

"${KAFKA_ACLS}" --bootstrap-server "${BOOTSTRAP_SERVERS}" --command-config "${ADMIN_CONFIG}" \
  --add --allow-principal User:akhq_prod_operator \
  --operation Describe --operation Read \
  --topic 'prod.app.' --resource-pattern-type prefixed

"${KAFKA_ACLS}" --bootstrap-server "${BOOTSTRAP_SERVERS}" --command-config "${ADMIN_CONFIG}" \
  --add --allow-principal User:akhq_prod_operator \
  --operation Describe --operation Read \
  --group 'prod.app.' --resource-pattern-type prefixed

"${KAFKA_ACLS}" --bootstrap-server "${BOOTSTRAP_SERVERS}" --command-config "${ADMIN_CONFIG}" \
  --add --allow-principal User:akhq_admin \
  --operation All \
  --cluster

"${KAFKA_ACLS}" --bootstrap-server "${BOOTSTRAP_SERVERS}" --command-config "${ADMIN_CONFIG}" --list
