# KRaft Monitoring: AKHQ + LDAP + Kafka ACLs on Bare Metal

This guide describes a production-oriented bare metal deployment pattern for using AKHQ as the Kafka operations UI, LDAP or Active Directory as the identity source, and Kafka ACLs as the broker-side authorization boundary.

The intended outcome is:

- Users authenticate to AKHQ with LDAP credentials.
- LDAP groups are mapped to AKHQ RBAC groups.
- AKHQ controls what users can see or click in the UI.
- Kafka ACLs still enforce what Kafka actually allows.
- Sensitive topic data is blocked or masked by default.
- Changes are auditable and managed through configuration.

## Architecture

```text
User browser
  -> HTTPS reverse proxy
  -> AKHQ on bare metal
  -> LDAP / Active Directory for login and group lookup
  -> Kafka bootstrap servers
  -> Kafka ACL authorizer enforces broker-side access

Prometheus / Grafana
  -> separate monitoring path for metrics and alerts
```

Use AKHQ for human Kafka operations. Use Kafka ACLs as the mandatory security control. AKHQ RBAC is not a replacement for Kafka authorization.

## Recommended Bare Metal Layout

Example hosts:

| Host | Purpose |
| --- | --- |
| `kafka-01.example.com` | Kafka broker/controller |
| `kafka-02.example.com` | Kafka broker/controller |
| `kafka-03.example.com` | Kafka broker/controller |
| `akhq-01.example.com` | AKHQ service |
| `ldap-01.example.com` | LDAP or Active Directory |
| `monitor-01.example.com` | Prometheus / Grafana |

Example service accounts:

| Account | Purpose |
| --- | --- |
| `cn=akhq-reader,ou=service-accounts,dc=example,dc=com` | LDAP bind account used by AKHQ to search users and groups |
| `User:akhq_prod_viewer` | Kafka principal for read-only production access |
| `User:akhq_prod_operator` | Kafka principal for approved operational actions |
| `User:akhq_admin` | Kafka principal for restricted platform administration |

For high-security production environments, prefer separate AKHQ instances or separate Kafka client principals per environment. Avoid one overpowered AKHQ instance connected to all clusters with a single admin principal.

## LDAP Group Model

Create LDAP groups that match operational responsibility, not individual users.

| LDAP Group | AKHQ Group | Intended Access |
| --- | --- | --- |
| `kafka-prod-viewers` | `prod-viewer` | View production topics, brokers, partitions, consumer groups |
| `kafka-prod-developers` | `prod-developer` | View approved app topics and browse approved non-sensitive data |
| `kafka-prod-operators` | `prod-operator` | Manage consumer groups and offsets for approved apps |
| `kafka-platform-admins` | `platform-admin` | Administer Kafka through tightly controlled access |
| `kafka-security-auditors` | `security-auditor` | Read-only compliance and audit visibility |

Recommended default:

```text
No LDAP group membership = no AKHQ access
```

## Kafka KRaft ACL Prerequisites

On every Kafka node in a KRaft cluster, enable the KRaft-compatible authorizer:

```properties
authorizer.class.name=org.apache.kafka.metadata.authorizer.StandardAuthorizer
super.users=User:kafka_admin;User:akhq_admin
allow.everyone.if.no.acl.found=false
```

Notes:

- `StandardAuthorizer` stores ACLs in the KRaft metadata log.
- Keep `allow.everyone.if.no.acl.found=false` for production.
- Use a small, audited `super.users` list.
- Kafka principal names are case sensitive.
- If using mTLS, the principal is commonly derived from the certificate subject.
- If using SASL/SCRAM or SASL/OAUTHBEARER, the principal is derived from the authenticated username or token subject.

## AKHQ Installation on Bare Metal

1. Create a dedicated OS user.

```bash
sudo useradd --system --home /opt/akhq --shell /sbin/nologin akhq
sudo mkdir -p /opt/akhq /etc/akhq /var/log/akhq
sudo chown -R akhq:akhq /opt/akhq /etc/akhq /var/log/akhq
```

2. Install Java 17 or the Java version required by your AKHQ release.

```bash
java -version
```

3. Download the AKHQ release artifact from the AKHQ GitHub releases page and place it under `/opt/akhq`.

```bash
sudo install -o akhq -g akhq -m 0644 akhq.jar /opt/akhq/akhq.jar
```

4. Store runtime configuration in `/etc/akhq/application.yml`.

