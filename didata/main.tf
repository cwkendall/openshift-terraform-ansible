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

variable "node-roles" { default = {"0" = "openshift-infra"} }

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

resource "ddcloud_nat" "bastion-nat" {
  networkdomain       = "${ddcloud_networkdomain.ose-domain.id}"
  private_ipv4        = "${ddcloud_server.ose-bastion.primary_adapter_ipv4}"
  depends_on          = ["ddcloud_vlan.ose-vlan"]
}

resource "ddcloud_nat" "master-nat" {
  networkdomain       = "${ddcloud_networkdomain.ose-domain.id}"
  private_ipv4        = "${ddcloud_server.ose-master.primary_adapter_ipv4}"
  depends_on          = ["ddcloud_vlan.ose-vlan"]
}

resource "ddcloud_nat" "router-nat" {
  networkdomain       = "${ddcloud_networkdomain.ose-domain.id}"
  private_ipv4        = "${ddcloud_server.ose-node.0.primary_adapter_ipv4}"
  depends_on          = ["ddcloud_vlan.ose-vlan"]
}

resource "ddcloud_firewall_rule" "firewall-rule-001" {
  name                = "ssh.inbound"
  placement           = "first"
  action              = "accept"
  enabled             = true
  ip_version          = "ipv4"
  protocol            = "tcp"
  destination_address = "${ddcloud_nat.bastion-nat.public_ipv4}"
  destination_port    = "22"
  networkdomain       = "${ddcloud_networkdomain.ose-domain.id}"
}

resource "ddcloud_address_list" "node-address-list" {
  name                = "node_Address_List"
  ip_version          = "IPv4"

  addresses           = [ "${ddcloud_nat.master-nat.public_ipv4}", "${ddcloud_nat.router-nat.public_ipv4}" ]
# Below just for reference
# ddcloud_server.ose-master.*.primary_adapter_ipv4
# ddcloud_server.ose-node.*.primary_adapter_ipv4
#  address {
#    network           = "${var.dd_vlan_netaddr}.0"
#    prefix_size       = "${var.dd_vlan_prefix}"
#  }
  
  networkdomain       = "${ddcloud_networkdomain.ose-domain.id}"
  depends_on          = ["ddcloud_networkdomain.ose-domain", "ddcloud_server.ose-master", "ddcloud_server.ose-node"]
}

resource "ddcloud_port_list" "http-port-list" {
  name					      = "http.port_list"
	description 			  = "Http ports for OpenShift nodes"
	ports		            = [80,443,8443]
	networkdomain     	= "${ddcloud_networkdomain.ose-domain.id}"
}


resource "ddcloud_firewall_rule" "firewall-rule-002" {
  name                = "http.inbound"
  placement           = "first"
  action              = "accept"
  enabled             = true
  ip_version          = "ipv4"
  protocol            = "tcp"
  destination_address_list = "${ddcloud_address_list.node-address-list.id}"
  destination_port_list    = "${ddcloud_port_list.http-port-list.id}"
  networkdomain       = "${ddcloud_networkdomain.ose-domain.id}"
}

resource "ddcloud_server" "ose-bastion" {
  name                 = "bastion"
  admin_password       = "${var.dd_admin_pass}"
  networkdomain        = "${ddcloud_networkdomain.ose-domain.id}"
  primary_network_adapter = {
    ipv4 = "${var.dd_vlan_netaddr}.98"
  }
  dns_primary          = "8.8.8.8"
  dns_secondary        = "8.8.4.4"
  image                = "${var.dd_image}"
  tag {
    name               = "role"
    value              = "bastion"
  }
  auto_start           = "TRUE"
  depends_on           = ["ddcloud_vlan.ose-vlan"]
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
    size_gb            = 100
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
    ipv4 = "${var.dd_vlan_netaddr}.${count.index + 100}"
  }
  dns_primary          = "8.8.8.8"
  dns_secondary        = "8.8.4.4"
  image                = "${var.dd_image}"

  disk {
    scsi_unit_id       = 0
    size_gb            = 50
  }

  disk {
    scsi_unit_id       = 1
    size_gb            = 30
  }

  tag {
    name               = "role"
    value              = "${lookup(var.node-roles, count.index, "openshift-node")}"
  }

  auto_start           = "TRUE"
  depends_on           = ["ddcloud_vlan.ose-vlan"]
}
