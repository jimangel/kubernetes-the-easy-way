#!/bin/bash

# Set your SSH keys to import here
# https://www.digitalocean.com/community/tutorials/how-to-set-up-ssh-keys-on-ubuntu-1804
PUBLIC_KEY="$HOME/.ssh/id_rsa.pub"
PRIVATE_KEY="$HOME/.ssh/id_rsa"

# error if DigitalOcean Access Token isn't set
if [[ -z "${DO_PAT}" ]]; then
    printf "\n*******************************************************\n"
    printf "Makes sure you've exported your DO_PAT token variable\n"
    printf "export DO_PAT=b4fec39662e1543fc9ac76b6ca9bba9ba6b9ab9bc7b9ab0a\n"
    printf "*******************************************************\n"
    exit 0
fi

# initialize the resources
terraform init

# plan the deployment
#terraform plan -var "do_token=${DO_PAT}" -var "pub_key=$PUBLIC_KEY" -var "pvt_key=$PRIVATE_KEY" -var "ssh_fingerprint=$(ssh-keygen -E md5 -lf $PRIVATE_KEY | awk '{print $2}' | cut -c 5-)"

terraform apply -auto-approve -var "do_token=${DO_PAT}" -var "pub_key=$PUBLIC_KEY" -var "pvt_key=$PRIVATE_KEY" -var "ssh_fingerprint=$(ssh-keygen -E md5 -lf $PRIVATE_KEY | awk '{print $2}' | cut -c 5-)"

scp -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@$(terraform output -json control_plane_ip | jq -r .[0]):/root/.kube/config ~/.kube/.