#!/bin/bash

KEY_NAME="thiago-devops-keypair-02"
SG_NAME="thiago-devops-sg-th"

# Pegar VPC default
VPC_ID=$(aws ec2 describe-vpcs \
 --filters "Name=isDefault,Values=true" \
 --query "Vpcs[0].VpcId" --output text)

# Pegar Subnet default
SUBNET_ID=$(aws ec2 describe-subnets \
 --filters "Name=default-for-az,Values=true" \
 --query "Subnets[0].SubnetId" --output text)

# Pegar última AMI Amazon Linux 2
AMI_ID=$(aws ec2 describe-images \
 --owners amazon \
 --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" \
 --query "Images | sort_by(@, &CreationDate) | [0].ImageId" \
 --output text)

# Criar key pair se não existir
aws ec2 describe-key-pairs --key-names "$KEY_NAME" > /dev/null 2>&1

KEY_PATH="$HOME/$KEY_NAME.pem"

# Verifica se o key pair existe de verdade
EXISTS=$(aws ec2 describe-key-pairs --key-names "$KEY_NAME" --query "KeyPairs[0].KeyName" --output text 2>/dev/null)

if [ "$EXISTS" = "None" ] || [ -z "$EXISTS" ]; then
    echo "Criando key pair $KEY_NAME..."
    aws ec2 create-key-pair --key-name "$KEY_NAME" \
        --query "KeyMaterial" --output text > "$KEY_PATH"
    chmod 400 "$KEY_PATH"
    echo "Key pair criado em $KEY_PATH"
else
    echo "Key pair $KEY_NAME já existe"
    if [ ! -f "$KEY_PATH" ]; then
        echo "Arquivo $KEY_PATH não encontrado! Por favor coloque o .pem correto."
        exit 1
    fi
fi

# Criar Security Group
SG_ID=$(aws ec2 create-security-group \
 --group-name "$SG_NAME" \
 --description "Security group for $SG_NAME" \
 --vpc-id "$VPC_ID" \
 --query "GroupId" --output text)

# Liberar porta 22
aws ec2 authorize-security-group-ingress \
 --group-id "$SG_ID" --protocol tcp --port 22 --cidr 0.0.0.0/0

# Lista de nomes das VMs
VMS=(vm01 vm02 vm03)

for NAME in "${VMS[@]}"; do
    echo "Creating VM $NAME"

    INSTANCE_ID=$(aws ec2 run-instances \
        --image-id "$AMI_ID" \
        --count 1 \
        --instance-type t3.micro \
        --key-name "$KEY_NAME" \
        --security-group-ids "$SG_ID" \
        --subnet-id "$SUBNET_ID" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$NAME}]" \
        --query "Instances[0].InstanceId" --output text)

    echo "$NAME criada com ID: $INSTANCE_ID"
    aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"
    echo "$NAME está em execução."
done
