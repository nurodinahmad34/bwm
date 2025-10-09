#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}📦 Bandwidth Monitor Installer${NC}"
echo "======================================"

# Check root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ Please run as root: sudo bash install.sh${NC}"
    exit 1
fi

# Install dependencies
echo -e "${YELLOW}🔧 Installing dependencies...${NC}"
apt update && apt install -y vnstat bc curl

# Setup vnstat
echo -e "${YELLOW}📊 Setting up vnstat...${NC}"
vnstat --add -i ens3
systemctl enable vnstat
systemctl start vnstat

# Download main script
echo -e "${YELLOW}📥 Downloading bandwidth monitor...${NC}"
wget -q -O /usr/local/bin/bwm.sh "https://raw.githubusercontent.com/YOUR_USERNAME/bwm/main/bwm.sh"
chmod +x /usr/local/bin/bwm.sh

# Create log file
touch /var/log/bwm.log
chmod 644 /var/log/bwm.log

# Setup crontab
echo -e "${YELLOW}⏰ Setting up crontab...${NC}"
(crontab -l 2>/dev/null | grep -v "/usr/local/bin/bwm.sh"; echo "0 19 * * * /usr/local/bin/bwm.sh") | crontab -

# Test
echo -e "${YELLOW}🧪 Testing...${NC}"
sleep 10
/usr/local/bin/bwm.sh

echo -e "${GREEN}"
echo "🎉 INSTALLATION COMPLETED!"
echo "✅ Run: bwm.sh"
echo "✅ Logs: tail -f /var/log/bwm.log"
echo -e "${NC}"
