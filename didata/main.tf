variable "dd_username" {}
variable "dd_password" {}
variable "dd_region" {default = "AU"}
variable "dd_datacenter" {default = "AU9"}
variable "dd_netdomain" {default = "Openshift TF Demo"}
variable "dd_vlan" {default = "openshift_test"}
variable "dd_vlan_netaddr" {default = "192.168.64" }
variable "dd_vlan_prefix" {default = "24" }

variable "dd_image" {default = "CentOS 7 64-bit 2 CPU"}
variable "dd_admin_pass" {}

variable "num_nodes" { default = "2" }

provider "ddcloud" {
    username           = "${var.dd_username}"
    password           = "${var.dd_password}"
    region             = "${var.dd_region}"
}

resource "ddcloud_networkdomain" "ose-domain" {
  name                 = "${var.dd_netdomain}"
  description          = "This is my Terraform test network domain."
  datacenter           = "${var.dd_datacenter}" # The ID of the data centre in which to create your network domain.
}

resource "ddcloud_vlan" "ose-vlan" {
  name                 = "${var.dd_vlan}"
  description          = "This is my Terraform test VLAN."

  networkdomain        = "${ddcloud_networkdomain.ose-domain.id}"

  # VLAN's default network: 192.168.64.1 -> 192.168.64.254 (netmask = 255.255.255.0)
  ipv4_base_address    = "${var.dd_vlan_netaddr}.0"
  ipv4_prefix_size     = "${var.dd_vlan_prefix}"

  depends_on           = [ "ddcloud_networkdomain.ose-domain"]
}

resource "ddcloud_server" "ose-master" {
  name                 = "master"
  admin_password       = "${var.dd_admin_pass}"
  memory_gb            = 16
  cpu_count            = 2
  networkdomain        = "${ddcloud_networkdomain.ose-domain.id}"
  primary_network_adapter = {
    ipv4 = "${var.dd_vlan_netaddr}.99"
  }
  dns_primary          = "8.8.8.8"
  dns_secondary        = "8.8.4.4"
  image                = "${var.dd_image}"

  disk {
    scsi_unit_id       = 0
    size_gb            = 50
  }

  tag {
    name               = "role"
    value              = "openshift-master"
  }

  auto_start           = "TRUE"
  depends_on           = ["ddcloud_vlan.ose-vlan"]

}

resource "ddcloud_server" "ose-node" {
  count                = "${var.num_nodes}"
  name                 = "node${count.index}"
  admin_password       = "${var.dd_admin_pass}"
  memory_gb            = 8
  cpu_count            = 2
  networkdomain        = "${ddcloud_networkdomain.ose-domain.id}"
  primary_network_adapter = {
    ipv4 = "${var.dd_vlan_netaddr}.10${count.index}"
  }
  dns_primary          = "8.8.8.8"
  dns_secondary        = "8.8.4.4"
  image                = "${var.dd_image}"

  disk {
    scsi_unit_id       = 0
    size_gb            = 20
  }

  disk {
    scsi_unit_id       = 1
    size_gb            = 30
  }

  tag {
    name               = "role"
    value              = "openshift-node"
  }

  auto_start           = "TRUE"
  depends_on           = ["ddcloud_vlan.ose-vlan"]
}
