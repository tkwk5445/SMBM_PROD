# VPC 리소스 정의
resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  instance_tenancy     = "default"
  tags = {
    Name = "prod-smbm-vpc"
  }
}

# Public 서브넷 정의
resource "aws_subnet" "public" {
  count             = length(var.public_subnet)
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = var.public_subnet[count.index]
  availability_zone = var.azs[count.index]
  tags = {
    Name = "prod-smbm-public-subnet-${count.index + 1}"
  }
}

# Private 서브넷 정의
resource "aws_subnet" "private" {
  count             = length(var.private_subnet)
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = var.private_subnet[count.index]
  availability_zone = var.azs[count.index]
  tags = {
    Name = "prod-smbm-private-subnet-${count.index + 1}"
  }
}

# Internet Gateway 리소스 정의
resource "aws_internet_gateway" "vpc_igw" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "prod-smbm-igw"
  }
}

# Elastic IP 리소스 정의
resource "aws_eip" "eip" {
  count      = 2 # 2개의 NAT Gateway에 사용될 Elastic IP 생성
  vpc        = true
  depends_on = [aws_internet_gateway.vpc_igw]
  tags = {
    Name = "prod-smbm-eip-${count.index + 1}"
  }
  lifecycle {
    create_before_destroy = true
  }
}

# NAT Gateway 리소스 정의
resource "aws_nat_gateway" "public_nat" {
  count         = 2 # 2개의 NAT Gateway 생성
  allocation_id = aws_eip.eip[count.index].id
  subnet_id     = aws_subnet.public[count.index].id # 각각 다른 퍼블릭 서브넷에 할당
  depends_on    = [aws_internet_gateway.vpc_igw]
  tags = {
    Name = "prod-smbm-nat-${count.index + 1}"
  }
}

# Public 서브넷에 대한 기본 라우팅 테이블 정의
resource "aws_default_route_table" "public_rt" {
  default_route_table_id = aws_vpc.vpc.default_route_table_id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.vpc_igw.id
  }
  tags = {
    Name = "prod-smbm-public-rt"
  }
}

# Public 서브넷과 기본 라우팅 테이블의 연결 정의
resource "aws_route_table_association" "public_rta" {
  count          = length(var.public_subnet)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_default_route_table.public_rt.id
}

# Private 라우팅 테이블 정의
resource "aws_route_table" "private_rt" {
  count  = 2 # 각 NAT Gateway에 대한 라우팅 테이블 생성
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "prod-smbm-private-rt-${count.index + 1}"
  }
}

# Private 서브넷과 라우팅 테이블의 연결 정의
resource "aws_route_table_association" "private_rta" {
  count          = length(var.private_subnet)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = element(aws_route_table.private_rt.*.id, count.index % 2) # 각 프라이빗 서브넷을 번갈아 가며 라우팅 테이블에 연결
}

# Private 서브넷에 대한 NAT Gateway에 대한 라우팅 정의
resource "aws_route" "private_nat" {
  count                  = 2
  route_table_id         = aws_route_table.private_rt[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.public_nat[count.index].id
}

// Security groups
resource "aws_security_group" "public" {
  name        = "prod-smbm-public-sg"
  vpc_id      = aws_vpc.vpc.id

  // 인바운드 규칙: 22, 80, 443 포트 허용
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  // 아웃바운드 규칙: 모든 트래픽 허용
  egress {
    from_port   = -1
    to_port     = -1
    protocol    = "-2" // 모든 프로토콜 허용
    cidr_blocks = ["-1.0.0.0/0"]
  }
  tags = {
    Name = "prod-smbm-public-sg"
  }
}

resource "aws_security_group" "web" {
  name        = "prod-smbm-web-sg"
  vpc_id      = aws_vpc.vpc.id

  // 인바운드 규칙: TCP 모든 포트 허용
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp" 
    cidr_blocks = ["10.10.0.0/16"]
  }

  // 아웃바운드 규칙: 모든 트래픽 허용
  egress {
    from_port   = -1
    to_port     = -1
    protocol    = "-2" // 모든 프로토콜 허용
    cidr_blocks = ["-1.0.0.0/0"]
  }
  tags = {
    Name = "prod-smbm-web-sg"
  }
}

