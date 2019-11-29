variable "access_key" {}
variable "secret_key" {}
variable "region" {}

variable "instance_count" {
  default = 3
}




provider "aws" {
  access_key = var.access_key
  secret_key = var.secret_key
  region     = var.region
}



resource "aws_vpc" "AyushVPC" {
  cidr_block           = "10.0.0.0/16"
  instance_tenancy     = "default"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "AyushTerraformVPC"

  }
}



resource "aws_internet_gateway" "ayushigw" {
  vpc_id = aws_vpc.AyushVPC.id

  tags = {
    Name = "Ayush IgW"
  }

}




resource "aws_subnet" "ayush-public-terraform" {
  vpc_id = aws_vpc.AyushVPC.id

  cidr_block        = "10.0.1.0/24"
  availability_zone = "${var.region}a"

  tags = {
    Name = "ayush-public-terraform"
  }
}




resource "aws_route_table" "ayush-public-RT" {
  vpc_id = aws_vpc.AyushVPC.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ayushigw.id
  }

  tags = {
    Name = "Ayush Public RT"
  }
}

resource "aws_route_table_association" "ayush-public-RT-association" {
  subnet_id      = aws_subnet.ayush-public-terraform.id
  route_table_id = aws_route_table.ayush-public-RT.id
}




resource "aws_security_group" "ayushweb" {
  name        = "vpc_web"
  description = "Accept incoming connections."
  vpc_id      = aws_vpc.AyushVPC.id

  tags = {
    Name = "WebServerSG"
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
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



data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-trusty-14.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"]
}

module "keypair" {
  name    = "AYUSHKEY"
  source  = "mitchellh/dynamic-keys/aws"
  version = "2.0.0"
  path    = "${path.root}/keys"
}


resource "aws_instance" "web" {
  count                       = var.instance_count
  ami                         = data.aws_ami.ubuntu.id
  availability_zone           = "${var.region}a"
  instance_type               = "t2.micro"
  vpc_security_group_ids      = [aws_security_group.ayushweb.id]
  subnet_id                   = aws_subnet.ayush-public-terraform.id
  associate_public_ip_address = true
  key_name                    = module.keypair.key_name

  connection {
    user        = "ubuntu"
    private_key = "${file("keys/AYUSHKEY.pem")}"
    host        = self.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y apache2"
    ]
  }

  tags = {
    Name = "AyushApache-${count.index + 1}"
  }
}




resource "aws_elb" "ayush-terraform-elb" {
  name            = "ayush-terraform-elb"
  subnets         = [aws_subnet.ayush-public-terraform.id]
  security_groups = [aws_security_group.ayushweb.id]


  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:80/"
    interval            = 30
  }


  instances                   = aws_instance.web.*.id
  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

  tags = {
    Name = "ayush-terraform-elb"
  }
}







output "public_ip" {
  description = "List of public IP addresses assigned to the instances, if applicable"
  value       = aws_instance.web.*.public_ip
}

output "public_dns" {
  description = "List of public DNS names assigned to the instances. For EC2-VPC, this is only available if you've enabled DNS hostnames for your VPC"
  value       = aws_instance.web.*.public_dns
}