#!/bin/bash

# these boys don't export well.
export TF_VAR_do_token=${DO_PAT}
export TF_VAR_pub_key=$HOME/.ssh/id_rsa.pub
export TF_VAR_pvt_key=$HOME/.ssh/id_rsa
export TF_VAR_ssh_fingerprint="$(ssh-keygen -E md5 -lf ~/.ssh/id_rsa.pub | awk '{print $2}' | cut -c 5-)"

# swap vars out
terraform destroy --force

# if file exists delete it
[ -e info.txt ] && rm -rf info.txt

exit 0