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

resource "aws_lb_listener" "example" {
  load_balancer_arn = aws_lb.my_private_alb.arn
  port              = 3306
  protocol          = "TCP"

  default_action {
    target_group_arn = aws_lb_target_group.rds.arn
    type             = "forward"
  }
}

#security group in Terraform for an RDS cluster:
resource "aws_security_group" "rds_cluster_sg" {
  name_prefix = "rds-cluster-sg-"
  vpc_id      = "${var.vpc_id}"

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [
      "${aws_security_group.private_elb_sg.id}",
      "${aws_db_subnet_group.rds_cluster_subnets.id}"
    ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# create RDS 
resource "aws_rds_cluster" "rds_cluster" {
  engine                        = "aurora"
  engine_version                = "5.7.mysql_aurora.2.08.1"
  database_name                 = "mydatabase"
  master_username               = "admin"
  master_password               = "password"
  backup_retention_period       = 7
  preferred_backup_window       = "03:00-04:00"
  skip_final_snapshot           = true
  deletion_protection           = false
  availability_zones            = ["us-west-2a", "us-west-2b", "us-west-2c", "us-west-2d", "us-west-2e"]
  db_subnet_group_name          = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids        = [aws_security_group.rds_security_group.id]
  scaling_configuration         = {
    auto_pause                  = true
    max_capacity                = 64
    min_capacity                = 2
    seconds_until_auto_pause    = 300
    timeout_action              = "ForceApplyCapacityChange"
  }
  replication_source_identifier = aws_rds_cluster.replication_source_identifier.id

  tags = {
    Name = "rds-cluster"
  }
}

resource "aws_rds_cluster_instance" "rds_cluster_instance" {
  count             = 5
  identifier        = "rds-instance-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.rds_cluster.id
  instance_class    = "db.r5.large"
  engine            = "aurora"
  engine_version    = "5.7.mysql_aurora.2.08.1"
  subnet_group_name = aws_db_subnet_group.rds_subnet_group.name
  publicly_accessible = false

  tags = {
    Name = "rds-instance-${count.index + 1}"
  }
}


resource "aws_lb_target_group_attachment" "rds" {
  target_group_arn = aws_lb_target_group.rds.arn

  count = length(aws_rds_cluster_instance.example)
  target_id = aws_rds_cluster_instance.example[count.index].id
  port      = 3306
}


