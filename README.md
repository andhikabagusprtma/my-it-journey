# 🛡️ My IT Journey: NOC → SRE

Automated network monitoring system with:
- Real-time connectivity checks (8.8.8.8, google.com, 1.1.1.1)
- Root cause diagnosis (gateway, interface, DNS)
- Auto-remediation for common network issues

## 🚀 Setup & Usage

### Run manually
1. git clone https://github.com/andhikabagusprtma/my-it-journey.git
2. cd my-it-journey
3. ls -la
4. chmod +x scripts/*.sh (chmod +x scripts/monitor.sh)
5. ./scripts/monitor.sh

### Auto-Run with cron (every 5 minutes)
1. crontab -e
2. */5 * * * * /home/username/my-it-journey/scripts/monitor.sh
3. chmod +x /home/username/my-it-journey/scripts/monitor.sh
4. start cron
5. check cron status

# Checking your username (Example for user "gael"):
- Run 'whoami' in WSL to verify your username
- */5 * * * * /home/gael/my-it-journey/scripts/monitor.sh

# Start cron (WSL2 only)
- sudo systemctl start cron

# Stop cron
- sudo systemctl stop cron (if you want this program to stop)

# Check cron status
- systemctl status cron

## ⚠️ NOTES
- Warnings like sudo: unable to resolve host are safe to ignore in WSL2.
- First run creates logs/, alerts/, and diagnosis/ folders automatically.

## 📁 Structure
- `scripts/monitor.sh` → main monitoring logic  
- `scripts/remediate.sh` → auto-fix network problems  
- `logs/`, `alerts/` → runtime output  

Built with Bash on WSL2 • Day 3 of 365 (2026)
