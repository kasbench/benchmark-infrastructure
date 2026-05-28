output "etcd_volume_id" {
  description = "ID of the pre-created etcd EBS volume"
  value       = aws_ebs_volume.etcd.id
}

output "all_volumes" {
  description = "Map of all pre-created EBS volumes with metadata for environment description"
  value = {
    etcd = {
      volume_id  = aws_ebs_volume.etcd.id
      size_gib   = aws_ebs_volume.etcd.size
      type       = aws_ebs_volume.etcd.type
      iops       = aws_ebs_volume.etcd.iops
      throughput = aws_ebs_volume.etcd.throughput
      az         = aws_ebs_volume.etcd.availability_zone
      workload   = "etcd"
    }
  }
}

output "storage_class_metadata" {
  description = "Metadata for Kubernetes StorageClass configuration by bootstrap process"
  value = {
    default_workload_storage = {
      volume_type = "gp3"
      fs_type     = "ext4"
      encrypted   = true
      description = "Default StorageClass for PostgreSQL, Kafka, Prometheus PVCs"
    }
    high_iops_storage = {
      volume_type = "gp3"
      iops        = 6000
      throughput  = 250
      fs_type     = "ext4"
      encrypted   = true
      description = "High-IOPS StorageClass for Kafka and PostgreSQL"
    }
  }
}
