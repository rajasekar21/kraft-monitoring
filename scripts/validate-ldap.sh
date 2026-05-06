#!/usr/bin/env bash
set -euo pipefail

: "${LDAP_URI:?Set LDAP_URI, for example ldaps://ldap-01.example.com:636}"
: "${LDAP_BIND_DN:?Set LDAP_BIND_DN}"
: "${LDAP_USER_BASE:?Set LDAP_USER_BASE}"
: "${LDAP_GROUP_BASE:?Set LDAP_GROUP_BASE}"
: "${LDAP_TEST_USER:?Set LDAP_TEST_USER}"
: "${LDAP_TEST_GROUP:?Set LDAP_TEST_GROUP}"

LDAP_USER_FILTER="${LDAP_USER_FILTER:-uid=${LDAP_TEST_USER}}"
LDAP_GROUP_FILTER="${LDAP_GROUP_FILTER:-cn=${LDAP_TEST_GROUP}}"

echo "Validating LDAP user search against ${LDAP_URI}"
ldapsearch -H "${LDAP_URI}" -D "${LDAP_BIND_DN}" -W -b "${LDAP_USER_BASE}" "${LDAP_USER_FILTER}" dn

echo "Validating LDAP group search against ${LDAP_URI}"
ldapsearch -H "${LDAP_URI}" -D "${LDAP_BIND_DN}" -W -b "${LDAP_GROUP_BASE}" "${LDAP_GROUP_FILTER}" dn member
