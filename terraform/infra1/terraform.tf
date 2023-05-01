# create the vpc
resource "aws_vpc" "dev_ap-se-1_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    name = "dev-ap-se-1"
  }
}

# create the public subnet
resource "aws_subnet" "public_subnet" {
  vpc_id     = aws_vpc.dev_ap-se-1_vpc.id
  cidr_block = "10.0.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    name = "public-subnet"
  }
}

# create the private subnet
resource "aws_subnet" "private_a" {
  vpc_id     = aws_vpc.dev_ap-se-1_vpc.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "ap-southeast-1a"

  tags = {
    name = "private-subnet-a"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id     = aws_vpc.dev_ap-se-1_vpc.id
  cidr_block = "10.0.3.0/24"
  availability_zone = "ap-southeast-1b"

  tags = {
    name = "private-subnet-b"
  }
}
# create the internet gateway
resource "aws_internet_gateway" "dev_igw" {
  vpc_id = aws_vpc.dev_ap-se-1_vpc.id

  tags = {
    name = "dev-igw"
  }
}
/*
# attach the internet gateway to the vpc
resource "aws_internet_gateway_attachment" "example_attachment" {
  vpc_id       = aws_vpc.dev_ap-se-1_vpc.id
  internet_gateway_id = aws_internet_gateway.dev_igw.id
} 
*/

resource "aws_route_table" "private_a" {
  vpc_id = aws_vpc.dev_ap-se-1_vpc.id 

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.dev_igw.id
  }

  tags = {
    Name = "private-a"
  }
} 

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private_a.id
}


# create a security group for the elb
resource "aws_security_group" "dev_elb_sg" {
  name = "dev-elb-sg"
  vpc_id = aws_vpc.dev_ap-se-1_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
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


resource "aws_lb" "dev_elbv2" {
  name               = "dev-elbv2"
  internal           = false
  load_balancer_type = "application"

  subnets = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id,
  ]

  security_groups = [
    aws_security_group.dev_elb_sg.id,
  ]

  tags = {
    Environment = "production"
  }

}

output "lb_dns" {
  value = aws_lb.dev_elbv2.dns_name
}

resource "aws_lb_target_group" "dev_web_target_group" {
  name_prefix = "dwtg"

  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.dev_ap-se-1_vpc.id

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    interval            = 30
    path                = "/"
  }
}

resource "aws_lb_listener" "dev_elbv2_listener" {
  load_balancer_arn = aws_lb.dev_elbv2.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_lb_target_group.dev_web_target_group.arn
    type             = "forward"
  }
}




# security group for auto scalling 
resource "aws_security_group" "dev_web_sg" {
  name = "dev-web-sg"
  vpc_id      = aws_vpc.dev_ap-se-1_vpc.id

  ingress {
    from_port = 80
    to_port   = 80
    protocol  = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "TCP"
    cidr_blocks = ["10.0.2.0/24"]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


# Create the launch configuration
resource "aws_launch_configuration" "dev_web_lc" {
  name = "dev-web-lc"

  image_id = "ami-0a72af05d27b49ccb"
  instance_type = "t2.micro"
  key_name = "hal-ap-se-1a-1"

  security_groups = [aws_security_group.dev_web_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              nohup python3 -m http.server 80 &
              EOF


  lifecycle {
    create_before_destroy = true
  }
}

# Create the Auto Scaling Group
resource "aws_autoscaling_group" "dev_web_autoscaling_group" {
  name                      = "deb-web-asg"
  vpc_zone_identifier       = [aws_subnet.private_a.id]
  launch_configuration      = aws_launch_configuration.dev_web_lc.name
  min_size                  = 2
  max_size                  = 4
  desired_capacity          = 2
  health_check_grace_period = 300
  health_check_type         = "EC2"
  termination_policies      = ["OldestInstance", "Default"]
  target_group_arns = [aws_lb_target_group.dev_web_target_group.arn]
  
  tag {
    key                 = "Name"
    value               = "dev-web-asg"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_attachment" "web_server_attachment" {
  autoscaling_group_name = aws_autoscaling_group.dev_web_autoscaling_group.name
  lb_target_group_arn   = aws_lb_target_group.dev_web_target_group.arn
}


# Create a security group for the jumphost 

resource "aws_security_group" "jumphost_sg" {
  name_prefix = "jh"
  vpc_id      = aws_vpc.dev_ap-se-1_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }
} 

# Create an EC2 instance in the private subnet
resource "aws_instance" "jumphost" {

  ami           = "ami-0a72af05d27b49ccb"
  instance_type = "t2.micro"
  key_name      = "hal-ap-se-1a-1"
  subnet_id     = aws_subnet.private_a.id
  associate_public_ip_address = true
  vpc_security_group_ids = [aws_security_group.jumphost_sg.id]

  tags = {
    Name = "jumphost"
  }
}

