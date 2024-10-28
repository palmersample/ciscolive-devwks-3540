#!/bin/sh

if [ "x${DNS_DOMAIN}" = "x" ]; then
  echo ""
  echo "******************************************************************************"
  echo "FATAL ERROR:"
  echo "  DNS_DOMAIN environment variable not set, unable to proceed!"
  echo ""
  echo "  Ensure you completed the workshop setup task to setup the environment,"
  echo "  or supply the DNS_DOMAIN variable when calling this script."
  echo "******************************************************************************"
  echo ""
  kill -INT $$
fi

# Create a persistent env file in case of connection error to the LL2
# environment - can restore access without workshop interruption by sourcing
# the filename specified here.
SAVED_ENV_FILE="./workshop-env"


[ ! -d "./ssh" ] && mkdir ./ssh
NETCONF_SSH_CONFIG_FILE="./ssh/netconf_ssh_config"
SSH_CONFIG_FILE="./ssh/ssh_config"

TIMEOUT_CMD=`which timeout`

ERROR_COUNT=0
ERROR_MESSAGES=""

TIMEOUT_CMD=`which timeout`
if [ $? -eq 0 ]; then
  TIMEOUT_CMD="${TIMEOUT_CMD} 5 "
else
  TIMEOUT_CMD=""
fi

test_proxy()
{
  printf "%40s" "Proxy status: "
  PROXY_CONNECT_RESULT=$(echo "" | ${TIMEOUT_CMD}openssl s_client -connect ${PROXY_DNS_NAME}:443 -tls1_2 2>&1 > /dev/null)
  if [ $? -ne 0 ] ; then
    ERROR_COUNT=${ERROR_COUNT+1}
    ERROR_MESSAGES="${ERROR_MESSAGES}\t- Unable to contact the proxy server.\n"
    echo "FAIL"
  else
    echo "OK"
  fi
}

test_vault()
{
  INIT_TARGET="true"
  SEAL_TARGET="false"
  UI_TARGET=200

  printf "%40s" "Vault Web UI status: "
  VAULT_UI_RESULT=$(${TIMEOUT_CMD}curl -s -o /dev/null -w "%{http_code}" "${VAULT_URL}/ui/vault/auth?with=token")

  if [ "x${VAULT_UI_RESULT}" = "x${UI_TARGET}" ]; then
    echo "OK"
  else
    ERROR_COUNT=${ERROR_COUNT+1}
    ERROR_MESSAGES="${ERROR_MESSAGES}\t- The Vault UI is not accessible.\n"
    echo "FAIL"
  fi

  printf "%40s" "Vault API status: "
  VAULT_API_RESULT=$(${TIMEOUT_CMD}curl -fsv \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    "${VAULT_URL}/v1/sys/seal-status" 2>&1)

  if [ $? -ne 0 ] ; then
    ERROR_COUNT=${ERROR_COUNT+1}
    ERROR_MESSAGES="${ERROR_MESSAGES}\t- The Vault API is not accessible.\n"
    echo "FAIL"
  else
    echo "OK"

    INIT_STATUS=$(grep -o '"'"initialized"'"\s*:\s*\(true\|false\)' \
      <<<${VAULT_API_RESULT} | \
      awk -F: '{ print $2 }'
    )

    SEAL_STATUS=$(grep -o '"'"sealed"'"\s*:\s*\(true\|false\)' \
      <<<${VAULT_API_RESULT} | \
      awk -F: '{ print $2 }'
    )

    printf "%40s" "Vault initialization status: "
    if [ "x${INIT_STATUS}" = "x${INIT_TARGET}" ]; then
      echo "OK"
    else
      ERROR_COUNT=${ERROR_COUNT+1}
      ERROR_MESSAGES="${ERROR_MESSAGES}\t- The Vault server is not initialized.\n"
      echo "FAIL"
    fi

    printf "%40s" "Vault seal status: "
    if [ "x${SEAL_STATUS}" = "x${SEAL_TARGET}" ]; then
      echo "OK"
    else
      ERROR_COUNT=${ERROR_COUNT+1}
      ERROR_MESSAGES="${ERROR_MESSAGES}\t- Vault secrets are are not accessible.\n"
      echo "FAIL"
    fi

  fi
}