Do not store LDAP bind passwords or Kafka secrets directly in Git. Use environment variables, a local secret file with strict permissions, or your enterprise secret manager.

## AKHQ LDAP and RBAC Configuration

Sample `/etc/akhq/application.yml`:

```yaml
micronaut:
  security:
    enabled: true
    token:
      jwt:
        signatures:
          secret:
            generator:
              secret: "${AKHQ_JWT_SECRET}"
    ldap:
      default:
        enabled: true
        context:
          server: "ldaps://ldap-01.example.com:636"
          managerDn: "cn=akhq-reader,ou=service-accounts,dc=example,dc=com"
          managerPassword: "${LDAP_MANAGER_PASSWORD}"
        search:
          base: "ou=users,dc=example,dc=com"
          attributes:
            - "cn"
        groups:
          enabled: true
          base: "ou=groups,dc=example,dc=com"
          filter: "member={0}"

akhq:
  connections:
    prod-kraft:
      properties:
        bootstrap.servers: "kafka-01.example.com:9093,kafka-02.example.com:9093,kafka-03.example.com:9093"
        security.protocol: SASL_SSL
        sasl.mechanism: SCRAM-SHA-512
        sasl.jaas.config: "org.apache.kafka.common.security.scram.ScramLoginModule required username=\"akhq_prod_operator\" password=\"${KAFKA_AKHQ_PASSWORD}\";"
        ssl.truststore.location: "/etc/akhq/certs/kafka.truststore.jks"
        ssl.truststore.password: "${KAFKA_TRUSTSTORE_PASSWORD}"

  security:
    default-group: no-roles

    roles:
      topic-reader:
        - resources: [ "TOPIC" ]
          actions: [ "READ", "READ_CONFIG" ]
        - resources: [ "CONSUMER_GROUP" ]
          actions: [ "READ" ]
        - resources: [ "NODE" ]
          actions: [ "READ" ]

      topic-data-reader:
        - resources: [ "TOPIC_DATA" ]
          actions: [ "READ" ]

      consumer-operator:
        - resources: [ "CONSUMER_GROUP" ]
          actions: [ "READ", "UPDATE_OFFSET", "DELETE_OFFSET" ]

      topic-operator:
        - resources: [ "TOPIC" ]
          actions: [ "READ", "CREATE", "UPDATE", "READ_CONFIG", "ALTER_CONFIG" ]
        - resources: [ "CONSUMER_GROUP" ]
          actions: [ "READ", "UPDATE_OFFSET" ]

      acl-reader:
        - resources: [ "ACL" ]
          actions: [ "READ" ]

      akhq-platform-admin:
        - resources: [ "TOPIC", "TOPIC_DATA", "CONSUMER_GROUP", "CONNECT_CLUSTER", "CONNECTOR", "SCHEMA", "NODE", "ACL" ]
          actions: [ "READ", "CREATE", "UPDATE", "DELETE", "READ_CONFIG", "ALTER_CONFIG", "UPDATE_OFFSET", "DELETE_OFFSET" ]

    groups:
      prod-viewer:
        - role: topic-reader
          patterns: [ "prod\\..*" ]
          clusters: [ "prod-kraft" ]

      prod-developer:
        - role: topic-reader
          patterns: [ "prod\\.app\\..*" ]
          clusters: [ "prod-kraft" ]
        - role: topic-data-reader
          patterns: [ "prod\\.app\\.public\\..*" ]
          clusters: [ "prod-kraft" ]

      prod-operator:
        - role: topic-reader
          patterns: [ "prod\\.app\\..*" ]
          clusters: [ "prod-kraft" ]
        - role: consumer-operator
          patterns: [ "prod\\.app\\..*" ]
          clusters: [ "prod-kraft" ]

      security-auditor:
        - role: topic-reader
          patterns: [ "prod\\..*" ]
          clusters: [ "prod-kraft" ]
        - role: acl-reader
          clusters: [ "prod-kraft" ]

      platform-admin:
        - role: akhq-platform-admin
          patterns: [ ".*" ]
          clusters: [ "prod-kraft" ]

    ldap:
      groups:
        - name: kafka-prod-viewers
          groups:
            - prod-viewer
        - name: kafka-prod-developers
          groups:
            - prod-developer
        - name: kafka-prod-operators
          groups:
            - prod-operator
        - name: kafka-security-auditors
          groups:
            - security-auditor
        - name: kafka-platform-admins
          groups:
            - platform-admin

    data-masking:
      mode: json_mask_by_default
      json-mask-by-default:
        fields:
          - "password"
          - "secret"
          - "token"
          - "ssn"
          - "cardNumber"
          - "email"

  topic:
    internal-regexps:
      - "__consumer_offsets"
      - "_schemas"
      - ".*\\.internal\\..*"

  audit:
    enabled: true
    cluster-id: prod-kraft
    topic-name: akhq.audit
```

