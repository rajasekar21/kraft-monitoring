# AKHQ + LDAP + Kafka ACLs on Ubuntu Bare Metal

This repository contains a reference deployment layout for running AKHQ on Ubuntu bare metal servers with an existing LDAP or Active Directory setup and Kafka KRaft ACL enforcement.

The preferred installation model is a **versioned tar/JAR deployment managed by systemd**. This keeps upgrades simple: place a new AKHQ artifact under `/opt/akhq/releases/<version>`, move the `/opt/akhq/current` symlink, and restart the service. AKHQ publishes a standalone JAR release; if your organization requires `.deb`, package the same directory layout into an internal Debian package.

## Repository Layout

```text
configs/
  akhq/
    application.yml
    akhq.env.example
  kafka/
    admin-client.properties
    server-kraft-acl.properties
  systemd/
    akhq.service
scripts/
  install-akhq-tar.sh
  upgrade-akhq-tar.sh
  apply-kafka-acls.sh
  validate-ldap.sh
```

## Target Architecture

```text
User browser
  -> HTTPS reverse proxy or load balancer
  -> AKHQ on Ubuntu bare metal
  -> Existing LDAP / Active Directory for authentication and groups
  -> Kafka bootstrap servers
  -> Kafka StandardAuthorizer ACLs enforce broker-side permissions
```

AKHQ RBAC controls the UI. Kafka ACLs remain the hard authorization boundary.

## Why AKHQ Was Selected

AKHQ is selected as the Kafka operations UI because it gives the right balance of operational capability, RBAC maturity, LDAP integration, and deployment simplicity for Ubuntu bare metal.

| Tool | Strength | Limitation for This Use Case | Decision |
| --- | --- | --- | --- |
| AKHQ | Kafka UI, LDAP/RBAC, multi-cluster support, topic browsing, consumer groups, ACL visibility, Schema Registry and Kafka Connect support | Requires careful RBAC and Kafka ACL design | Selected |
| Kafdrop | Simple read-focused Kafka UI | Limited enterprise RBAC and governance controls | Not selected for production RBAC use |
| Kafbat UI / Kafka UI | Modern Kafka UI with broad Kafka visibility | Good option, but AKHQ configuration model is simpler for LDAP group to role mapping in this design | Alternative |
| Burrow | Strong consumer lag health evaluation | Not a general Kafka administration or RBAC UI | Complementary only |
| Prometheus exporters | Excellent metrics collection | No human Kafka operations UI, no LDAP/RBAC workflow | Complementary only |
| Grafana | Excellent dashboards and alerting | Observability layer only; does not manage Kafka resources | Complementary only |
| Cruise Control | Broker balancing and optimization | Higher operational complexity; not needed for initial monitoring/admin UI | Future large-cluster option |
| CMAK / Kafka Manager | Historical Kafka management UI | ZooKeeper-era assumptions and weaker KRaft fit | Avoid for KRaft |

Architectural reasons:

- AKHQ supports LDAP-backed authentication and group-based RBAC, which matches the existing enterprise identity model.
- AKHQ can restrict UI actions by role, topic pattern, and cluster, which supports least privilege access.
- AKHQ works as a standalone Java service, making it suitable for Ubuntu bare metal with `systemd`.
- AKHQ can be deployed through a versioned JAR/tar layout, which keeps upgrades and rollbacks simple.
- AKHQ covers operational workflows beyond dashboards: topics, consumer groups, offsets, topic data, ACLs, Schema Registry, and Kafka Connect.
- AKHQ complements Kafka ACLs instead of replacing them. The UI controls what users can attempt, while Kafka enforces what is actually allowed.
- AKHQ avoids the heavier automation footprint of Cruise Control while still giving operators useful day-to-day Kafka visibility.

Final tool positioning:

```text
AKHQ                 -> Kafka operations UI with LDAP/RBAC
Kafka ACLs           -> broker-side authorization
Prometheus/Grafana   -> metrics, dashboards, alerts
Burrow or exporter   -> optional consumer lag specialization
Cruise Control       -> optional future balancing and optimization
```

## Ubuntu Installation Pattern

Recommended server path layout:

```text
/opt/akhq/
  releases/
    0.25.1/
      akhq.jar
    0.26.0/
      akhq.jar
  current -> /opt/akhq/releases/0.26.0

/etc/akhq/
  application.yml
  akhq.env
  certs/

/var/log/akhq/
```

Install Java and base packages:

```bash
sudo apt-get update
sudo apt-get install -y openjdk-17-jre-headless ldap-utils curl ca-certificates
```

Install AKHQ from a downloaded release artifact:

```bash
sudo ./scripts/install-akhq-tar.sh /tmp/akhq.jar 0.26.0
sudo install -o root -g akhq -m 0640 configs/akhq/application.yml /etc/akhq/application.yml
sudo install -o root -g akhq -m 0640 configs/akhq/akhq.env.example /etc/akhq/akhq.env
sudo install -o root -g root -m 0644 configs/systemd/akhq.service /etc/systemd/system/akhq.service
sudo systemctl daemon-reload
sudo systemctl enable --now akhq
```

