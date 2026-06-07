Please validate that the following requirements are already satisfied or modify the existing HCL to satisfy theese requirements:


1. The IAM role connected to the control plane and worker EC2 instances must have the following policies:
- AmazonEBSCSIDriverPolicy
- AmazonS3FullAccess
- AmazonSSMManagedInstanceCore
- CloudWatchAgentServerPolicy

If the role contains other policies, do not remove them.

2. The security groups attached to the control plane and worker EC2 instances must allow all traffic between to pass between them.  Traffice between the control plane and worker nodes or between worker nodes must be unrestricted.