Important:

- Enable `micronaut.security.enabled`.
- Set `akhq.security.default-group: no-roles`.
- Set `micronaut.security.token.jwt.signatures.secret.generator.secret`; otherwise group restrictions may only be enforced in the UI path instead of the API path.
- Keep AKHQ behind HTTPS.
- Restrict direct network access to the AKHQ port.

## Systemd Service

Create `/etc/systemd/system/akhq.service`:

```ini
[Unit]
Description=AKHQ Kafka UI
After=network-online.target
Wants=network-online.target

[Service]
User=akhq
Group=akhq
WorkingDirectory=/opt/akhq
EnvironmentFile=/etc/akhq/akhq.env
ExecStart=/usr/bin/java -Dmicronaut.config.files=/etc/akhq/application.yml -jar /opt/akhq/akhq.jar
Restart=on-failure
RestartSec=10
SuccessExitStatus=143
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
```

Example `/etc/akhq/akhq.env`:

```bash
AKHQ_JWT_SECRET=replace-with-strong-random-secret-at-least-256-bits
LDAP_MANAGER_PASSWORD=replace-with-ldap-bind-password
KAFKA_AKHQ_PASSWORD=replace-with-kafka-sasl-password
KAFKA_TRUSTSTORE_PASSWORD=replace-with-truststore-password
```

Secure the files:

```bash
sudo chown root:akhq /etc/akhq/application.yml /etc/akhq/akhq.env
sudo chmod 0640 /etc/akhq/application.yml /etc/akhq/akhq.env
sudo systemctl daemon-reload
sudo systemctl enable --now akhq
sudo systemctl status akhq
```

## Kafka ACL Implementation

Create a client properties file for the Kafka admin user:

`/etc/kafka/admin-client.properties`

```properties
security.protocol=SASL_SSL
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="kafka_admin" password="replace-me";
ssl.truststore.location=/etc/kafka/certs/kafka.truststore.jks
ssl.truststore.password=replace-me
```

Example ACLs for AKHQ principals:

```bash
KAFKA_HOME=/opt/kafka
BOOTSTRAP=kafka-01.example.com:9093
ADMIN_CONFIG=/etc/kafka/admin-client.properties

$KAFKA_HOME/bin/kafka-acls.sh \
  --bootstrap-server "$BOOTSTRAP" \
  --command-config "$ADMIN_CONFIG" \
  --add \
  --allow-principal User:akhq_prod_viewer \
  --operation Describe \
  --topic 'prod.' \
  --resource-pattern-type prefixed

$KAFKA_HOME/bin/kafka-acls.sh \
  --bootstrap-server "$BOOTSTRAP" \
  --command-config "$ADMIN_CONFIG" \
  --add \
  --allow-principal User:akhq_prod_viewer \
  --operation Describe \
  --group 'prod.' \
  --resource-pattern-type prefixed

$KAFKA_HOME/bin/kafka-acls.sh \
  --bootstrap-server "$BOOTSTRAP" \
  --command-config "$ADMIN_CONFIG" \
  --add \
  --allow-principal User:akhq_prod_operator \
  --operation Describe \
  --operation Read \
  --topic 'prod.app.' \
  --resource-pattern-type prefixed

$KAFKA_HOME/bin/kafka-acls.sh \
  --bootstrap-server "$BOOTSTRAP" \
  --command-config "$ADMIN_CONFIG" \
  --add \
  --allow-principal User:akhq_prod_operator \
  --operation Describe \
  --operation Read \
  --group 'prod.app.' \
  --resource-pattern-type prefixed

$KAFKA_HOME/bin/kafka-acls.sh \
  --bootstrap-server "$BOOTSTRAP" \
  --command-config "$ADMIN_CONFIG" \
  --add \
  --allow-principal User:akhq_admin \
  --operation All \
  --cluster
```

Review ACLs:

