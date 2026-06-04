output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.kubeadm.id
}

output "public_ip" {
  description = "Public IP address — point your DNS A records here"
  value       = aws_instance.kubeadm.public_ip
}

output "private_ip" {
  description = "Private IP of the instance"
  value       = aws_instance.kubeadm.private_ip
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh -i nilkanth-personal.pem ubuntu@${aws_instance.kubeadm.public_ip}"
}

output "dns_records_to_create" {
  description = "DNS A records to create pointing to the public IP"
  value = {
    "jerney.nilkanthprojects.site" = aws_instance.kubeadm.public_ip
    "argocd.nilkanthprojects.site" = aws_instance.kubeadm.public_ip
    "signoz.nilkanthprojects.site" = aws_instance.kubeadm.public_ip
  }
}
