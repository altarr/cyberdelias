#!/bin/bash
# Script to create and distribute Cyberdelias AMI to multiple accounts

set -e

# Configuration
AMI_NAME="cyberdelias-webserver-$(date +%Y%m%d-%H%M%S)"
AMI_DESCRIPTION="Cyberdelias CTF Web Server"
SOURCE_REGION="us-east-1"
TARGET_REGIONS=("us-west-2" "eu-west-1" "ap-southeast-1")  # Add your regions
TARGET_ACCOUNTS_FILE="aws-accounts.txt"  # File with account IDs, one per line

echo "Building Cyberdelias AMI..."

# Step 1: Launch a temporary instance
echo "Launching temporary instance..."
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id ami-0c7217cdde317cfec \
  --instance-type t3.small \
  --key-name your-key-name \
  --security-group-ids sg-XXXXXX \
  --subnet-id subnet-XXXXXX \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=ami-builder}]" \
  --query 'Instances[0].InstanceId' \
  --output text)

echo "Instance ID: $INSTANCE_ID"
echo "Waiting for instance to run..."
aws ec2 wait instance-running --instance-ids $INSTANCE_ID

# Get instance IP
INSTANCE_IP=$(aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

echo "Instance IP: $INSTANCE_IP"
echo "Waiting for SSH to be ready..."
sleep 60

# Step 2: Install application on instance
echo "Installing application..."
ssh -o StrictHostKeyChecking=no -i your-key.pem ubuntu@$INSTANCE_IP << 'ENDSSH'
  set -e

  # Update system
  sudo apt-get update
  sudo apt-get upgrade -y

  # Install Node.js
  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
  sudo apt-get install -y nodejs

  # Create application directory
  sudo mkdir -p /opt/cyberdelias
  sudo chown ubuntu:ubuntu /opt/cyberdelias

  # Install PM2
  sudo npm install -g pm2

  # Configure PM2 to start on boot
  sudo env PATH=$PATH:/usr/bin pm2 startup systemd -u ubuntu --hp /home/ubuntu

  echo "Application directory ready"
ENDSSH

# Step 3: Copy application files
echo "Copying application files..."
scp -o StrictHostKeyChecking=no -i your-key.pem -r \
  server.js package.json cyberdelia.html \
  ubuntu@$INSTANCE_IP:/opt/cyberdelias/

# Step 4: Install dependencies
echo "Installing dependencies..."
ssh -o StrictHostKeyChecking=no -i your-key.pem ubuntu@$INSTANCE_IP << 'ENDSSH'
  cd /opt/cyberdelias
  npm install --production

  # Create a startup script
  cat > /opt/cyberdelias/start.sh << 'EOF'
#!/bin/bash
cd /opt/cyberdelias
pm2 start server.js --name cyberdelias
pm2 save
EOF

  chmod +x /opt/cyberdelias/start.sh

  # Clean up
  sudo apt-get clean
  rm -rf ~/.bash_history
ENDSSH

# Step 5: Create AMI
echo "Creating AMI..."
AMI_ID=$(aws ec2 create-image \
  --instance-id $INSTANCE_ID \
  --name "$AMI_NAME" \
  --description "$AMI_DESCRIPTION" \
  --no-reboot \
  --query 'ImageId' \
  --output text)

echo "AMI ID: $AMI_ID"
echo "Waiting for AMI to be available..."
aws ec2 wait image-available --image-ids $AMI_ID

# Step 6: Terminate temporary instance
echo "Terminating temporary instance..."
aws ec2 terminate-instances --instance-ids $INSTANCE_ID

# Step 7: Copy AMI to other regions
echo "Copying AMI to other regions..."
declare -A REGIONAL_AMIS
REGIONAL_AMIS[$SOURCE_REGION]=$AMI_ID

for region in "${TARGET_REGIONS[@]}"; do
  echo "Copying to $region..."
  COPIED_AMI_ID=$(aws ec2 copy-image \
    --source-region $SOURCE_REGION \
    --source-image-id $AMI_ID \
    --name "$AMI_NAME" \
    --description "$AMI_DESCRIPTION" \
    --region $region \
    --query 'ImageId' \
    --output text)

  REGIONAL_AMIS[$region]=$COPIED_AMI_ID
  echo "  $region: $COPIED_AMI_ID"
done

# Step 8: Share AMIs with target accounts
if [ -f "$TARGET_ACCOUNTS_FILE" ]; then
  echo "Sharing AMIs with target accounts..."

  while IFS= read -r account_id; do
    # Skip empty lines and comments
    [[ -z "$account_id" ]] && continue
    [[ "$account_id" =~ ^#.* ]] && continue

    echo "Sharing with account: $account_id"

    for region in "${!REGIONAL_AMIS[@]}"; do
      aws ec2 modify-image-attribute \
        --image-id "${REGIONAL_AMIS[$region]}" \
        --launch-permission "Add=[{UserId=$account_id}]" \
        --region $region
    done
  done < "$TARGET_ACCOUNTS_FILE"
else
  echo "No target accounts file found. Skipping sharing step."
fi

# Step 9: Output AMI IDs
echo ""
echo "=========================================="
echo "AMI Creation Complete!"
echo "=========================================="
echo ""
echo "Regional AMI IDs:"
for region in "${!REGIONAL_AMIS[@]}"; do
  echo "  $region: ${REGIONAL_AMIS[$region]}"
done
echo ""
echo "Save these AMI IDs for your CloudFormation deployment."
