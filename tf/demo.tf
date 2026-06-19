# =============================================================================
# FICHIER TERRAFORM VOLONTAIREMENT VULNÉRABLE - À DES FINS ÉDUCATIVES
# NE PAS UTILISER EN PRODUCTION
# =============================================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# VULN-1 : Credentials AWS codées en dur (OWASP A07 - Identification failures)
provider "aws" {
  region     = "us-east-1"
  access_key = "AKIAIOSFODNN7EXAMPLE"         # ❌ Ne jamais coder des credentials en dur
  secret_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"  # ❌ Utiliser des variables ou IAM roles
}

# VULN-2 : Bucket S3 entièrement public (OWASP A01 - Broken Access Control)
resource "aws_s3_bucket" "public_bucket" {
  bucket = "my-totally-public-bucket"
}

resource "aws_s3_bucket_public_access_block" "public_bucket" {
  bucket = aws_s3_bucket.public_bucket.id

  block_public_acls       = false   # ❌ Devrait être true
  block_public_policy     = false   # ❌ Devrait être true
  ignore_public_acls      = false   # ❌ Devrait être true
  restrict_public_buckets = false   # ❌ Devrait être true
}

resource "aws_s3_bucket_acl" "public_bucket" {
  bucket = aws_s3_bucket.public_bucket.id
  acl    = "public-read-write"      # ❌ Permet à n'importe qui de lire ET écrire
}

# Pas de chiffrement sur le bucket ❌
# aws_s3_bucket_server_side_encryption_configuration manquant

# Pas de versioning ❌
# aws_s3_bucket_versioning manquant

# VULN-3 : Security Group ouvert à tout internet (OWASP A05 - Security Misconfiguration)
resource "aws_security_group" "wide_open" {
  name        = "wide-open-sg"
  description = "Allows all traffic"

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]    # ❌ Tous les ports ouverts à tout internet
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]    # ❌ SSH exposé à internet
  }

  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]    # ❌ RDP exposé à internet
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# VULN-4 : Instance EC2 avec IMDSv1 et données sensibles en user_data
resource "aws_instance" "vulnerable_ec2" {
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t2.micro"

  security_groups = [aws_security_group.wide_open.name]

  # ❌ IMDSv1 activé - vulnérable aux attaques SSRF pour voler des credentials
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "optional"   # ❌ Devrait être "required" (IMDSv2)
    http_put_response_hop_limit = 2            # ❌ Devrait être 1
  }

  # ❌ Données sensibles en clair dans user_data (visible dans la console AWS)
  user_data = <<-EOF
    #!/bin/bash
    export DB_PASSWORD="super_secret_password_123"
    export API_KEY="sk-prod-abc123def456"
    echo "DB_PASSWORD=$DB_PASSWORD" >> /etc/environment
  EOF

  # ❌ Pas de chiffrement du volume racine
  root_block_device {
    volume_size = 20
    encrypted   = false   # ❌ Devrait être true
  }

  tags = {
    Name = "vulnerable-instance"
  }
}

# VULN-5 : Base de données RDS exposée publiquement sans chiffrement
resource "aws_db_instance" "vulnerable_rds" {
  identifier        = "vulnerable-db"
  engine            = "mysql"
  engine_version    = "5.7"          # ❌ Version obsolète
  instance_class    = "db.t3.micro"
  allocated_storage = 20

  db_name  = "mydb"
  username = "admin"
  password = "Password123!"          # ❌ Mot de passe codé en dur

  publicly_accessible    = true      # ❌ Base de données exposée à internet
  skip_final_snapshot    = true      # ❌ Pas de snapshot final avant suppression
  deletion_protection    = false     # ❌ Pas de protection contre la suppression
  storage_encrypted      = false     # ❌ Données non chiffrées au repos
  backup_retention_period = 0        # ❌ Pas de backups automatiques

  # ❌ Pas de groupe de sous-réseau privé défini
  vpc_security_group_ids = [aws_security_group.wide_open.id]
}

# VULN-6 : Politique IAM trop permissive (privilege escalation)
resource "aws_iam_policy" "overly_permissive" {
  name        = "OverlyPermissivePolicy"
  description = "Full admin access for everyone"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "*"         # ❌ Toutes les actions autorisées
        Resource = "*"         # ❌ Sur toutes les ressources
      }
    ]
  })
}

resource "aws_iam_role" "vulnerable_role" {
  name = "vulnerable-role"

  # ❌ N'importe quel principal peut assumer ce rôle
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { AWS = "*" }   # ❌ Tout le monde peut assumer ce rôle
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_admin" {
  role       = aws_iam_role.vulnerable_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"  # ❌ Droits admin complets
}

# VULN-7 : Cluster EKS sans logging ni chiffrement
resource "aws_eks_cluster" "vulnerable_eks" {
  name     = "vulnerable-cluster"
  role_arn = aws_iam_role.vulnerable_role.arn

  vpc_config {
    subnet_ids              = []
    endpoint_public_access  = true    # ❌ API server exposé à internet
    endpoint_private_access = false   # ❌ Pas d'accès privé
    public_access_cidrs     = ["0.0.0.0/0"]  # ❌ Tout internet peut atteindre l'API
  }

  # ❌ Aucun logging activé
  # enabled_cluster_log_types manquant

  # ❌ Pas de chiffrement des secrets Kubernetes
  # encryption_config manquant
}

# VULN-8 : Bucket S3 utilisé comme backend Terraform sans chiffrement ni verrou
# (état Terraform peut contenir des secrets en clair)
# terraform {
#   backend "s3" {
#     bucket = "my-tf-state"
#     key    = "prod/terraform.tfstate"
#     region = "us-east-1"
#     # ❌ encrypt = true manquant
#     # ❌ dynamodb_table manquant (pas de state locking)
#   }
# }

# =============================================================================
# RÉSUMÉ DES VULNÉRABILITÉS
# =============================================================================
# 1. Credentials codées en dur dans le provider
# 2. Bucket S3 public en lecture/écriture sans chiffrement
# 3. Security Group ouvert sur tous les ports (0.0.0.0/0)
# 4. EC2 avec IMDSv1, secrets en user_data, volume non chiffré
# 5. RDS accessible publiquement, non chiffré, mot de passe en dur
# 6. Politique IAM avec wildcard (Action:* Resource:*) et rôle assumable par tous
# 7. EKS avec API server public et sans logging
# 8. State Terraform potentiellement non chiffré et sans verrou
# =============================================================================
 
