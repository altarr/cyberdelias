#!/bin/bash
# Simple script to build the Cyberdelias web server AMI

set -e

echo "Building Cyberdelias Web Server AMI..."

# Configuration
BASE_AMI="ami-0c7217cdde317cfec"  # Ubuntu 22.04 LTS
INSTANCE_TYPE="t3.small"
KEY_NAME="your-key-name"
SECURITY_GROUP="sg-XXXXXX"
SUBNET_ID="subnet-XXXXXX"
AMI_NAME="cyberdelias-webserver-$(date +%Y%m%d-%H%M%S)"

# Launch temporary instance
echo "Launching temporary build instance..."
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id $BASE_AMI \
  --instance-type $INSTANCE_TYPE \
  --key-name $KEY_NAME \
  --security-group-ids $SECURITY_GROUP \
  --subnet-id $SUBNET_ID \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=ami-builder-temp}]" \
  --query 'Instances[0].InstanceId' \
  --output text)

echo "Instance: $INSTANCE_ID"
aws ec2 wait instance-running --instance-ids $INSTANCE_ID

# Get instance IP
INSTANCE_IP=$(aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

echo "Waiting for SSH (60 seconds)..."
sleep 60

# Install application
echo "Installing application on instance..."
ssh -o StrictHostKeyChecking=no -i ~/.ssh/${KEY_NAME}.pem ubuntu@$INSTANCE_IP << 'ENDSSH'
  set -e
  sudo apt-get update && sudo apt-get upgrade -y
  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
  sudo apt-get install -y nodejs
  sudo mkdir -p /opt/cyberdelias
  sudo chown ubuntu:ubuntu /opt/cyberdelias
  sudo npm install -g pm2
  sudo env PATH=$PATH:/usr/bin pm2 startup systemd -u ubuntu --hp /home/ubuntu
ENDSSH

# Copy application files
echo "Copying application files..."
scp -o StrictHostKeyChecking=no -i ~/.ssh/${KEY_NAME}.pem \
  server.js package.json cyberdelia.html \
  ubuntu@$INSTANCE_IP:/opt/cyberdelias/

# Install dependencies and configure
ssh -o StrictHostKeyChecking=no -i ~/.ssh/${KEY_NAME}.pem ubuntu@$INSTANCE_IP << 'ENDSSH'
  cd /opt/cyberdelias
  npm install --production

  # Create startup script
  cat > start.sh << 'EOF'
#!/bin/bash
cd /opt/cyberdelias
pm2 start server.js --name cyberdelias
pm2 save
EOF
  chmod +x start.sh

  # Cleanup
  sudo apt-get clean
  rm -rf ~/.bash_history ~/.ssh/authorized_keys
ENDSSH

# Create AMI
echo "Creating AMI (this takes a few minutes)..."
AMI_ID=$(aws ec2 create-image \
  --instance-id $INSTANCE_ID \
  --name "$AMI_NAME" \
  --description "Cyberdelias CTF Web Server - Application Baked In" \
  --no-reboot \
  --query 'ImageId' \
  --output text)

echo "AMI: $AMI_ID"
aws ec2 wait image-available --image-ids $AMI_ID

# Cleanup
echo "Cleaning up temporary instance..."
aws ec2 terminate-instances --instance-ids $INSTANCE_ID > /dev/null

# Make AMI public (optional - remove if you want to keep it private)
# echo "Making AMI public..."
# aws ec2 modify-image-attribute --image-id $AMI_ID --launch-permission "Add=[{Group=all}]"

echo ""
echo "=========================================="
echo "AMI Created Successfully!"
echo "=========================================="
echo "AMI ID: $AMI_ID"
echo ""
echo "Use this AMI ID in your CloudFormation template:"
echo "  ParameterKey=WebServerAMI,ParameterValue=$AMI_ID"
echo ""