test_netbox()
{
  NETBOX_UI_TARGET=200

  printf "%40s" "NetBox UI status: "
  NETBOX_UI_RESULT=$(${TIMEOUT_CMD}curl -s -o /dev/null -w "%{http_code}" "${NETBOX_URL}/login/?next=/")
  if [ "x${NETBOX_UI_RESULT}" = "x${NETBOX_UI_TARGET}" ]; then
    echo "OK"
  else
    ERROR_COUNT=${ERROR_COUNT+1}
    ERROR_MESSAGES="${ERROR_MESSAGES}\t- The NetBox UI is not accessible.\n"
    echo "FAIL"
  fi

  printf "%40s" "NetBox API status: "
  NETBOX_API_RESULT=$(${TIMEOUT_CMD}curl -fsv \
    --header "Authorization: Token ${NETBOX_TOKEN}" \
    "${NETBOX_URL}/api/status/" 2>&1)

  if [ $? -ne 0 ] ; then
    ERROR_COUNT=${ERROR_COUNT+1}
    ERROR_MESSAGES="${ERROR_MESSAGES}\t- The NetBox API is not accessible.\n"
    echo "FAIL"
  else
    echo "OK"
  fi
}

test_router()
{
  # Expect an "Unauthorized" result
  RESTCONF_TARGET=401

  printf "%40s" "IOSXE SSH Status: "
  SSH_PROXY_RESULT=$(${TIMEOUT_CMD}ssh \
    -o ProxyCommand="openssl s_client -quiet -servername ${RTR_DNS_NAME} -connect ${PROXY_DNS_NAME}:${PROXY_SSH_PORT}" \
    -o 'BatchMode=yes' \
    -o 'ConnectionAttempts=1' \
    -o "StrictHostKeyChecking=no" \
    dummy@${RTR_DNS_NAME} -p 8000 2>&1 > /dev/null
  )
  SSH_STATUS=$(grep -i "permission denied" <<<${SSH_PROXY_RESULT})
  if [ $? -ne 0 ]; then
    ERROR_COUNT=${ERROR_COUNT+1}
    ERROR_MESSAGES="${ERROR_MESSAGES}\t- IOSXE SSH is not accessible.\n"
    echo "FAIL"
  else
    echo "OK"
  fi

  printf "%40s" "IOSXE NETCONF Status: "
  NETCONF_PROXY_RESULT=$(${TIMEOUT_CMD}ssh \
    -o ProxyCommand="openssl s_client -quiet -servername ${RTR_DNS_NAME} -connect ${PROXY_DNS_NAME}:${PROXY_NETCONF_PORT}" \
    -o 'BatchMode=yes' \
    -o 'ConnectionAttempts=1' \
    -o "StrictHostKeyChecking=no" \
    dummy@${RTR_DNS_NAME} \
    -p 830 NETCONF 2>&1 > /dev/null)
  NETCONF_STATUS=$(grep -i "permission denied" <<<${NETCONF_PROXY_RESULT})
  if [ $? -ne 0 ]; then
    ERROR_COUNT=${ERROR_COUNT+1}
    ERROR_MESSAGES="${ERROR_MESSAGES}\t- IOSXE NETCONF is not accessible.\n"
    echo "FAIL"
  else
    echo "OK"
  fi

  printf "%40s" "IOSXE RESTCONF Status: "
  RESTCONF_RESULT=$(${TIMEOUT_CMD}curl -s -o /dev/null -w "%{http_code}" \
    "${RTR_URL}/restconf"
  )
  if [ "x${RESTCONF_RESULT}" = "x${RESTCONF_TARGET}" ]; then
    echo "OK"
  else
    ERROR_COUNT=${ERROR_COUNT+1}
    ERROR_MESSAGES="${ERROR_MESSAGES}\t- IOSXE RESTCONF is not accessible.\n"
    echo "FAIL"
  fi
}

generate_ssh_config()
{
  printf "%40s" "NETCONF proxy: "
  # Generate NETCONF SSH Proxy Config file
  echo "Host *.${DNS_DOMAIN}" > ${NETCONF_SSH_CONFIG_FILE}
  echo "  ProxyCommand openssl s_client -quiet -servername %h -connect ${PROXY_DNS_NAME}:${PROXY_NETCONF_PORT}" >> ${NETCONF_SSH_CONFIG_FILE}
  echo "  StrictHostKeyChecking no" >> ${NETCONF_SSH_CONFIG_FILE}

  if [ -f ${NETCONF_SSH_CONFIG_FILE} ]; then
    echo "OK"
  else
    ERROR_COUNT=${ERROR_COUNT+1}
    ERROR_MESSAGES="${ERROR_MESSAGES}\t- NETCONF SSH Proxy config not created.\n"
    echo "FAIL"
  fi

  printf "%40s" "SSH proxy: "
  # Generate SSH Proxy Config file
  echo "Host *.${DNS_DOMAIN}" > ${SSH_CONFIG_FILE}
  echo "  ProxyCommand openssl s_client -quiet -servername %h -connect ${PROXY_DNS_NAME}:${PROXY_SSH_PORT}" >> ${SSH_CONFIG_FILE}
  echo "  StrictHostKeyChecking no" >> ${SSH_CONFIG_FILE}
  if [ -f ${SSH_CONFIG_FILE} ]; then
    echo "OK"
  else
    ERROR_COUNT=${ERROR_COUNT+1}
    ERROR_MESSAGES="${ERROR_MESSAGES}\t- SSH Proxy config not created.\n"
    echo "FAIL"
  fi

}

