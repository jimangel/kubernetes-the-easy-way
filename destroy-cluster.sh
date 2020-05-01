#!/bin/bash

# Set your SSH keys to import here
# https://www.digitalocean.com/community/tutorials/how-to-set-up-ssh-keys-on-ubuntu-1804
PUBLIC_KEY="$HOME/.ssh/id_rsa.pub"
PRIVATE_KEY="$HOME/.ssh/id_rsa"

# error if DigitalOcean Access Token isn't set
if [[ -z "${DO_PAT}" ]]; then
    printf "\n*******************************************************\n"
    printf "Makes sure you've exported your DO_PAT token variable\n"
    printf "export DO_PAT=\"<DIGITALOCEAN PERSONAL ACCESS TOKEN>\"\n"
    printf "*******************************************************\n"
    exit 0
fi

# swap vars out
terraform destroy --force -var "do_token=${DO_PAT}" -var "pub_key=$PUBLIC_KEY" -var "pvt_key=$PRIVATE_KEY" -var "ssh_fingerprint=$(ssh-keygen -E md5 -lf $PRIVATE_KEY | awk '{print $2}' | cut -c 5-)"

# if file exists delete it
[ -e info.txt ] && rm -rf info.txt

exit 0
