variable "cidr_vpc" {
  description = "CIDR block for the VPC"
  default     = "172.32.0.0/16"
}
variable "cidr_subnet" {
  description = "CIDR block for the subnet"
  default     = "172.32.0.0/24"
}

variable "environment_tag" {
  description = "Environment tag"
  default     = "Locust"
}

variable "region" {
  description = "The region Terraform deploys your instance"
  default     = "eu-north-1"
}
