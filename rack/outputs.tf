output "ssh_key_name" {
  description = "EC2 key pair name used for the rack instance"
  value       = aws_instance.rack.key_name
}

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.rack.id
}

output "public_ip" {
  description = "Public IP of the rack instance"
  value       = aws_instance.rack.public_ip
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh -i ~/.ssh/${var.ssh_key_name}.pem ubuntu@${aws_instance.rack.public_ip}"
}
