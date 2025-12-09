# CloudFormation Deployment Guide

## Deployment Options

You have two ways to deploy the application via CloudFormation:

### Option 1: Using Git Repository (Recommended)

The CFT will automatically clone your code from a Git repository.

**Steps:**

1. **Push your code to a Git repository:**
```bash
git add .
git commit -m "Initial commit"
git push origin main
```

2. **Deploy the CloudFormation stack:**
```bash
aws cloudformation create-stack \
  --stack-name cyberdelias-ctf \
  --template-body file://cfn-template.yaml \
  --parameters \
    ParameterKey=DifyAMI,ParameterValue=ami-XXXXXXXXX \
    ParameterKey=WebServerAMI,ParameterValue=ami-XXXXXXXXX \
    ParameterKey=KeyName,ParameterValue=your-key-name \
    ParameterKey=SSHLocation,ParameterValue=YOUR_IP/32 \
    ParameterKey=GitRepoURL,ParameterValue=https://github.com/yourusername/cyberdelias.git \
    ParameterKey=DifyAPIKey,ParameterValue=app-Z3TEMkZSNuUjvltxnIgfhC2l
```

### Option 2: Bake Into AMI

Create a custom AMI with the application pre-installed.

**Steps:**

1. **Launch a temporary Ubuntu instance**

2. **Install and configure the application:**
```bash
# Install Node.js
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs git

# Create application directory
sudo mkdir -p /opt/cyberdelias
sudo chown ubuntu:ubuntu /opt/cyberdelias
cd /opt/cyberdelias

# Upload your files (use scp or git clone)
# Example with scp from your local machine:
# scp -r -i your-key.pem ./* ubuntu@instance-ip:/opt/cyberdelias/

# Install dependencies
npm install --production

# Install PM2
sudo npm install -g pm2

# Create a startup script
cat > /opt/cyberdelias/start.sh << 'EOF'
#!/bin/bash
cd /opt/cyberdelias
pm2 start server.js --name cyberdelias
pm2 save
EOF

chmod +x /opt/cyberdelias/start.sh
```

3. **Create the AMI:**
```bash
# From your local machine
aws ec2 create-image \
  --instance-id i-XXXXXXXXX \
  --name "cyberdelias-webserver-v1" \
  --description "Cyberdelias web server with Node.js app" \
  --no-reboot
```

4. **Update UserData to use the AMI:**

Edit the CFT to add this UserData instead:
```yaml
UserData:
  Fn::Base64: !Sub |
    #!/bin/bash
    # Create .env file
    cat > /opt/cyberdelias/.env << 'EOF'
    PORT=80
    NODE_ENV=production
    DIFY_API_KEY=${DifyAPIKey}
    DIFY_API_URL=http://10.0.2.10/v1
    EOF

    # Start the application
    cd /opt/cyberdelias
    pm2 start server.js --name cyberdelias
    pm2 startup systemd
    pm2 save
```

5. **Deploy with your custom AMI:**
```bash
aws cloudformation create-stack \
  --stack-name cyberdelias-ctf \
  --template-body file://cfn-template.yaml \
  --parameters \
    ParameterKey=DifyAMI,ParameterValue=ami-XXXXXXXXX \
    ParameterKey=WebServerAMI,ParameterValue=ami-YOUR_CUSTOM_AMI \
    ParameterKey=KeyName,ParameterValue=your-key-name \
    ParameterKey=SSHLocation,ParameterValue=YOUR_IP/32 \
    ParameterKey=DifyAPIKey,ParameterValue=app-Z3TEMkZSNuUjvltxnIgfhC2l
```

## Monitoring Deployment

**Check CloudFormation stack status:**
```bash
aws cloudformation describe-stacks \
  --stack-name cyberdelias-ctf \
  --query 'Stacks[0].StackStatus'
```

**Get the web server public IP:**
```bash
aws cloudformation describe-stacks \
  --stack-name cyberdelias-ctf \
  --query 'Stacks[0].Outputs[?OutputKey==`WebServerPublicIP`].OutputValue' \
  --output text
```

**SSH into the web server to check deployment:**
```bash
WEB_IP=$(aws cloudformation describe-stacks \
  --stack-name cyberdelias-ctf \
  --query 'Stacks[0].Outputs[?OutputKey==`WebServerPublicIP`].OutputValue' \
  --output text)

ssh -i your-key.pem ubuntu@$WEB_IP

# Check if deployment completed
cat /tmp/cyberdelias-deploy.log

# Check if the app is running
pm2 status

# View logs
pm2 logs cyberdelias
```

## Updating the Application

**Option 1: With Git (if using GitRepoURL):**
```bash
ssh -i your-key.pem ubuntu@$WEB_IP
cd /opt/cyberdelias
git pull
npm install
pm2 restart cyberdelias
```

**Option 2: Update AMI and redeploy stack:**
1. Create a new AMI with updated code
2. Update the stack with new AMI ID:
```bash
aws cloudformation update-stack \
  --stack-name cyberdelias-ctf \
  --use-previous-template \
  --parameters \
    ParameterKey=WebServerAMI,ParameterValue=ami-NEW_AMI_ID \
    ParameterKey=DifyAMI,UsePreviousValue=true \
    ParameterKey=KeyName,UsePreviousValue=true \
    ParameterKey=SSHLocation,UsePreviousValue=true \
    ParameterKey=DifyAPIKey,UsePreviousValue=true
```

## Troubleshooting

**UserData didn't run:**
```bash
# Check cloud-init logs
sudo cat /var/log/cloud-init-output.log
```

**Application not starting:**
```bash
cd /opt/cyberdelias
cat /tmp/cyberdelias-deploy.log
pm2 logs cyberdelias --lines 100
```

**Can't reach the website:**
```bash
# Check if app is running
pm2 status

# Check if port 80 is listening
sudo netstat -tlnp | grep :80

# Test locally on the server
curl http://localhost/api/health
```

## Cleanup

**Delete the stack:**
```bash
aws cloudformation delete-stack --stack-name cyberdelias-ctf

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name cyberdelias-ctf
```

This will delete all resources created by the stack (VPC, subnets, instances, etc.).
