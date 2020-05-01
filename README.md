# Kubernetes The Easy Way

This tutorial walks you through setting up Kubernetes the easy way. This guide is for people looking to bootstrap a cluster not managed by a cloud provider.

"not managed" means the control-plane is managed by you as opposed to a cloud provider. This gives you full control of the cluster's configuration (OIDC, FeatureGates, AuditLogs, etc).

Kubernetes The Easy Way is a complement to [Kubernetes The Hard Way](https://github.com/kelseyhightower/kubernetes-the-hard-way). Once you understand the hard way, use this tutorial to expand your knowledge in a multi-node lab.

> The results of this tutorial are not production ready, and may receive limited support from the community, but don't let that stop you from learning!

### Overview

Terraform is used to deploy and destroy a Kubernetes cluster on DigitalOcean via kubeadm. By default, the script deploys 1 control-plane-node and 2 worker-nodes.

The default configuration will create (3) 2GB nodes ($10 a month or $0.015 an hour). I use it to spin up, test, and tear down. Total cost of ownership is $30 a month or $0.045 an hour. If I spun up a cluster and tested for 24 hours then destroyed it, it would cost $1.08 - pretty affordable!

> Note: ONLY TESTED ON UBUNTU 18.04

### Cluster details

* [kubernetes](https://github.com/kubernetes/kubernetes) v1.18.2
* [docker](https://github.com/docker/docker-ce) v19.03.8
* [coredns](https://github.com/coredns/coredns) v1.6.7
* [cilium cni](https://github.com/cilium/cilium) v1.7.3
* [etcd](https://github.com/coreos/etcd) v3.4.3

### Prerequisites

- Install [Terraform](https://learn.hashicorp.com/terraform/getting-started/install.html#install-terraform)

- Export a [DigitalOcean Personal Access Token](https://www.digitalocean.com/docs/apis-clis/api/create-personal-access-token/) with **WRITE** access:

    ```
    export DO_PAT="<DIGITALOCEAN PERSONAL ACCESS TOKEN>"
    ```

### Assumptions

- kubectl is [installed](https://kubernetes.io/docs/tasks/tools/install-kubectl/) locally

- You have the [following files](https://www.digitalocean.com/community/tutorials/how-to-set-up-ssh-keys-on-ubuntu-1804):

    ```
    $HOME/.ssh/id_rsa.pub
    $HOME/.ssh/id_rsa
    
    # verify with:
    cat $HOME/.ssh/id_rsa.pub
    cat $HOME/.ssh/id_rsa
    ```

    > Note: the location can be changed in [./create-cluster.sh](/create-cluster.sh) & [./destroy-cluster.sh](/destroy-cluster.sh)

### Deploy Kubernetes

Clone repository:

```
git clone https://github.com/jimangel/kubernetes-the-easy-way
cd kubernetes-the-easy-way
```


Build the cluster:

**WARNING:** this will overwrite your `~/.kube/config` file

```
./create-cluster.sh
```

It should take ~5 minutes to complete

```
real	4m24.201s
user	0m6.580s
sys	0m3.029s
```

Check it out!

```
kubectl get nodes
kubectl get pods -A
```

---

### Smoke test

SSH into any of the nodes:
```
# control-plane-1
ssh root@$(terraform output -json control_plane_ip | jq -r .[0])

# worker-1
ssh root@$(terraform output -json worker_ip | jq -r .[0])

# worker-2
ssh root@$(terraform output -json worker_ip | jq -r .[1])
```

Deploy NGINX
```
kubectl create deployment nginx --image=nginx
kubectl expose deployment/nginx --port 80
kubectl port-forward deployment/nginx 80:80
# visit localhost in a browser
```

---

### Cleaning up

```
./destroy-cluster.sh
```

### Additional resources:

- How to [add a DigitalOcean CCM](docs/add-digitalocean-ccm.md) for dynamic LB provisioning.
