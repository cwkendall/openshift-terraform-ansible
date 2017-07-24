#!/bin/bash
# ./run.sh --private-key=~/.ssh/cx-cloud-test
terraform apply

sleep 15

terraform refresh

sleep 120


ansible-playbook -i ../terraform.py ./ansible/rhel-sub.yml $@
ansible-playbook -i ../terraform.py ./ansible/ose3-prep-nodes.yml $@
