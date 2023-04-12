# create the vpc
resource "aws_vpc" "example_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    name = "example-vpc"
  }
}

# create the public subnet
resource "aws_subnet" "public_subnet" {
  vpc_id     = aws_vpc.example_vpc.id
  cidr_block = "10.0.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    name = "public-subnet"
  }
}

# create the private subnet
resource "aws_subnet" "private_a" {
  vpc_id     = aws_vpc.example_vpc.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "ap-southeast-1a"

  tags = {
    name = "private-subnet"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id     = aws_vpc.example_vpc.id
  cidr_block = "10.0.3.0/24"
  availability_zone = "ap-southeast-1b"

  tags = {
    name = "private-subnet"
  }
}
# create the internet gateway
resource "aws_internet_gateway" "example_igw" {
  vpc_id = aws_vpc.example_vpc.id

  tags = {
    name = "example-igw"
  }
}
/*
# attach the internet gateway to the vpc
resource "aws_internet_gateway_attachment" "example_attachment" {
  vpc_id       = aws_vpc.example_vpc.id
  internet_gateway_id = aws_internet_gateway.example_igw.id
} 
*/
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.example_vpc.id 

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.example_igw.id
  }

  tags = {
    Name = "private"
  }
} 

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}


# create a security group for the elb
resource "aws_security_group" "elb_sg" {
  name = "example-elb-sg"
  vpc_id = aws_vpc.example_vpc.id

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


resource "aws_lb" "example" {
  name               = "example-lb"
  internal           = false
  load_balancer_type = "application"

  subnets = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id,
  ]

  security_groups = [
    aws_security_group.elb_sg.id,
  ]

  tags = {
    Environment = "production"
  }
}

resource "aws_lb_target_group" "web_server_target_group" {
  name_prefix = "examp"

  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.example_vpc.id

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    interval            = 30
    path                = "/"
  }
}

resource "aws_lb_listener" "example" {
  load_balancer_arn = aws_lb.example.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_lb_target_group.web_server_target_group.arn
    type             = "forward"
  }
}




# security group for auto scalling 
resource "aws_security_group" "web_sg" {
  name = "web-sg"
  vpc_id      = aws_vpc.example_vpc.id

  ingress {
    from_port = 80
    to_port   = 80
    protocol  = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
    #security_groups = [aws_security_group.elb_sg.id]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


# Create the launch configuration
resource "aws_launch_configuration" "example_lc" {
  name = "example-lc"

  image_id = "ami-0a72af05d27b49ccb"
  instance_type = "t2.micro"
  key_name = "hal-aws-2"

  security_groups = [aws_security_group.web_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              nohup python3 -m http.server 80 &
              EOF


  lifecycle {
    create_before_destroy = true
  }
}

# Create the Auto Scaling Group
resource "aws_autoscaling_group" "web_server_autoscaling_group" {
  name                      = "example-asg"
  vpc_zone_identifier       = [aws_subnet.private_a.id]
  launch_configuration      = aws_launch_configuration.example_lc.name
  min_size                  = 5
  max_size                  = 10
  desired_capacity          = 5
  health_check_grace_period = 300
  health_check_type         = "EC2"
  termination_policies      = ["OldestInstance", "Default"]
  target_group_arns = [aws_lb_target_group.web_server_target_group.arn]
  
  tag {
    key                 = "Name"
    value               = "example-asg"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_attachment" "web_server_attachment" {
  autoscaling_group_name = aws_autoscaling_group.web_server_autoscaling_group.name
  lb_target_group_arn   = aws_lb_target_group.web_server_target_group.arn
}