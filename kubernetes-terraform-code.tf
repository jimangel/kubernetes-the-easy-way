##############
#### TODO ####
##############

# containerd swap
# security
# multi-master
# block storage

##################################
#### SET VARIABLES & VERISONS ####
##################################

# https://github.com/kubernetes/sig-release/blob/master/releases/patch-releases.md#timelines
variable "kubernetes_version" { default = "1.18.3" }
# https://github.com/docker/docker-ce/releases
variable "docker_version" { default = "19.03.11" }
# https://github.com/cilium/cilium/releases
variable "clilium_version" { default = "1.7.2" }
variable "pod_subnet" { default = "10.217.0.0/16" }
# https://www.digitalocean.com/docs/platform/availability-matrix/#datacenter-regions
variable "dc_region" { default = "nyc3" }
# https://developers.digitalocean.com/documentation/v2/#list-all-sizes
# setting below 2 CPUs will fail kubeadm, ignore with `--ignore-preflight-errors=all`
variable "droplet_size" { default = "s-2vcpu-2gb" }
# set with `export DO_PAT=<API TOKEN>`
variable "do_token" {}
# set in `*-cluster.sh` scripts
variable "pub_key" {}
variable "pvt_key" {}
variable "ssh_fingerprint" {}

##################################
#### CONFIGURE CLOUD PROVIDER ####
##################################

provider "digitalocean" { token = var.do_token }

###########################################################
#### GENERATE RANDOM STRING FOR UNIQUE KUBECTL CONTEXT ####
###########################################################

resource "random_string" "lower" {
  length  = 6
  upper   = false
  lower   = true
  number  = true
  special = false
}

######################################
#### CREATE CONTROL PLANE NODE(S) ####
######################################

resource "digitalocean_droplet" "control_plane" {
  count              = 1
  image              = "ubuntu-20-04-x64"
  name               = format("control-plane-%s-%v", var.dc_region, count.index + 1)
  region             = var.dc_region
  size               = var.droplet_size
  private_networking = true
  ssh_keys = [
    var.ssh_fingerprint,
  ]

connection {
    user        = "root"
    host        = self.ipv4_address
    type        = "ssh"
    private_key = file(var.pvt_key)
    timeout     = "2m"
    agent       = false
  }

###############################
#### RENDER KUBEADM CONFIG ####
###############################

provisioner "file" {
    content = templatefile("${path.module}/kubeadm-config.tpl", 
    {
      cluster_name = format("ktew-%s", var.dc_region),
      kubernetes_version = var.kubernetes_version,
      pod_subnet = var.pod_subnet,
      control_plane_ip = digitalocean_droplet.control_plane[0].ipv4_address 
    })
    destination = "/tmp/kubeadm-config.yaml"
  }

###################################################
#### INSTALL CONTROL PLANE DOCKER / KUBERNETES ####
###################################################

provisioner "remote-exec" {
    inline = [
      # GENERAL REPO SPEEDUP
      "until [ -f /var/lib/cloud/instance/boot-finished ]; do sleep 1; done",
      "echo '' > /etc/apt/sources.list",
      "add-apt-repository 'deb [arch=amd64] http://mirrors.digitalocean.com/ubuntu/ focal main restricted universe'",
      # ADD KUBERNETES REPO
      "curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -",
      "add-apt-repository 'deb http://apt.kubernetes.io/ kubernetes-xenial main'",
      #"echo 'deb http://apt.kubernetes.io/ kubernetes-xenial main' | sudo tee -a /etc/apt/sources.list.d/kubernetes.list",
      # INSTALL DOCKER
      "curl -s https://download.docker.com/linux/ubuntu/gpg | apt-key add -",
      "add-apt-repository 'deb [arch=amd64] https://download.docker.com/linux/ubuntu eoan stable'",
      #"echo 'deb http://apt.kubernetes.io/ kubernetes-xenial main' | sudo tee -a /etc/apt/sources.list.d/kubernetes.list",
      #"export VERSION=${var.docker_version} && curl -L https://get.docker.io | bash",
      #"apt update && apt install -y docker.io=${var.docker_version}-0ubuntu1",
      "apt install -y docker-ce=5:${var.docker_version}~3-0~ubuntu-eoan",
      # INSTALL KUBEADM
      "apt install -y kubectl=${var.kubernetes_version}-00 kubelet=${var.kubernetes_version}-00 kubeadm=${var.kubernetes_version}-00 -f",
      # KUBEADM INIT THE CONTROL PLANE
      "kubeadm init --config=/tmp/kubeadm-config.yaml",
      # SETUP KUBECTL REMOTELY
     "mkdir -p /root/.kube && cp -i /etc/kubernetes/admin.conf /root/.kube/config && chown $(id -u):$(id -g) /root/.kube/config"
    ]
  }

#####################
#### INSTALL CNI ####
#####################

provisioner "remote-exec" {
  inline = [
    # INSTALL CALICO CNI
    "kubectl apply -f https://raw.githubusercontent.com/cilium/cilium/v${var.clilium_version}/install/kubernetes/quick-install.yaml"
    ]
  }

}

######################################
#### CREATE ADMIN KUBECTL CONTEXT ####
######################################

