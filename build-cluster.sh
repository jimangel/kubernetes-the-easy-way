#!/bin/bash

if [[ -z "${DO_PAT}" ]]; then
    printf "\n*******************************************************\n"
    printf "Makes sure you've exported your DO_PAT token variable\n"
    printf "export DO_PAT=b4fec39662e1543fc9ac76b6ca9bba9ba6b9ab9bc7b9ab0a\n"
    printf "*******************************************************\n"
    exit 0
fi

terraform init

#terraform plan -var "do_token=${DO_PAT}" -var "pub_key=$HOME/.ssh/id_rsa.pub" -var "pvt_key=$HOME/.ssh/id_rsa" -var "ssh_fingerprint=$(ssh-keygen -E md5 -lf ~/.ssh/id_rsa.pub | awk '{print $2}' | cut -c 5-)""

terraform apply -auto-approve -var "do_token=${DO_PAT}" -var "pub_key=$HOME/.ssh/id_rsa.pub" -var "pvt_key=$HOME/.ssh/id_rsa" -var "ssh_fingerprint=$(ssh-keygen -E md5 -lf ~/.ssh/id_rsa.pub | awk '{print $2}' | cut -c 5-)"

scp -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@$(terraform output -json control_plane_ip | jq -r .[0]):/root/.kube/config ~/.kube/.