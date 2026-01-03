# 🛡️ My IT Journey: NOC → SRE

Automated network monitoring system with:
- Real-time connectivity checks (8.8.8.8, google.com, 1.1.1.1)
- Root cause diagnosis (gateway, interface, DNS)
- Auto-remediation for common network issues

## 🚀 Setup & Usage

### ▶️ Run manually
1. git clone https://github.com/andhikabagusprtma/my-it-journey.git
2. cd my-it-journey
3. (Optional) Check folder structure after first run, you’ll see:
   - `scripts/`
   - `logs/`, `alerts/`, `diagnosis/` (created automatically)
4. chmod +x scripts/*.sh
5. ./scripts/monitor.sh

### 🔄 Auto-Run with cron (every 5 minutes)
1. crontab -e
2. */5 * * * * /home/username/my-it-journey/scripts/monitor.sh
3. sudo systemctl start cron
4. systemctl status cron

## 🛠️ System Management (cron)

== ▶️ Start cron
- sudo systemctl start cron
- sudo systemctl enable cron → Optional: auto-start on boot
== ⏹️ Stop cron
- sudo systemctl stop cron → If you want this program to stop
== 📊 Check cron status
- systemctl status cron
💡 Note: Stopping cron won’t stop a currently running script it only prevents future runs.

## ⚠️ NOTES
- Warnings like sudo: unable to resolve host are safe to ignore in WSL2.
- First run creates logs/, alerts/, and diagnosis/ folders automatically.
- Find your username with: 'whoami'

## 📁 Structure
- `scripts/monitor.sh` → main monitoring logic  
- `scripts/remediate.sh` → auto-fix network problems  
- `logs/`, `alerts/` → runtime output  

Built with Bash on WSL2 • Day 3 of 365 (2026)