resource "null_resource" "kubectl_configure" {

# I use this pointless trigger to reference "self" on destroy...
triggers = {
    cluster_name = format("ktew-%s-%s", random_string.lower.result, var.dc_region)
    admin_name = format("admin-ktew-%s-%s", random_string.lower.result, var.dc_region) 
  }

provisioner "local-exec" {
    command = <<EOT
      scp -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@${digitalocean_droplet.control_plane[0].ipv4_address}:/etc/kubernetes/admin.conf .;

      # get API SERVER URL:PORT
      export API_SERVER=$(kubectl --kubeconfig=admin.conf config view --raw -o json --minify | jq -r '.clusters[0].cluster."server"');

      # get CA cert
      kubectl --kubeconfig=admin.conf config view --raw -o json --minify | jq -r '.clusters[0].cluster."certificate-authority-data"' | tr -d '"' | base64 --decode > ca-file.crt;

      # get client cert
      kubectl --kubeconfig=admin.conf config view --raw -o json --minify | jq -r '.users[0].user."client-certificate-data"' | tr -d '"' | base64 --decode > client-data.crt;

      # get client key
      kubectl --kubeconfig=admin.conf config view --raw -o json --minify | jq -r '.users[0].user."client-key-data"' | tr -d '"' | base64 --decode > client-key.crt;

      # build context
      kubectl config set-cluster ${self.triggers.cluster_name} --server=$API_SERVER --certificate-authority=ca-file.crt --embed-certs=true;
      kubectl config set-context ${self.triggers.cluster_name} --cluster=${self.triggers.cluster_name};
      kubectl config set-credentials ${self.triggers.admin_name} --client-certificate=client-data.crt --client-key=client-key.crt --embed-certs=true;
      kubectl config set-context ${self.triggers.cluster_name} --user=${self.triggers.admin_name};
      kubectl config use-context ${self.triggers.cluster_name};

      # clean up
      rm -rf *.crt *.conf
    EOT
  }

# clean up on destroy
provisioner "local-exec" {
  when    = destroy
  command = <<EOT
    kubectl config unset users.${self.triggers.admin_name};
    kubectl config unset contexts.${self.triggers.cluster_name};
    kubectl config unset clusters.${self.triggers.cluster_name}
  EOT
  }

lifecycle {
    ignore_changes = [triggers["cluster_name"],triggers["admin_name"]]
  }

}

#############################
#### CREATE WORKER NODES ####
#############################

resource "digitalocean_droplet" "worker" {
  count              = 2
  image              = "ubuntu-20-04-x64"
  name               = format("worker-%s-%v", var.dc_region, count.index + 1)
  region             = var.dc_region
  size               = var.droplet_size
  private_networking = true
  ssh_keys = [
    var.ssh_fingerprint,
  ]

connection {
  user        = "root"
  host        = self.ipv4_address
  type        = "ssh"
  private_key = file(var.pvt_key)
  timeout     = "2m"
  agent       = false
  }

###############################
#### RENDER KUBEADM CONFIG ####
############################### 

provisioner "file" {
  content = templatefile("${path.module}/kubeadm-config.tpl", 
    {
      cluster_name = format("ktew-%s", var.dc_region),
      kubernetes_version = var.kubernetes_version,
      pod_subnet = var.pod_subnet,
      control_plane_ip = digitalocean_droplet.control_plane[0].ipv4_address 
    })
    destination = "/tmp/kubeadm-config.yaml"
  }

############################################
#### INSTALL WORKER DOCKER / KUBERNETES ####
############################################

provisioner "remote-exec" {
  inline = [
      # GENERAL REPO SPEEDUP
      "until [ -f /var/lib/cloud/instance/boot-finished ]; do sleep 1; done",
      "echo '' > /etc/apt/sources.list",
      "add-apt-repository 'deb [arch=amd64] http://mirrors.digitalocean.com/ubuntu/ focal main restricted universe'",
      # ADD KUBERNETES REPO
      "curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -",
      "add-apt-repository 'deb http://apt.kubernetes.io/ kubernetes-xenial main'",
      #"echo 'deb http://apt.kubernetes.io/ kubernetes-xenial main' | sudo tee -a /etc/apt/sources.list.d/kubernetes.list",
      # INSTALL DOCKER
      "curl -s https://download.docker.com/linux/ubuntu/gpg | apt-key add -",
      "add-apt-repository 'deb [arch=amd64] https://download.docker.com/linux/ubuntu eoan stable'",
      #"echo 'deb http://apt.kubernetes.io/ kubernetes-xenial main' | sudo tee -a /etc/apt/sources.list.d/kubernetes.list",
      #"export VERSION=${var.docker_version} && curl -L https://get.docker.io | bash",
      #"apt update && apt install -y docker.io=${var.docker_version}-0ubuntu1",
      "apt install -y docker-ce=5:${var.docker_version}~3-0~ubuntu-eoan",
      # INSTALL KUBEADM
      "apt install -y kubectl=${var.kubernetes_version}-00 kubelet=${var.kubernetes_version}-00 kubeadm=${var.kubernetes_version}-00 -f",
      # KUBEADM JOIN THE WORKER
      "kubeadm join --config=/tmp/kubeadm-config.yaml"
    ]
  }
}

##########################
#### OUTPUT VARIABLES ####
##########################

output "control_plane_ip" {
  value = digitalocean_droplet.control_plane.*.ipv4_address
}

output "worker_ip" {
  value = digitalocean_droplet.worker.*.ipv4_address
}

output "cluster_context" {
  value = format("ktew-%s-%s", random_string.lower.result, var.dc_region)
  description = "kubectl config use-context --context ..."
}