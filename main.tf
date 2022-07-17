terraform {
  required_providers {

    aws = {
      source  = "hashicorp/aws"
      version = "4.0.0"
    }
  }

  required_version = "~> 1.1.5"
}

// Here we are configuring our aws provider.
// We are setting the region to the region of
// our variable "aws_region"
provider "aws" {
  region = var.aws_region
}

// This data object is going to be
// holding all the available availability
// zones in our defined region
data "aws_availability_zones" "available" {
  state = "available"
}

// Create a data object called "ubuntu" that holds the latest
// Ubuntu 20.04 server AMI
data "aws_ami" "ubuntu" {
  most_recent = "true"
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"]
}

// Create a VPC named "tutorial_vpc"
resource "aws_vpc" "tutorial_vpc" {

  cidr_block           = var.vpc_cidr_block
  enable_dns_hostnames = true

  tags = {
    Name = "tutorial_vpc"
  }
}

resource "aws_internet_gateway" "tutorial_igw" {

  vpc_id = aws_vpc.tutorial_vpc.id

  tags = {
    Name = "tutorial_igw"
  }
}

// Create a group of public subnets based on the variable subnet_count.public
resource "aws_subnet" "tutorial_public_subnet" {

  count             = var.subnet_count.public
  vpc_id            = aws_vpc.tutorial_vpc.id
  cidr_block        = var.public_subnet_cidr_blocks[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "tutorial_public_subnet_${count.index}"
  }
}

// Create a group of private subnets based on the variable subnet_count.private
resource "aws_subnet" "tutorial_private_subnet" {

  count             = var.subnet_count.private
  vpc_id            = aws_vpc.tutorial_vpc.id
  cidr_block        = var.private_subnet_cidr_blocks[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "tutorial_private_subnet_${count.index}"
  }
}

// Create a public route table named "tutorial_public_rt"
resource "aws_route_table" "tutorial_public_rt" {
  vpc_id = aws_vpc.tutorial_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.tutorial_igw.id
  }
}

// Here we are going to add the public subnets to the
// "tutorial_public_rt" route table
resource "aws_route_table_association" "public" {

  count          = var.subnet_count.public
  route_table_id = aws_route_table.tutorial_public_rt.id
  subnet_id      = aws_subnet.tutorial_public_subnet[count.index].id
}

// Create a private route table named "tutorial_private_rt"
resource "aws_route_table" "tutorial_private_rt" {
  vpc_id = aws_vpc.tutorial_vpc.id
}


resource "aws_route_table_association" "private" {

  count          = var.subnet_count.private
  route_table_id = aws_route_table.tutorial_private_rt.id
  subnet_id      = aws_subnet.tutorial_private_subnet[count.index].id
}

// Create a security for the EC2 instances called "tutorial_web_sg"
resource "aws_security_group" "tutorial_web_sg" {
  name        = "tutorial_web_sg"
  description = "Security group for tutorial web servers"
  vpc_id      = aws_vpc.tutorial_vpc.id

  ingress {
    description = "Allow all traffic through HTTP"
    from_port   = "80"
    to_port     = "80"
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow SSH from my computer"
    from_port   = "22"
    to_port     = "22"
    protocol    = "tcp"
    cidr_blocks = ["${var.my_ip}/32"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "tutorial_web_sg"
  }
}

// Create a security group for the RDS instances called "tutorial_db_sg"
resource "aws_security_group" "tutorial_db_sg" {
  name        = "tutorial_db_sg"
  description = "Security group for tutorial databases"
  vpc_id      = aws_vpc.tutorial_vpc.id

  ingress {
    description     = "Allow MySQL traffic from only the web sg"
    from_port       = "3306"
    to_port         = "3306"
    protocol        = "tcp"
    security_groups = [aws_security_group.tutorial_web_sg.id]
  }

  tags = {
    Name = "tutorial_db_sg"
  }
}


resource "aws_db_subnet_group" "tutorial_db_subnet_group" {

  name        = "tutorial_db_subnet_group"
  description = "DB subnet group for tutorial"
  subnet_ids  = [for subnet in aws_subnet.tutorial_private_subnet : subnet.id]
}


resource "aws_db_instance" "tutorial_database" {

  allocated_storage      = var.settings.database.allocated_storage
  engine                 = var.settings.database.engine
  engine_version         = var.settings.database.engine_version
  instance_class         = var.settings.database.instance_class
  db_name                = var.settings.database.db_name
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.tutorial_db_subnet_group.id
  vpc_security_group_ids = [aws_security_group.tutorial_db_sg.id]
  skip_final_snapshot    = var.settings.database.skip_final_snapshot
  backup_window = "03:00-06:00"
  maintenance_window = "Mon:00:00-Mon:03:00"

}

// Create a key pair named "tutorial_kp"
resource "aws_key_pair" "tutorial_kp" {

  key_name   = "tutorial_kp"
  public_key = file("tutorial_kp.pub")
}

// Create an EC2 instance named "tutorial_web"
resource "aws_instance" "tutorial_web" {

  count                  = var.settings.web_app.count
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.settings.web_app.instance_type
  subnet_id              = aws_subnet.tutorial_public_subnet[count.index].id
  key_name               = aws_key_pair.tutorial_kp.key_name
  vpc_security_group_ids = [aws_security_group.tutorial_web_sg.id]

  tags = {
    Name = "tutorial_web_${count.index}"
  }
}

// Create an Elastic IP named "tutorial_web_eip" for each
// EC2 instance
resource "aws_eip" "tutorial_web_eip" {

  count    = var.settings.web_app.count
  instance = aws_instance.tutorial_web[count.index].id
  vpc      = true

  tags = {
    Name = "tutorial_web_eip_${count.index}"
  }
}

