## Multi Region Clusters

I wanted to be able to create clusters in different regions with the goal of testing https://cilium.io/blog/2019/03/12/clustermesh/ and multi-cluster workloads.

Review the available Digital Ocean regions and short-names here: https://www.digitalocean.com/docs/platform/availability-matrix/#datacenter-regions

### Before you start

Please review the [README.md](../README.md)

### Provision one cluster (default NYC3)

```
# from root directory
git clone https://github.com/jimangel/kubernetes-the-easy-way nyc3
cd nyc3
./create-cluster.sh
```

to use

```
# kubectl config use-context $(terraform output cluster_context)
kubectl config use-context ktew-2q9pmg-nyc3
```

### Provision second cluster in SFO2
```
# from root directory
git clone https://github.com/jimangel/kubernetes-the-easy-way sfo2
cd sfo2
sed -i 's/default = "nyc3"/default = "sfo2"/g' kubernetes-terraform-code.tf
./create-cluster.sh
```

to use

```
# kubectl config use-context $(terraform output cluster_context)
kubectl config use-context ktew-s9fwpd-sfo2
```

### Switch between the two clusters using contexts

```
kubectl config use-context ktew-2q9pmg-nyc3

kubectl get nodes
NAME                   STATUS   ROLES    AGE     VERSION
control-plane-nyc3-1   Ready    master   2m26s   v1.18.2
worker-nyc3-1          Ready    <none>   64s     v1.18.2
worker-nyc3-2          Ready    <none>   64s     v1.18.2

kubectl config use-context ktew-s9fwpd-sfo2

kubectl get nodes
NAME                   STATUS   ROLES    AGE    VERSION
control-plane-sfo2-1   Ready    master   2m9s   v1.18.2
worker-sfo2-1          Ready    <none>   36s    v1.18.2
worker-sfo2-2          Ready    <none>   32s    v1.18.2

```

### Context tips

Show all contexts

```
kubectl config get-contexts
CURRENT   NAME                         CLUSTER            AUTHINFO           NAMESPACE
          kind-kind                    kind-kind          kind-kind          
          ktew-nyc3                    ktew-2q9pmg-nyc3   admin-ktew-2q9pmg-nyc3    
*         ktew-sfo2                    ktew-s9fwpd-sfo2   admin-ktew-s9fwpd-sfo2  
```

Set default namespace for current context

```
kubectl config set-context --current --namespace=FOO
```

### Clean up

```
# from active cloned folder
./destroy-cluster.sh

cd <TO OTHER CLONED FOLDER>
./destroy-cluster.sh
```

> Note: ./destroy-cluster.sh will also unset (cleanup) the contexts that were created.