# Cyberdelias Deployment Guide

## Architecture

- **Frontend**: Static HTML/CSS/JS (cyberdelia.html)
- **Backend**: Node.js/Express proxy server
- **AI Backend**: Dify server (private network)

## Local Development

1. **Install dependencies:**
```bash
npm install
```

2. **Start the server:**
```bash
npm start
```

3. **Access the site:**
```
http://localhost:3000
```

## Production Deployment on AWS

### Prerequisites
- Web server EC2 instance (10.0.1.10)
- Dify server EC2 instance (10.0.2.10) - private
- Node.js installed on web server

### Deployment Steps

**1. Connect to your web server:**
```bash
ssh -i your-key.pem ubuntu@<web-server-public-ip>
```

**2. Install Node.js:**
```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs
```

**3. Clone/upload your code:**
```bash
# Option A: Git clone
git clone <your-repo-url>
cd cyberdelias

# Option B: Upload files directly
# Use scp or sftp to upload the project files
```

**4. Create .env file:**
```bash
cp .env.example .env
nano .env
```

Edit the .env file:
```
PORT=80
NODE_ENV=production
DIFY_API_KEY=app-Z3TEMkZSNuUjvltxnIgfhC2l
DIFY_API_URL=http://10.0.2.10/v1
```

**5. Install dependencies:**
```bash
npm install --production
```

**6. Run with PM2 (recommended for production):**
```bash
# Install PM2
sudo npm install -g pm2

# Start the server
sudo pm2 start server.js --name cyberdelias

# Set PM2 to start on boot
sudo pm2 startup
sudo pm2 save
```

**7. Alternative: Run with systemd:**
Create `/etc/systemd/system/cyberdelias.service`:
```ini
[Unit]
Description=Cyberdelias CTF Server
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/cyberdelias
Environment=NODE_ENV=production
ExecStart=/usr/bin/node server.js
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

Then:
```bash
sudo systemctl enable cyberdelias
sudo systemctl start cyberdelias
sudo systemctl status cyberdelias
```

**8. Configure firewall (if needed):**
```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```

## Testing

**Test the backend:**
```bash
curl http://localhost/api/health
```

**Test the chat endpoint:**
```bash
curl -X POST http://localhost/api/chat \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello Delia"}'
```

## Monitoring

**View logs with PM2:**
```bash
pm2 logs cyberdelias
```

**View logs with systemd:**
```bash
sudo journalctl -u cyberdelias -f
```

## Updating

**With PM2:**
```bash
git pull  # or upload new files
npm install
pm2 restart cyberdelias
```

**With systemd:**
```bash
git pull  # or upload new files
npm install
sudo systemctl restart cyberdelias
```

## Troubleshooting

**Check if server is running:**
```bash
pm2 status
# or
sudo systemctl status cyberdelias
```

**Check port binding:**
```bash
sudo netstat -tlnp | grep :80
```

**Test Dify connectivity from web server:**
```bash
curl http://10.0.2.10/v1
```

## Security Notes

- API key is now hidden from frontend users
- All communication to Dify goes through the backend proxy
- The .env file should never be committed to git
- Consider adding rate limiting for production