restart_caddy()
{
  printf "%40s" "Stopping log proxy: "
  CADDY_STOP_RESULT=$(${TIMEOUT_CMD}pkill caddy)
  if [ $? -le 1 ]; then
    echo "OK"
  else
    # Stopping and starting caddy should not be fatal errors -
    # for this workshop, it just means the log server won't be
    # accessible.
    echo "FAIL (NOT CRITICAL)"
  fi

  printf "%40s" "Starting log proxy: "
  CADDY_START_RESULT=$(${TIMEOUT_CMD}caddy start --config Caddyfile 2>/dev/null >/dev/null)
  if [ $? -ne 0 ]; then
    echo "FAIL (NOT CRITICAL)"
  else
    echo "OK"
  fi
}

echo "GET READY FOR YOUR CISCO LIVE WORKSHOP EXPERIENCE! :)"
echo ""

echo -n "What is your pod number? "
read POD_NUMBER
POD_NUMBER=$(echo ${POD_NUMBER} | sed 's/^0*//')

PROXY_DNS_NAME="proxy.${DNS_DOMAIN}"
PROXY_SSH_PORT=8000
PROXY_NETCONF_PORT=8300

#####
# Set defaults if Vault and NetBox vars are not defined
#
if [ "x${VAULT_URL}" = "x" ]; then
  VAULT_URL="https://pod${POD_NUMBER}-vault.${DNS_DOMAIN}"
fi

if [ "x${VAULT_TOKEN}" = "x" ]; then
  VAULT_TOKEN="secret-vault-token"
fi

if [ "x${NETBOX_URL}" = "x" ]; then
  NETBOX_URL="https://pod${POD_NUMBER}-netbox.${DNS_DOMAIN}"
fi

if [ "x${NETBOX_TOKEN}" = "x" ]; then
  NETBOX_TOKEN="ba9cded0eda0f4053cfbe1e11e33b1e0e141100e"
fi

echo "VAULT URL: ${VAULT_URL}"

RTR_DNS_NAME="pod${POD_NUMBER}-rtr.${DNS_DOMAIN}"
RTR_URL="https://${RTR_DNS_NAME}"

echo ""
echo "************************************************************************"

echo ""
echo "TEST 1: Checking connectivity to the proxy for Pod ${POD_NUMBER}"
test_proxy

echo ""
echo "TEST 2: Checking connectivity to Hashicorp Vault in Pod ${POD_NUMBER}:"
test_vault

echo ""
echo "TEST 3: Checking connectivity to NetBox in Pod ${POD_NUMBER}:"
test_netbox

echo ""
echo "TEST 4: Checking connectivity to IOSXE in Pod ${POD_NUMBER}:"
test_router

echo ""
echo "SETUP: Generate SSH configuration files for Pod ${POD_NUMBER}"
generate_ssh_config

echo ""
echo "SETUP: Restarting proxy for pyATS log server"
restart_caddy

echo ""
if [ ${ERROR_COUNT} -gt 0 ]; then
  echo "THERE WERE ERRORS IN SETUP TESTING:"
  printf "${ERROR_MESSAGES}\n"
  printf "\tPlease ask your proctor for assistance!\n"
else
  echo "ALL SETUP TASKS OK - Time to have some automation fun!"
  export POD_NUMBER=${POD_NUMBER}
  export RTR_DNS_NAME=${RTR_DNS_NAME}
  export PROXY_DNS_NAME=${PROXY_DNS_NAME}
  export PROXY_SSH_PORT=${PROXY_SSH_PORT}
  export VAULT_URL=${VAULT_URL}
  export VAULT_TOKEN=${VAULT_TOKEN}

  echo "export POD_NUMBER=${POD_NUMBER}" > ${SAVED_ENV_FILE}
  echo "export DNS_DOMAIN=${DNS_DOMAIN}" >> ${SAVED_ENV_FILE}
  echo "export VAULT_URL=${VAULT_URL}" >> ${SAVED_ENV_FILE}
  echo "export VAULT_TOKEN=${VAULT_TOKEN}" >> ${SAVED_ENV_FILE}
  echo "export PROXY_DNS_NAME=${PROXY_DNS_NAME}" >> ${SAVED_ENV_FILE}
  echo "export PROXY_SSH_PORT=${PROXY_SSH_PORT}" >> ${SAVED_ENV_FILE}
fi

echo ""