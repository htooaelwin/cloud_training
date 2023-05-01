# Define VPC
resource "aws_vpc" "example_vpc" {
  cidr_block = "10.0.0.0/16"
}

# Define subnets
resource "aws_subnet" "private_subnet_1" {
  vpc_id = aws_vpc.example_vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1a"
}

resource "aws_subnet" "private_subnet_2" {
  vpc_id = aws_vpc.example_vpc.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "us-east-1b"
}

# Create a private subnet group for RDS:
resource "aws_db_subnet_group" "example" {
  name        = "example-rds-subnet-group"
  subnet_ids  = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]

  tags = {
    Name = "example-rds-subnet-group"
  }
}


# Define security group
resource "aws_security_group" "elb_sg" {
  name_prefix = "elb_sg_"
  vpc_id      = aws_vpc.example_vpc.id

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.example_vpc.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "my_private_alb" {
  name               = "my-private-alb"
  internal           = true
  load_balancer_type = "application"
  subnets            = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]

  security_groups = [
    aws_security_group.private_alb.id
  ]

  tags = {
    Name = "My Private ALB"
  }
}

resource "aws_lb_listener" "example" {
  load_balancer_arn = aws_lb.my_private_alb.arn
  port              = 3306
  protocol          = "TCP"

  default_action {
    target_group_arn = aws_lb_target_group.example.arn
    type             = "forward"
  }
}

resource "aws_lb_target_group" "rds" {
  name_prefix = "rds-tg-"
  port        = 3306
  protocol    = "TCP"
  vpc_id      = aws_vpc.example.id

  health_check {
    protocol = "TCP"
  }

  tags = {
    Name = "RDS Target Group"
  }
}


resource "aws_lb_target_group_attachment" "rds" {
  target_group_arn = aws_lb_target_group.rds.arn

  count = length(aws_rds_cluster_instance.example)
  target_id = aws_rds_cluster_instance.example[count.index].id
  port      = 3306
}

resource "aws_rds_cluster_instance" "example" {
  count            = 5
  identifier       = "example-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.example.id
  instance_class   = "db.t3.small"
  engine           = "mysql"
  engine_version   = "8.0"
  publicly_accessible = false
  vpc_security_group_ids = [aws_security_group.rds.id]

  subnet_group_name = aws_db_subnet_group.example.name

  tags = {
    Name = "RDS Cluster Instance"
  }
}

resource "aws_rds_cluster" "example_rds_cluster" {
  cluster_identifier = "example-rds-cluster"
  engine             = "aurora-mysql"
  engine_version     = "5.7.12"
  database_name      = "example_db"
  master_username    = "admin"
  master_password    = "adminpassword"
  db_subnet_group_name = aws_db_subnet_group.example_db_subnet_group.name
  vpc_security_group_ids = [
    aws_security_group.example_sg.id
  ]
  scaling_configuration {
    auto_pause = true
    max_capacity = 5
    min_capacity = 2
  }
}