```bash
$KAFKA_HOME/bin/kafka-acls.sh \
  --bootstrap-server "$BOOTSTRAP" \
  --command-config "$ADMIN_CONFIG" \
  --list
```

## Access Matrix

| Action | Viewer | Developer | Operator | Security Auditor | Platform Admin |
| --- | --- | --- | --- | --- | --- |
| View topics | Yes | Yes | Yes | Yes | Yes |
| View consumer groups | Yes | Yes | Yes | Yes | Yes |
| Browse topic data | No | Approved prefixes only | Approved prefixes only | No | Yes |
| Reset consumer offsets | No | No | Approved groups only | No | Yes |
| Create topics | No | No | Optional, restricted | No | Yes |
| Delete topics | No | No | No | No | Yes |
| Alter topic configs | No | No | Optional, restricted | No | Yes |
| View ACLs | No | No | No | Yes | Yes |
| Change ACLs | No | No | No | No | Yes |

## Validation Steps

1. Validate LDAP login.

```bash
ldapsearch -H ldaps://ldap-01.example.com:636 \
  -D "cn=akhq-reader,ou=service-accounts,dc=example,dc=com" \
  -W \
  -b "ou=users,dc=example,dc=com" "(cn=test.user)"
```

2. Validate LDAP group lookup.

```bash
ldapsearch -H ldaps://ldap-01.example.com:636 \
  -D "cn=akhq-reader,ou=service-accounts,dc=example,dc=com" \
  -W \
  -b "ou=groups,dc=example,dc=com" "(cn=kafka-prod-viewers)"
```

3. Login to AKHQ as a viewer.

Expected:

- Can see allowed production topics.
- Cannot browse sensitive topic data.
- Cannot create, delete, or alter topics.

4. Login to AKHQ as an operator.

Expected:

- Can see approved app topics.
- Can manage approved consumer groups.
- Cannot change ACLs.
- Cannot delete production topics.

5. Test broker-side denial.

Temporarily remove a Kafka ACL from the AKHQ service principal and retry the same UI action. The UI action should fail because Kafka rejects it.

6. Confirm audit events.

```bash
$KAFKA_HOME/bin/kafka-console-consumer.sh \
  --bootstrap-server "$BOOTSTRAP" \
  --consumer.config "$ADMIN_CONFIG" \
  --topic akhq.audit \
  --from-beginning
```

## Operational Hardening

- Put AKHQ behind an HTTPS reverse proxy.
- Allow inbound AKHQ traffic only from corporate networks or VPN.
- Allow AKHQ outbound traffic only to LDAP, Kafka, Schema Registry, Kafka Connect, and audit destinations.
- Use LDAPS, not plain LDAP.
- Use SASL_SSL or mTLS for Kafka access.
- Rotate LDAP bind and Kafka service account credentials.
- Keep topic data browsing disabled by default.
- Mask PII and secrets in message payloads.
- Require pull requests for AKHQ RBAC configuration changes.
- Keep production and non-production AKHQ deployments separate.
- Alert on failed AKHQ logins, Kafka authorization failures, and ACL changes.

## Troubleshooting

| Symptom | Likely Cause | Fix |
| --- | --- | --- |
| All users have admin access | Security disabled or default group is `admin` | Set `micronaut.security.enabled=true` and `akhq.security.default-group=no-roles` |
| UI hides actions but API still allows them | Missing AKHQ JWT secret | Set `micronaut.security.token.jwt.signatures.secret.generator.secret` |
| User logs in but sees nothing | LDAP group not mapped to AKHQ group | Check `akhq.security.ldap.groups` and LDAP group names |
| AKHQ shows topic but action fails | Kafka ACL denies service principal | Add or correct Kafka ACLs |
| Topic data is visible unexpectedly | Broad `TOPIC_DATA` role or pattern | Narrow patterns and enable masking |
| ACL changes fail in AKHQ | AKHQ principal lacks cluster `Alter` ACL | Grant only to admin principal, or keep ACL changes outside AKHQ |

## References

- AKHQ authentication documentation: https://akhq.io/docs/configuration/authentifications/
- AKHQ LDAP documentation: https://akhq.io/docs/configuration/authentifications/ldap.html
- AKHQ groups and roles documentation: https://akhq.io/docs/configuration/authentifications/groups.html
- AKHQ configuration documentation: https://akhq.io/docs/configuration/akhq.html
- Apache Kafka authorization and ACLs: https://kafka.apache.org/42/security/authorization-and-acls/
