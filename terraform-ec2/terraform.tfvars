aws_region       = "ap-south-1"
environment      = "dev"
instance_type    = "t3.medium"
key_name         = "nilkanth-personal"
volume_size      = 30
allowed_ssh_cidr = "0.0.0.0/0" # TODO: Restrict to your IP (e.g., "203.0.113.5/32")