Upgrade later:

```bash
sudo ./scripts/upgrade-akhq-tar.sh /tmp/akhq-new.jar 0.27.0
sudo systemctl status akhq
```

## Debian Package Option

Use the same layout for an internal `.deb` if your operations team prefers package-based rollbacks and inventory.

Suggested package contents:

```text
/opt/akhq/releases/<version>/akhq.jar
/etc/systemd/system/akhq.service
```

Keep `/etc/akhq/application.yml` and `/etc/akhq/akhq.env` as managed configuration files, not overwritten on package upgrade. This avoids losing LDAP, Kafka, and secret settings during upgrades.

## LDAP Configuration Scope

This repo assumes LDAP already exists. Configure only:

- LDAP URL, preferably `ldaps://`.
- LDAP bind DN and password for AKHQ lookup.
- User search base.
- Group search base.
- Group membership filter.
- LDAP group to AKHQ group mapping.

See [configs/akhq/application.yml](configs/akhq/application.yml).

## RBAC Model

| LDAP Group | AKHQ Group | Access |
| --- | --- | --- |
| `kafka-prod-viewers` | `prod-viewer` | Read-only topics, brokers, consumer groups |
| `kafka-prod-developers` | `prod-developer` | Read approved app topics and approved non-sensitive data |
| `kafka-prod-operators` | `prod-operator` | Consumer group and offset operations for approved apps |
| `kafka-security-auditors` | `security-auditor` | Read-only audit and ACL visibility |
| `kafka-platform-admins` | `platform-admin` | Restricted platform administration |

Default access is `no-roles`, so unmapped LDAP users receive no AKHQ permissions.

## Kafka KRaft ACL Enforcement

On Kafka KRaft nodes, enable the KRaft-compatible authorizer:

```properties
authorizer.class.name=org.apache.kafka.metadata.authorizer.StandardAuthorizer
super.users=User:kafka_admin;User:akhq_admin
allow.everyone.if.no.acl.found=false
```

See [configs/kafka/server-kraft-acl.properties](configs/kafka/server-kraft-acl.properties).

Apply example ACLs after adjusting principals and topic prefixes:

```bash
export KAFKA_HOME=/opt/kafka
export BOOTSTRAP_SERVERS=kafka-01.example.com:9093
export ADMIN_CONFIG=/etc/kafka/admin-client.properties
sudo install -o root -g root -m 0600 configs/kafka/admin-client.properties /etc/kafka/admin-client.properties
./scripts/apply-kafka-acls.sh
```

## Validation

Validate LDAP connectivity:

```bash
LDAP_URI="ldaps://ldap-01.example.com:636" \
LDAP_BIND_DN="cn=akhq-reader,ou=service-accounts,dc=example,dc=com" \
LDAP_USER_BASE="ou=users,dc=example,dc=com" \
LDAP_GROUP_BASE="ou=groups,dc=example,dc=com" \
LDAP_TEST_USER="test.user" \
LDAP_TEST_GROUP="kafka-prod-viewers" \
./scripts/validate-ldap.sh
```

Validate AKHQ:

```bash
sudo systemctl status akhq
sudo journalctl -u akhq -f
curl -I http://localhost:8080
```

Validate access:

- Viewer can see approved topics but cannot browse sensitive data.
- Developer can browse only approved topic prefixes.
- Operator can manage approved consumer groups and offsets.
- Auditor can view ACLs but cannot change them.
- Platform admin can perform admin actions.
- Removing Kafka ACLs from the AKHQ Kafka principal causes broker-side denial even if the UI allows the click.

## Hardening Checklist

- Use LDAPS.
- Use SASL_SSL or mTLS for Kafka.
- Keep `akhq.security.default-group: no-roles`.
- Keep `allow.everyone.if.no.acl.found=false`.
- Store secrets in `/etc/akhq/akhq.env` or a secret manager, never in Git.
- Restrict `/etc/akhq/akhq.env` to `0640`.
- Put AKHQ behind HTTPS.
- Restrict direct access to port `8080`.
- Separate production and non-production AKHQ instances where possible.
- Block or mask sensitive topic payload fields by default.
- Audit AKHQ actions to a Kafka audit topic.

## References

- AKHQ installation documentation: https://akhq.io/docs/installation.html
- AKHQ authentication documentation: https://akhq.io/docs/configuration/authentifications/
- AKHQ LDAP documentation: https://akhq.io/docs/configuration/authentifications/ldap.html
- AKHQ groups and roles documentation: https://akhq.io/docs/configuration/authentifications/groups.html
- AKHQ configuration documentation: https://akhq.io/docs/configuration/akhq.html
- Apache Kafka authorization and ACLs: https://kafka.apache.org/42/security/authorization-and-acls/
