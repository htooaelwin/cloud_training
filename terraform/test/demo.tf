# Create a security group for the jumphost 

resource "aws_security_group" "jumphost_sg" {
  name_prefix = "jh"

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
  key_name      = "hal-aws-2"
  subnet_id     = aws_subnet.private_a.id
  vpc_security_group_ids = [aws_security_group.jumphost_sg.id]

  tags = {
    Name = "jumphost"
  }
}