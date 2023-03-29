apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
bootstrapTokens:
- token: wi19h5.n18aqn376cwny601
  description: "kubeadm bootstrap token"
  ttl: "1h"
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
clusterName: ${cluster_name}
kubernetesVersion: ${kubernetes_version}
networking:
  podSubnet: "${pod_subnet}"
controllerManager:
  extraArgs:
    node-monitor-grace-period: "16s"
    node-monitor-period: "2s"
    bind-address: 0.0.0.0
apiServer:
  extraArgs:
    default-not-ready-toleration-seconds: "30"
    default-unreachable-toleration-seconds: "30"
scheduler:
  extraArgs:
    bind-address: 0.0.0.0
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: JoinConfiguration
discovery:
  bootstrapToken:
    apiServerEndpoint: ${control_plane_ip}:6443
    token: wi19h5.n18aqn376cwny601
    unsafeSkipCAVerification: true
  timeout: 5m0s
  tlsBootstrapToken: wi19h5.n18aqn376cwny601
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
---
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
metricsBindAddress: 0.0.0.0