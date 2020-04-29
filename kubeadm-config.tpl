apiVersion: kubeadm.k8s.io/v1beta2
kind: InitConfiguration
bootstrapTokens:
- token: wi19h5.n18aqn376cwny601
  description: "kubeadm bootstrap token"
  ttl: "1h"
---
apiVersion: kubeadm.k8s.io/v1beta2
kind: ClusterConfiguration
clusterName: kubernetes-the-easy-way
kubernetesVersion: ${kubernetes_version}
networking:
  podSubnet: "10.217.0.0/16"
---
apiVersion: kubeadm.k8s.io/v1beta2
kind: JoinConfiguration
discovery:
  bootstrapToken:
    apiServerEndpoint: kube-apiserver:6443
    token: wi19h5.n18aqn376cwny601
    unsafeSkipCAVerification: true
  timeout: 5m0s
  tlsBootstrapToken: wi19h5.n18aqn376cwny601