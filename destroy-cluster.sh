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

# swap vars out
terraform init
terraform destroy -var "do_token=${DO_PAT}"

# check the number of loadbalancers running
LB_COUNT=$(curl -s -H "Authorization: Bearer $DO_PAT" "https://api.digitalocean.com/v2/load_balancers" |  jq -r .meta.total)

# if running more than 0, error
if [ $LB_COUNT -ne 0 ]; then printf "\n\n***\nWARNING: You have running loadbalancers in DigitalOcean which you are paying for. You may not have removed all loadbalancers created by the CCM, check Digital Ocean if not intended\n***\n\n"; fi

exit 0
