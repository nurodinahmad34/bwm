#!/bin/bash

echo "🗑️ Uninstalling Bandwidth Monitor..."

# Remove script
rm -f /usr/local/bin/bwm.sh

# Remove from crontab
(crontab -l | grep -v "/usr/local/bin/bwm.sh") | crontab -

# Remove log file (optional)
echo "Hapus log file? (y/n)"
read answer
if [ "$answer" = "y" ]; then
    rm -f /var/log/bwm.log
fi

echo "✅ Bandwidth Monitor uninstalled!"