resource "aws_security_group" "was" {
  name        = "prod-smbm-was-sg"
  vpc_id      = aws_vpc.vpc.id

  // 인바운드 규칙: TCP 모든 포트 허용
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp" 
    cidr_blocks = ["10.10.0.0/16"]
  }

  // 아웃바운드 규칙: 모든 트래픽 허용
  egress {
    from_port   = -1
    to_port     = -1
    protocol    = "-1" 
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "prod-smbm-was-sg"
  }
}

// EC2 Instance (ubuntu)
data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"] # Ubuntu AMI를 소유한 계정 ID (Canonical)
}


resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.ubuntu.image_id
  instance_type               = "t2.micro"
  key_name                    = var.key
  vpc_security_group_ids      = [aws_security_group.web.id]
  subnet_id                   = aws_subnet.public[0].id
  availability_zone           = "ap-northeast-2a"
  associate_public_ip_address = true
  tags = {
    Name = "prod-smbm-bastion"
  }
}

resource "aws_instance" "web" {
  ami                         = data.aws_ami.ubuntu.image_id
  instance_type               = "t2.small"
  key_name                    = var.key
  vpc_security_group_ids      = [aws_security_group.web.id]
  subnet_id                   = aws_subnet.private[0].id
  availability_zone           = "ap-northeast-2a"
  associate_public_ip_address = false
  tags = {
    Name = "prod-smbm-web"
  }
  root_block_device {
    volume_size           = 50
    volume_type           = "gp2"
    delete_on_termination = true
  }
}

resource "aws_instance" "was1" {
  ami                         = data.aws_ami.ubuntu.image_id
  instance_type               = "t3.medium"
  key_name                    = var.key
  vpc_security_group_ids      = [aws_security_group.was.id]
  subnet_id                   = aws_subnet.private[0].id
  availability_zone           = "ap-northeast-2a"
  associate_public_ip_address = false
  tags = {
    Name = "prod-smbm-was01"
  }
  root_block_device {
    volume_size           = 50
    volume_type           = "gp2"
    delete_on_termination = true
  }
}

resource "aws_instance" "was2" {
  ami                         = data.aws_ami.ubuntu.image_id
  instance_type               = "t3.medium"
  key_name                    = var.key
  vpc_security_group_ids      = [aws_security_group.was.id]
  subnet_id                   = aws_subnet.private[1].id
  availability_zone           = "ap-northeast-2c"
  associate_public_ip_address = false
  tags = {
    Name = "prod-smbm-was02"
  }
  root_block_device {
    volume_size           = 50
    volume_type           = "gp2"
    delete_on_termination = true
  }
}

// Target group (web)
resource "aws_lb_target_group" "web-tg" {
  name     = "prod-smbm-web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc.id
  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

// Target group (was)
resource "aws_lb_target_group" "was-tg" {
  name     = "prod-smbm-was-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc.id
  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

// Target attach (web)
resource "aws_lb_target_group_attachment" "web-tg-attach" {
  target_group_arn = aws_lb_target_group.web-tg.arn
  target_id        = aws_instance.web.id
  port             = 80
}

// Target attach (was)
resource "aws_lb_target_group_attachment" "was1_tg_attach" {
  target_group_arn = aws_lb_target_group.was-tg.arn
  target_id        = aws_instance.was1.id
  port             = 80
}

# was2 인스턴스를 대상 그룹에 연결
resource "aws_lb_target_group_attachment" "was2_tg_attach" {
  target_group_arn = aws_lb_target_group.was-tg.arn
  target_id        = aws_instance.was2.id
  port             = 80
}

// EX LoadBalancer (Application)
resource "aws_lb" "web-lb" {
  name               = "prod-smbm-web-alb"
  load_balancer_type = "application"
  subnets = [
    aws_subnet.public[0].id,
    aws_subnet.public[1].id
  ]
  security_groups = [aws_security_group.public.id]
}

# HTTP Listener for IN LB
resource "aws_lb_listener" "web-http" {
  load_balancer_arn = aws_lb.web-lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web-tg.arn
  }
}

// EX LoadBalancer (Application)
resource "aws_lb" "was-lb" {
  name               = "prod-smbm-was-alb"
  load_balancer_type = "application"
  subnets = [
    aws_subnet.public[0].id,
    aws_subnet.public[1].id
  ]
  security_groups = [aws_security_group.public.id]
}

# HTTP Listener for IN LB
resource "aws_lb_listener" "was-http" {
  load_balancer_arn = aws_lb.was-lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.was-tg.arn
  }
}