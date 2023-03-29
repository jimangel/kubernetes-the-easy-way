#!/bin/bash

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
