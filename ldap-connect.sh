#!/bin/bash
#
# This script requires the OpenShift CLI `oc` to be installed
# as well as having a valid session (i.e. oc login).
#
# For more information about the API go to
# https://www.ibm.com/support/knowledgecenter/SSHKN6/iam/3.4.0/apis/directory_mgmt.html
#
if ! [ -x "$(command -v oc)" ]; then
    echo "oc could not be found. Please install the OpenShift CLI."
    exit 1
fi
if ! [ -x "$(command -v jq)" ]; then
    echo "jq could not be found. Please install the jq."
    exit 1
fi
whoami=$(oc whoami)
if [ -z "$whoami" ]; then
  echo "OpenShift session is not valid. Please authenticate with a cluster before using this script."
  exit 1
fi

echo "Retriving IBM Common Services hostname..."
CONSOLE_HOST=$(oc get routes -n ibm-common-services | grep cp-console | awk '{print $2}')
if [ -z "$CONSOLE_HOST" ]; then
  echo "Common Services hostname not found. Is it installed? Please check and try again later."
  exit 1
fi

echo "Retriving IBM Common Services Auth Credentials..."
CP_USERNAME=$(oc get secrets -n ibm-common-services platform-auth-idp-credentials -ojsonpath='{.data.admin_username}' | base64 --decode && echo "")
CP_PASSWORD=$(oc get secrets -n ibm-common-services platform-auth-idp-credentials -ojsonpath='{.data.admin_password}' | base64 --decode && echo "")

echo "Retriving IBM Common Services Access Token..."
ACCESS_TOKEN=$(curl -s -H "Content-Type: application/x-www-form-urlencoded;charset=UTF-8" \
-d "grant_type=password&username="$CP_USERNAME"&password="$CP_PASSWORD"&scope=openid" \
https://$CONSOLE_HOST:443/idprovider/v1/auth/identitytoken --insecure | \
jq '.access_token' | tr -d '"')

echo " ----- LDAP Configuration ----- "

LDAP_NAME_DEFAULT="local-OpenLDAP"
read -p "Connection Name [$LDAP_NAME_DEFAULT]: " LDAP_NAME
LDAP_NAME="${LDAP_NAME:-$LDAP_NAME_DEFAULT}"

LDAP_TYPE_DEFAULT="Custom"
read -p "LDAP Type [$LDAP_TYPE_DEFAULT]: " LDAP_TYPE
LDAP_TYPE="${LDAP_TYPE:-$LDAP_TYPE_DEFAULT}"

LDAP_BASE_DN_DEFAULT="dc=ibm,dc=com"
read -p "Base DN [$LDAP_BASE_DN_DEFAULT]: " LDAP_BASE_DN
LDAP_BASE_DN="${LDAP_BASE_DN:-$LDAP_BASE_DN_DEFAULT}"

LDAP_BIND_DN_DEFAULT="cn=admin,dc=ibm,dc=com"
read -p "Bind DN [$LDAP_BIND_DN_DEFAULT]: " LDAP_BIND_DN
LDAP_BIND_DN="${LDAP_BIND_DN:-$LDAP_BIND_DN_DEFAULT}"

LDAP_BIND_PASSWORD_DEFAULT="Passw0rd!"
read -p "Bind DN Password [$LDAP_BIND_PASSWORD_DEFAULT]: " LDAP_BIND_PASSWORD
LDAP_BIND_PASSWORD="${LDAP_BIND_PASSWORD:-$LDAP_BIND_PASSWORD_DEFAULT}"

LDAP_HOST_DEFAULT="ldap://cp4i-openldap.cp4i-ldap.svc.cluster.local:389"
read -p "LDAP Server [$LDAP_HOST_DEFAULT]: " LDAP_HOST
LDAP_HOST="${LDAP_HOST:-$LDAP_HOST_DEFAULT}"

LDAP_GROUP_FILTER_DEFAULT="(&(cn=%v)(objectclass=groupOfUniqueNames))"
read -p "Group Filter [$LDAP_GROUP_FILTER_DEFAULT]: " LDAP_GROUP_FILTER
LDAP_GROUP_FILTER="${LDAP_GROUP_FILTER:-$LDAP_GROUP_FILTER_DEFAULT}"

LDAP_USER_FILTER_DEFAULT="(&(uid=%v)(objectclass=person))"
read -p "User Filter [$LDAP_USER_FILTER_DEFAULT]: " LDAP_USER_FILTER
LDAP_USER_FILTER="${LDAP_USER_FILTER:-$LDAP_USER_FILTER_DEFAULT}"

LDAP_GROUP_ID_MAP_DEFAULT="*:cn"
read -p "Group Id map [$LDAP_GROUP_ID_MAP_DEFAULT]: " LDAP_GROUP_ID_MAP
LDAP_GROUP_ID_MAP="${LDAP_GROUP_ID_MAP:-$LDAP_GROUP_ID_MAP_DEFAULT}"

LDAP_USER_ID_MAP_DEFAULT="*:uid"
read -p "User ID map [$LDAP_USER_ID_MAP_DEFAULT]: " LDAP_USER_ID_MAP
LDAP_USER_ID_MAP="${LDAP_USER_ID_MAP:-$LDAP_USER_ID_MAP_DEFAULT}"

LDAP_GROUP_MEMBER_ID_MAP_DEFAULT="groupOfUniqueNames:uniqueMember"
read -p "Group member ID map [$LDAP_GROUP_MEMBER_ID_MAP_DEFAULT]: " LDAP_GROUP_MEMBER_ID_MAP
LDAP_GROUP_MEMBER_ID_MAP="${LDAP_GROUP_MEMBER_ID_MAP:-$LDAP_GROUP_MEMBER_ID_MAP_DEFAULT}"

ENCODED_LDAP_BIND_PASSWORD=$(echo $LDAP_BIND_PASSWORD | tr -d '\n' |  base64)

echo "Attempting to create the LDAP configuration in IBM Common Services with LDAP $LDAP_HOST..."
curl -k -X POST \
  https://$CONSOLE_HOST:443/idmgmt/identity/api/v1/directory/ldap/onboardDirectory \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "content-type: application/json" \
  -d '{
    "LDAP_ID": "'"${LDAP_NAME}"'",
    "LDAP_URL": "'"${LDAP_HOST}"'",
    "LDAP_BASEDN": "'"${LDAP_BASE_DN}"'",
    "LDAP_BINDDN": "'"${LDAP_BIND_DN}"'",
    "LDAP_BINDPASSWORD": "'"${ENCODED_LDAP_BIND_PASSWORD}"'",
    "LDAP_TYPE": "'"${LDAP_TYPE}"'",
    "LDAP_USERFILTER": "'"${LDAP_USER_FILTER}"'",
    "LDAP_GROUPFILTER": "'"${LDAP_GROUP_FILTER}"'",
    "LDAP_USERIDMAP": "'"${LDAP_USER_ID_MAP}"'",
    "LDAP_GROUPIDMAP": "'"${LDAP_GROUP_ID_MAP}"'",
    "LDAP_GROUPMEMBERIDMAP": "'"${LDAP_GROUP_MEMBER_ID_MAP}"'"    
  }' \
  --insecure