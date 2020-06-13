provider "aws" {
  region                  = "ap-south-1"
  profile                 = "pavan"
}
resource "tls_private_key" "webserver_key" {
    algorithm   =  "RSA"
    rsa_bits    =  4096
}
data "aws_vpc" "selected" {
    default = true
}
locals {
    vpc_id    = data.aws_vpc.selected.id
}
resource "local_file" "private_key" {
    content         =  tls_private_key.webserver_key.private_key_pem
    filename        =  "webserver.pem"
    file_permission =  0400
}
resource "aws_key_pair" "webserver_key" {
    key_name   = "webserver"
    public_key = tls_private_key.webserver_key.public_key_openssh
}
resource "aws_security_group" "allow_tls" {
  name        = "allow_tls"
  description = "Allow TLS inbound traffic"
  vpc_id      = local.vpc_id

  ingress {
    description = "TLS from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }


  tags = {
    Name = "allow_tls"
  }
}
resource "aws_instance" "myint"{
  ami	         = "ami-005956c5f0f757d37"
  instance_type  = "t2.micro"
  key_name       = "webserver"
  vpc_security_group_ids  = [aws_security_group.allow_tls.id]
  availability_zone       = "ap-south-1b"
  subnet_id               = "subnet-4a026906"
  

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.webserver_key.private_key_pem
    host     = aws_instance.myint.public_ip
  }
provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd  php git -y",
      "sudo service httpd restart",
      
    ]
  }
  

  tags= {
    Name = "myos1"
   }
}


resource "aws_ebs_volume" "esb2" {
  availability_zone = "ap-south-1b"
  size              = 1

  tags = {
    Name = "myebs1"
  }
}
resource "aws_volume_attachment" "ebs_att" {
  device_name = "/dev/sdd"
  volume_id   = aws_ebs_volume.esb2.id
  instance_id = aws_instance.myint.id
}
resource "null_resource" "nullremote3"  {

depends_on = [
    aws_volume_attachment.ebs_att,
  ]


  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.webserver_key.private_key_pem
    host     = aws_instance.myint.public_ip
  }

provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4  /dev/xvdh",
      "sudo mount  /dev/xvdh  /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/saipavanbm/web.git /var/www/html/"
    ]
  }
}
resource "aws_s3_bucket" "image-bucket" {
    bucket  = "webserver165"
    acl     = "public-read"
provisioner "local-exec" {
        command     = "git clone https://github.com/saipavanbm/image.git cloud"
    }

}
resource "aws_s3_bucket_object" "image-upload" {
    bucket  = aws_s3_bucket.image-bucket.bucket
    key     = "cloud.jpeg"
    source  = "cloud/cloud.jpg"
    acl     = "public-read"
}
variable "var1" {default = "S3-"}
locals {
    s3_origin_id = "${var.var1}${aws_s3_bucket.image-bucket.bucket}"
    image_url = "${aws_cloudfront_distribution.s3_distribution.domain_name}/${aws_s3_bucket_object.image-upload.key}"
}
resource "aws_cloudfront_distribution" "s3_distribution" {
    default_cache_behavior {
        allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
        cached_methods   = ["GET", "HEAD"]
        target_origin_id = local.s3_origin_id
        forwarded_values {
            query_string = false
            cookies {
                forward = "none"
            }
        }
        viewer_protocol_policy = "allow-all"
    }
enabled             = true
origin {
        domain_name = aws_s3_bucket.image-bucket.bucket_domain_name
        origin_id   = local.s3_origin_id
    }
restrictions {
        geo_restriction {
        restriction_type = "none"
        }
    }
viewer_certificate {
        cloudfront_default_certificate = true
    }
connection {
        type    = "ssh"
        user    = "ec2-user"
        host    = aws_instance.myint.public_ip
        port    = 22
        private_key = tls_private_key.webserver_key.private_key_pem
    }
provisioner "remote-exec" {
        inline  = [
            # "sudo su << \"EOF\" \n echo \"<img src='${self.domain_name}'>\" >> /var/www/html/index.html \n \"EOF\""
            "sudo su << EOF",
            "echo \"<img src='http://${self.domain_name}/${aws_s3_bucket_object.image-upload.key}'>\" >> /var/www/html/index.html",
            "EOF"
        ]
    }
}
resource "null_resource" "nulllocal1"  {


depends_on = [
    null_resource.nullremote3,
  ]

	provisioner "local-exec" {
	    command = "start chrome  ${aws_instance.myint.public_ip}"
  	}
}






