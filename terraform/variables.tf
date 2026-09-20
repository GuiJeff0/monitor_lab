variable "kubeconfig_path" {
  description = "Caminho para o arquivo kubeconfig do K3s"
  type        = string
  default     = "~/.kube/config"
}

variable "tailscale_hostname" {
  description = "Hostname da máquina no Tailscale (MagicDNS)"
  type        = string
  default     = "creedx66.tail096995.ts.net"
}

variable "tailscale_ip" {
  description = "IP da máquina na rede Tailscale"
  type        = string
  default     = "100.117.224.54"
}

variable "storage_path_hdd" {
  description = "Diretório montado no HDD SATA de 1TB para dados massivos"
  type        = string
  default     = "/mnt/dados/k3s-storage"
}

variable "storage_path_ssd" {
  description = "Diretório no SSD NVMe para dados rápidos do SO e K3s"
  type        = string
  default     = "/var/lib/rancher/k3s/storage"
}

variable "enable_portainer" {
  description = "Habilitar a instalação do Portainer CE para visualização do K3s"
  type        = bool
  default     = true
}

variable "enable_flux" {
  description = "Habilitar o bootstrap do Flux CD para GitOps"
  type        = bool
  default     = true
}

