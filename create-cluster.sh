#!/bin/bash

# Set your SSH keys to import here
# https://www.digitalocean.com/community/tutorials/how-to-set-up-ssh-keys-on-ubuntu-1804
#PUBLIC_KEY="${PUBLIC_KEY:-$HOME/.ssh/id_rsa.pub}"
#PRIVATE_KEY="${PRIVATE_KEY:-$HOME/.ssh/id_rsa}"

# error if DigitalOcean Access Token isn't set
if [[ -z "${DO_PAT}" ]]; then
    printf "\n*******************************************************\n"
    printf "Makes sure you've exported your DO_PAT token variable\n"
    printf "export DO_PAT=\"<DIGITALOCEAN PERSONAL ACCESS TOKEN>\"\n"
    printf "*******************************************************\n"
    exit 0
fi

# initialize the resources
terraform init

# plan the deployment
#terraform plan -var "do_token=${DO_PAT}"

terraform apply -auto-approve -var "do_token=${DO_PAT}"
