resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.env}-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "${var.env}-igw"
  }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.env}-public-${count.index + 1}"
  }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.env}-private-${count.index + 1}"
  }
}

# Reserves an Elastic IP for the NAT Gateway
resource "aws_eip" "nat" {
  tags = {
    Name = "${var.env}-nat-eip"
  }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "${var.env}-nat"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.env}-public-rt"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "${var.env}-private-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

data "aws_availability_zones" "available" {
  state = "available"
}



#----------------------
# Security Group
#----------------------

## EC2 Security Groups
#  Bastion Security Group
resource "aws_security_group" "bastion" {
  name        = "${var.env}-bastion-sg"
  description = "Allow SSH"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.env}-bastion-sg"
  }
}

resource "aws_security_group_rule" "bastion_ingress_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.bastion.id
  description       = "Allow SSH from anywhere"
}

# PostgreSQL Security Group
resource "aws_security_group" "postgres" {
  name        = "${var.env}-postgres-sg"
  description = "Allow PostgreSQL"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.env}-postgres-sg"
  }
}
resource "aws_security_group_rule" "postgres_ingress_ssh_from_bastion" {
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.bastion.id
  security_group_id        = aws_security_group.postgres.id
  description              = "Allow SSH from Bastion"
}

resource "aws_security_group_rule" "postgres_ingress_pgsql_from_bastion" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.bastion.id
  security_group_id        = aws_security_group.postgres.id
  description              = "Allow PostgreSQL from Bastion"
}

resource "aws_security_group_rule" "postgres_ingress_pgsql_from_dms" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.dms_sg.id
  security_group_id        = aws_security_group.postgres.id
  description              = "Allow PostgreSQL from DMS"
}



# DMS Security Group
resource "aws_security_group" "dms_sg" {
  name        = "dms-security-group"
  description = "Security group for DMS replication instance"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EMR Security Groups
# EMR Master Security Group
resource "aws_security_group" "emr_master_sg" {
  name        = "${var.env}-emr-master-sg"
  description = "EMR master security group"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.env}-emr-master-sg"
  }
}

resource "aws_security_group_rule" "emr_master_ingress_self" {
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  security_group_id = aws_security_group.emr_master_sg.id
  self              = true
  description       = "Allow all traffic within EMR master SG"
}

resource "aws_security_group_rule" "emr_master_ingress_ssh_from_bastion" {
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  security_group_id        = aws_security_group.emr_master_sg.id
  source_security_group_id = aws_security_group.bastion.id
  description              = "Allow SSH from Bastion SG"
}

# EMR Core/Task Nodes Security Group
resource "aws_security_group" "emr_core_sg" {
  name        = "${var.env}-emr-core-sg"
  description = "EMR core and task nodes security group"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.env}-emr-core-sg"
  }
}

resource "aws_security_group_rule" "emr_core_ingress_self" {
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  security_group_id = aws_security_group.emr_core_sg.id
  self              = true
  description       = "Allow all traffic within EMR core SG"
}

# EMR Service Access Security Group
resource "aws_security_group" "emr_service_access_sg" {
  name        = "${var.env}-emr-service-access-sg"
  description = "EMR Service Access"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.env}-emr-service-access-sg"
  }
}

resource "aws_security_group_rule" "emr_service_access_ingress_from_master" {
  type                     = "ingress"
  from_port                = 9443
  to_port                  = 9443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.emr_service_access_sg.id
  source_security_group_id = aws_security_group.emr_master_sg.id
  description              = "Allow EMR Master SG on port 9443"
}

# MWAA security groups
resource "aws_security_group" "mwaa" {
  name        = "${var.env}-mwaa-sg"
  description = "Security group for MWAA"
  vpc_id      = aws_vpc.main.id

  # Allow outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  tags = {
    Name = "${var.env}-mwaa-sg"
  }
}


resource "aws_security_group_rule" "mwaa_ingress_from_bastion" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.mwaa.id
  source_security_group_id = aws_security_group.bastion.id
  description              = "Allow bastion EC2"
}

# ---------------------
# VPC endpoints
# ---------------------
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${var.region}.s3"
  route_table_ids = [
    aws_route_table.private.id
  ]
  vpc_endpoint_type = "Gateway"

  tags = {
    Name = "${var.env}-s3-endpoint"
  }
}

# resource "aws_vpc_endpoint" "glue" {
#   vpc_id             = aws_vpc.main.id
#   service_name       = "com.amazonaws.ap-southeast-2.glue"
#   vpc_endpoint_type  = "Interface"
#   subnet_ids         = aws_subnet.private[*].id
#   security_group_ids = [aws_security_group.glue.id] # ✅ REQUIRED

#   private_dns_enabled = true

#   tags = {
#     Name = "${var.env}-glue-endpoint"
#   }
# }

resource "aws_vpc_endpoint" "dms" {
  service_name       = "com.amazonaws.${var.region}.dms"
  vpc_id             = aws_vpc.main.id
  vpc_endpoint_type  = "Interface"
  subnet_ids         = aws_subnet.private[*].id
  security_group_ids = [aws_security_group.dms_sg.id]

  private_dns_enabled = true

  tags = {
    Name = "${var.env}-dms-endpoint"
  }
}

resource "aws_vpc_endpoint" "ec2" {
  service_name       = "com.amazonaws.${var.region}.ec2"
  vpc_id             = aws_vpc.main.id
  vpc_endpoint_type  = "Interface"
  subnet_ids         = aws_subnet.private[*].id
  security_group_ids = [aws_security_group.emr_master_sg.id]

  private_dns_enabled = true

  tags = {
    Name = "${var.env}-ec2-endpoint"
  }
}

resource "aws_vpc_endpoint" "emr" {
  service_name       = "com.amazonaws.${var.region}.elasticmapreduce"
  vpc_id             = aws_vpc.main.id
  vpc_endpoint_type  = "Interface"
  subnet_ids         = aws_subnet.private[*].id
  security_group_ids = [aws_security_group.emr_master_sg.id]

  private_dns_enabled = true

  tags = {
    Name = "${var.env}-emr-endpoint"
  }
}



## MWAA VPC Endpoints, MWAA will automatically create VPC endpoints
# resource "aws_vpc_endpoint" "airflow_env" {
#   vpc_id             = aws_vpc.main.id
#   service_name       = "com.amazonaws.${var.region}.airflow-env"
#   vpc_endpoint_type  = "Interface"
#   subnet_ids         = aws_subnet.private[*].id
#   security_group_ids = [aws_security_group.mwaa.id]
# }

# resource "aws_vpc_endpoint" "sqs" {
#   vpc_id             = aws_vpc.main.id
#   service_name       = "com.amazonaws.${var.region}.sqs"
#   vpc_endpoint_type  = "Interface"
#   subnet_ids         = aws_subnet.private[*].id
#   security_group_ids = [aws_security_group.mwaa.id]
# }

# resource "aws_vpc_endpoint" "logs" {
#   vpc_id             = aws_vpc.main.id
#   service_name       = "com.amazonaws.${var.region}.logs"
#   vpc_endpoint_type  = "Interface"
#   subnet_ids         = aws_subnet.private[*].id
#   security_group_ids = [aws_security_group.mwaa.id]
# }

# resource "aws_vpc_endpoint" "s3" {
#   vpc_id            = aws_vpc.main.id
#   service_name      = "com.amazonaws.${var.region}.s3"
#   vpc_endpoint_type = "Gateway"
#   route_table_ids   = [aws_route_table.private.id]
# }
