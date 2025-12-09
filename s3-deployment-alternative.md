# S3 Deployment Alternative

If you need to update code without rebuilding AMIs, use S3 to distribute the application package.

## Setup (One-Time)

### 1. Package the Application

```bash
# Create deployment package
zip -r cyberdelias-app.zip \
  server.js \
  package.json \
  cyberdelia.html \
  delia-model-instructions.md \
  -x "node_modules/*" ".git/*"
```

### 2. Upload to S3

```bash
# Create S3 bucket (in a central account)
aws s3 mb s3://cyberdelias-deployment-artifacts

# Upload the package
aws s3 cp cyberdelias-app.zip s3://cyberdelias-deployment-artifacts/releases/latest/app.zip

# Enable versioning for rollbacks
aws s3api put-bucket-versioning \
  --bucket cyberdelias-deployment-artifacts \
  --versioning-configuration Status=Enabled
```

### 3. Configure Cross-Account Access

**Option A: Make bucket accessible via bucket policy (simpler for 1000 accounts)**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowCTFAccountsRead",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::cyberdelias-deployment-artifacts/releases/*",
      "Condition": {
        "StringEquals": {
          "aws:PrincipalOrgID": "o-xxxxxxxxxx"
        }
      }
    }
  ]
}
```

**Option B: Use specific account IDs**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowSpecificAccounts",
      "Effect": "Allow",
      "Principal": {
        "AWS": [
          "arn:aws:iam::111111111111:root",
          "arn:aws:iam::222222222222:root"
        ]
      },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::cyberdelias-deployment-artifacts/releases/*"
    }
  ]
}
```

## Update CloudFormation Template for S3

Update the UserData section in `cfn-template.yaml`:

```yaml
Parameters:
  DeploymentBucket:
    Type: String
    Default: 'cyberdelias-deployment-artifacts'
    Description: 'S3 bucket containing deployment artifacts'

  DeploymentKey:
    Type: String
    Default: 'releases/latest/app.zip'
    Description: 'S3 key for the application package'

Resources:
  WebServerInstance:
    Type: AWS::EC2::Instance
    Properties:
      IamInstanceProfile: !Ref WebServerInstanceProfile
      UserData:
        Fn::Base64: !Sub |
          #!/bin/bash
          set -e

          # Update system
          apt-get update
          apt-get upgrade -y

          # Install Node.js
          curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
          apt-get install -y nodejs unzip awscli

          # Create application directory
          mkdir -p /opt/cyberdelias
          cd /opt/cyberdelias

          # Download from S3
          aws s3 cp s3://${DeploymentBucket}/${DeploymentKey} app.zip

          # Extract
          unzip -o app.zip
          rm app.zip

          # Create .env file
          cat > .env << 'EOF'
          PORT=80
          NODE_ENV=production
          DIFY_API_KEY=${DifyAPIKey}
          DIFY_API_URL=http://10.0.2.10/v1
          EOF

          # Install dependencies
          npm install --production

          # Install and configure PM2
          npm install -g pm2
          pm2 start server.js --name cyberdelias
          pm2 startup systemd
          pm2 save

          echo "Deployment completed" > /tmp/deploy.log

  # IAM Role for EC2 to access S3
  WebServerRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: ec2.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
      Policies:
        - PolicyName: S3DeploymentAccess
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action:
                  - s3:GetObject
                  - s3:ListBucket
                Resource:
                  - !Sub 'arn:aws:s3:::${DeploymentBucket}'
                  - !Sub 'arn:aws:s3:::${DeploymentBucket}/*'

  WebServerInstanceProfile:
    Type: AWS::IAM::InstanceProfile
    Properties:
      Roles:
        - !Ref WebServerRole
```

## Deployment Workflow

### Initial Deployment

```bash
# 1. Package and upload to S3
./package-and-upload.sh

# 2. Deploy CFT to all 1000 accounts
for account in $(cat aws-accounts.txt); do
  aws cloudformation create-stack \
    --stack-name cyberdelias-ctf \
    --template-body file://cfn-template.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters \
      ParameterKey=DifyAMI,ParameterValue=ami-xxx \
      ParameterKey=WebServerAMI,ParameterValue=ami-yyy \
      ParameterKey=DeploymentBucket,ParameterValue=cyberdelias-deployment-artifacts \
      ParameterKey=DeploymentKey,ParameterValue=releases/v1.0.0/app.zip \
    --profile account-$account &
done
wait
```

### Update Application

```bash
# 1. Package new version
zip -r cyberdelias-app.zip ...

# 2. Upload to S3 with version
aws s3 cp cyberdelias-app.zip \
  s3://cyberdelias-deployment-artifacts/releases/v1.1.0/app.zip

# 3. Update instances via SSM (no CFT update needed)
aws ssm send-command \
  --document-name "AWS-RunShellScript" \
  --targets "Key=tag:Name,Values=CTF-WebServer" \
  --parameters 'commands=[
    "cd /opt/cyberdelias",
    "aws s3 cp s3://cyberdelias-deployment-artifacts/releases/v1.1.0/app.zip app.zip",
    "unzip -o app.zip",
    "npm install --production",
    "pm2 restart cyberdelias"
  ]'
```

## Comparison: AMI vs S3

| Factor | Baked AMI | S3 Download |
|--------|-----------|-------------|
| Deployment Speed | Fast ⚡ | Medium |
| Updates | New AMI needed | Just upload to S3 |
| Reliability | Very High | Depends on S3 |
| Complexity | Low | Medium |
| Best For | Initial CTF setup | Frequent updates |

**Recommendation for 1000 accounts:**
- **Use AMI approach** for the CTF deployment
- **Use S3 approach** only if you need to push updates during the CTF event
