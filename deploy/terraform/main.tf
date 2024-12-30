terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = var.region
}


data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_vpc" "vpc" {
  cidr_block           = var.cidr_vpc
  enable_dns_support   = true
  enable_dns_hostnames = true
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
}

resource "aws_subnet" "subnet_public" {
  vpc_id     = aws_vpc.vpc.id
  cidr_block = var.cidr_subnet
}

resource "aws_route_table" "rtb_public" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "rta_subnet_public" {
  subnet_id      = aws_subnet.subnet_public.id
  route_table_id = aws_route_table.rtb_public.id
}

resource "aws_security_group" "sg_ssh_and_locust" {
  name   = "sh_ssh_and_locust"
  vpc_id = aws_vpc.vpc.id

  # SSH access from the VPC
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # locust
  ingress {
    from_port   = 8089
    to_port     = 8089
    protocol    = "tcp"
    # todo: restrict access to users under Canonical VPN
    cidr_blocks = ["0.0.0.0/0"]
  }

  # grafana
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  # prometheus
  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_spot_instance_request" "locust_docker_compose" {
  ami           = data.aws_ami.ubuntu.id
  spot_price    = "0.1"
  instance_type = "c5.xlarge"
  key_name      = "aramanau-key"

  subnet_id                   = aws_subnet.subnet_public.id
  vpc_security_group_ids      = [aws_security_group.sg_ssh_and_locust.id]
  associate_public_ip_address = true
  user_data                   = file("setup_locust_cloudinit.yaml")
  wait_for_fulfillment        = true


  tags = {
    Name = "locust_docker_compose[terraform]"
  }
}

resource "aws_key_pair" "deployer" {
  key_name   = "aramanau-key"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC8l3ord9z3TnS5MKCCzQdjg9UCKHqDauNtW8ytQi7O2GtIw9VOWU99BrYFWf1pzsYkPFF6cvY/xbFjwEidg2CkuodBfXmEPHOx6C7gB11XnWvO8nKx7YsCb9zJYd+MaMKJl0D/HUidOk/DWgHW+LGFR48b+Gdz4Q23JF/7DOplg4p8JjzmyetzqhNGD0qDs6LAEnwLu/Wan4RigGVK88CVOqx3KeKynd0yQZ7I+QPRQYFsneMzkAktSEOFOwlNTeIvx7Cn/4WhUWCH9abM66wVarsxU9jf9YxtmYOAK4zMyVD3vllLagPIJY57rOEUf17KtCXMqezxGjCq5HzjU3WkZI4vRm0Ril/sL9yqunBQZzWkuFQLCwQNX4jV69JepKaBJYTrn4BbGyFK3yEzl/mFLfcoizuh6Yd5ilhQKYaQCQkcpitp+/eopuxNNvye4JxgETVEsKi9kke0sXDBVneyUIqr3wo2yg51lZcTSMgAtyS5Ew2G/OJmdxwYN0Vm9nfY6aWaO6n2C4Qw+JykxyY/CvrF44ywBgtvRN46QrLjnIBjZINenBN6CbbE2G5gEaGa5BrNYU/cLwkxgXFXHkMUm6BvPjPEtdd9fZzlnXChNMOwR9gv+gtORBFHBxS4eYh1VpwI+jqxdxb0zTKCFjJAV/u8KyPDeV9Y1tENa5s8wQ== dr@eniac-24-canonical"
}

#output "public_ip" {
#  value = aws_instance.locust_docker_compose.public_ip
#}

