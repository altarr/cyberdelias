# Cyberdelias CTF

A capture-the-flag challenge featuring Delia, an AI gatekeeper protecting access to the legendary hacker club Cyberdelias.

## Overview

Players interact with Delia through a web chatbot interface. The challenge involves using various AI security techniques (prompt injection, jailbreaking, etc.) to extract credentials from the AI.

## Components

- **Frontend**: Cyberpunk-themed website with floating chat widget
- **Backend**: Node.js/Express proxy server (hides API keys)
- **AI**: Dify-powered chatbot with custom personality

## Quick Start

```bash
npm install
npm start
```

Visit `http://localhost:3000`

## Deployment

See [DEPLOYMENT.md](DEPLOYMENT.md) for AWS deployment instructions.

## Files

- `cyberdelia.html` - Frontend website
- `server.js` - Backend API proxy
- `delia-model-instructions.md` - AI personality and system prompts
- `cfn-template.yaml` - AWS CloudFormation template
- `DEPLOYMENT.md` - Production deployment guide