#!/bin/bash
# ./run.sh --private-key=./ansible/ssh_keys/openshift_id

PRIVATE_KEY=./ansible/ssh_keys/openshift_id
ANSIBLE_VAULT=./ansible/ssh_keys/ssh_key_vault.yml
REMOTE_USER=osadmin

echo "Please enter your remote root password: "; read -s ADMIN_PASSWORD
echo "Note: remote root login will be disabled once public keys have been setup"

string_contains() { [ -z "${2##*$1*}" ] && [ -n "$2" -o -z "$1" ]; }

#### PARSE COMMAND LINE ####
for i in "$@"
do
case $i in
    -u=*|--user=*)
    REMOTE_USER="${i#*=}"
    shift # past argument=value
    ;;
    -p=*|--private-key=*)
    PRIVATE_KEY="${i#*=}"
    shift # past argument=value
    ;;
    *)
            # unknown option
    ;;
esac
done

echo "Remote user account to be created: $REMOTE_USER"
echo "Private key location: $PRIVATE_KEY"

if [ ! -f "$PRIVATE_KEY" ]; then
    echo "Generating RSA keypair"
    echo -e 'y\n' | ssh-keygen -b 4096 -t rsa -f "$PRIVATE_KEY" -N "" -q -C openshift
fi

#### BUILD INFRASTRUCTURE ####
TF_VAR_dd_admin_pass="$ADMIN_PASSWORD" terraform apply

#sleep 15

#terraform refresh

#sleep 120

BASTION_HOST_IP=`terraform state show ddcloud_nat.bastion-nat | grep public_ipv4 | awk -F"=" '{print $2}'`
MASTER_PUBLIC_IP=`terraform state show ddcloud_nat.master-nat | grep public_ipv4 | awk -F"=" '{print $2}'`
ROUTER_PUBLIC_IP=`terraform state show ddcloud_nat.router-nat | grep public_ipv4 | awk -F"=" '{print $2}'`

OS_PUBLIC_HOST="${MASTER_PUBLIC_IP// }.xip.io"
OS_APPS_DOMAIN="apps.${ROUTER_PUBLIC_IP// }.xip.io"

#### BUILD DYNAMIC INVENTORY ####
cat > ose-inventory-vars << EOF
# Set variables common for all OSEv3 hosts
[OSEv3:vars]
# SSH user, this user should allow ssh based auth without requiring a password
#ansible_ssh_user=$REMOTE_USER
openshift_master_cluster_public_hostname=$OS_PUBLIC_HOST
osm_default_subdomain=$OS_APPS_DOMAIN

# If ansible_ssh_user is not root, ansible_sudo must be set to true
ansible_become=true
openshift_disable_check=docker_storage

product_type=openshift
deployment_type=origin

# uncomment the following to enable htpasswd authentication; defaults to DenyAllPasswordIdentityProvider
openshift_master_identity_providers=[{'name': 'htpasswd_auth', 'login': 'true', 'challenge': 'true', 'kind': 'HTPasswdPasswordIdentityProvider', 'filename': '/etc/origin/openshift-passwd'}]

[role_openshift-master:vars]
openshift_public_hostname=$OS_PUBLIC_HOST

[role_openshift-infra:vars]
openshift_node_labels="{'region': 'infra', 'zone': 'default'}"
openshift_public_hostname=${ROUTER_PUBLIC_IP// }.xip.io

[role_openshift-node:vars]
openshift_node_labels="{'region': 'primary', 'zone': 'default'}"          

# Create an OSEv3 group that contains the masters and nodes groups
[OSEv3:children]                                                         
masters
etcd
nodes

# host group for etcd
[etcd:children]
role_openshift-master
#role_openshift-etcd

# host group for masters
[masters:children]
role_openshift-master

# host group for nodes, includes region info
[nodes:children]
role_openshift-master
role_openshift-infra
role_openshift-node

EOF

# TODO edit inventory-template if using multiple masters, perhaps ask some questions
 ~/go/bin/terraform-inventory -inventory | cat ose-inventory-vars - > inventory

#for first time setup, create an ansible vault
if [ ! -f $ANSIBLE_VAULT ]; then

echo "Setting up ansible vault"
_B64_PRIVATE_KEY=`base64 -i $PRIVATE_KEY`
RAW_PUBLIC_KEY=`cat "${PRIVATE_KEY}.pub"`
cat | ansible-vault encrypt --output-file=$ANSIBLE_VAULT - << EOF
ssh_public_key: ${RAW_PUBLIC_KEY}

ssh_private_key: ${B64_PRIVATE_KEY}

ssh_passphrase: ${ADMIN_PASSWORD}

EOF

fi

ANSIBLE_ARGS="--user=$REMOTE_USER --private-key=$PRIVATE_KEY $@"

# setup remote access through bastion host
ansible-playbook -i inventory ./ansible/setup-access.yml --ask-pass --ask-vault-pass --private-key=$PRIVATE_KEY

ansible-playbook -i inventory ./ansible/setup-access-user.yml --ask-vault-pass --private-key=$PRIVATE_KEY --extra-vars="createuser=$REMOTE_USER createpassword=\"$ADMIN_PASSWORD\""

# prep nodes
#ansible-playbook -i inventory ./ansible/rhel-sub.yml $ANSIBLE_ARGS
ansible-playbook -i inventory ./ansible/ose3-prep-nodes.yml $ANSIBLE_ARGS

# install openshift
ansible-playbook -i inventory ../../openshift-ansible/playbooks/byo/config.yml $ANSIBLE_ARGS
