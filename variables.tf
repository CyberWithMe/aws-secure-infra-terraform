variable "my_ip" {
  description = "Your home/office IP address for SSH access, in CIDR notation"
  type        = string
}

variable "ssh_public_key_path" {
  description = "Path to your SSH public key file"
  type        = string
}