output "ssh_key_name" {
  description = "EC2 key pair name used for the CP instance"
  value       = aws_instance.cp.key_name
}

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.cp.id
}

output "public_ip" {
  description = "Public IP of the CP instance"
  value       = aws_instance.cp.public_ip
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh -i ~/.ssh/${var.ssh_key_name}.pem ubuntu@${aws_instance.cp.public_ip}"
}
