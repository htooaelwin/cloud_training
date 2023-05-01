eksctl create cluster --name my-eks-cluster --region <region> --zones <availability_zone_1>,<availability_zone_2> --managed

aws eks update-kubeconfig --region <region> --name my-eks-cluster

