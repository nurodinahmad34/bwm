cat << 'EOF' > /tmp/bwm_complete.sh
#!/bin/bash

echo "🤖 Memulai instalasi BWM Bot Interaktif Lengkap..."

# Install dependencies
echo "🔧 Menginstall dependencies..."
apt update && apt install -y vnstat bc curl jq

# Setup vnstat
echo "📊 Setup vnstat..."
vnstat --add -i ens3
systemctl enable vnstat
systemctl start vnstat

# Create main monitoring script
echo "📝 Membuat script bwm interaktif..."
cat > /usr/local/bin/bwm << 'SCRIPTEOF'
#!/bin/bash

# ================================
# KONFIGURASI BOT TELEGRAM
# ================================
BOT_TOKEN="8054048255:AAHrEvs_qClO6DGXyiPzCcWJB8-D1KHekyQ"
CHAT_ID="5347438783"

# Konfigurasi lainnya
LOG_FILE="/var/log/bwm.log"
INTERFACE="ens3"
BULANAN_LIMIT="5"

# Fungsi untuk mencatat log
catat_log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Cek dependensi
cek_dependensi() {
    for dep in vnstat bc curl jq; do
        if ! command -v "$dep" &> /dev/null; then
            catat_log "ERROR: $dep tidak ditemukan"
            exit 1
        fi
    done
}

# Fungsi untuk mendapatkan IP Address VPS (AUTO DETECT)
dapatkan_ip_vps() {
    local ip_public=$(curl -s -4 ifconfig.me 2>/dev/null || curl -s -4 icanhazip.com 2>/dev/null || ip addr show $INTERFACE | grep -oP 'inet \K[\d.]+' | head -1)
    local ip_local=$(hostname -I | awk '{print $1}')
    echo "🌐 Public: $ip_public | 🔗 Local: $ip_local"
}

# Fungsi untuk mendapatkan informasi sistem
dapatkan_info_sistem() {
    local hostname=$(hostname)
    local os=$(lsb_release -d | cut -f2- 2>/dev/null || echo "Ubuntu")
    local uptime=$(uptime -p | sed 's/up //')
    local first_date=$(vnstat -i $INTERFACE 2>/dev/null | grep "first day:" | cut -d':' -f2- | sed 's/^ *//')
    if [ -z "$first_date" ]; then
        first_date="Data belum tersedia"
    fi
    echo "🖥️ $hostname | $os | ⏰ $uptime"
    echo "📅 Data sejak: $first_date"
}

# Fungsi untuk mengkonversi ke GiB
konversi_ke_gib() {
    local value=$1
    local unit=$2
    case $unit in
        "MiB") echo "scale=2; $value / 1024" | bc 2>/dev/null || echo "0" ;;
        "GiB") echo "$value" ;;
        "TiB") echo "scale=2; $value * 1024" | bc 2>/dev/null || echo "0" ;;
        "KiB") echo "scale=2; $value / 1048576" | bc 2>/dev/null || echo "0" ;;
        *) echo "0" ;;
    esac
}

# Fungsi untuk mendapatkan penggunaan bandwidth harian
dapatkan_penggunaan_harian() {
    local today=$(date +'%Y-%m-%d')
    local output=$(vnstat -i $INTERFACE -d 2>/dev/null | grep "$today")
    if [ -z "$output" ]; then
        echo "0|0|0"
        return
    fi
    local rx_value=$(echo "$output" | awk '{print $2}')
    local rx_unit=$(echo "$output" | awk '{print $3}')
    local tx_value=$(echo "$output" | awk '{print $5}')
    local tx_unit=$(echo "$output" | awk '{print $6}')
    local total_value=$(echo "$output" | awk '{print $8}')
    local total_unit=$(echo "$output" | awk '{print $9}')
    local rx_gib=$(konversi_ke_gib "$rx_value" "$rx_unit")
    local tx_gib=$(konversi_ke_gib "$tx_value" "$tx_unit")
    local total_gib=$(konversi_ke_gib "$total_value" "$total_unit")
    echo "${total_gib}|${rx_gib}|${tx_gib}"
}

# Fungsi untuk mendapatkan TOTAL KUMULATIF sejak awal
dapatkan_total_kumulatif() {
    local output=$(vnstat -i $INTERFACE 2>/dev/null)
    local total_line=$(echo "$output" | grep -E "total:|all time:" | head -1)
    if [ -z "$total_line" ]; then
        echo "0|0|0"
        return
    fi
    local rx_value=$(echo "$total_line" | awk '{print $2}')
    local rx_unit=$(echo "$total_line" | awk '{print $3}')
    local tx_value=$(echo "$total_line" | awk '{print $5}')
    local tx_unit=$(echo "$total_line" | awk '{print $6}')
    local total_value=$(echo "$total_line" | awk '{print $8}')
    local total_unit=$(echo "$total_line" | awk '{print $9}')
    if [ -z "$rx_value" ] || [ "$rx_value" = "total:" ]; then
        rx_value=$(echo "$total_line" | awk '{print $3}')
        rx_unit=$(echo "$total_line" | awk '{print $4}')
        tx_value=$(echo "$total_line" | awk '{print $6}')
        tx_unit=$(echo "$total_line" | awk '{print $7}')
        total_value=$(echo "$total_line" | awk '{print $9}')
        total_unit=$(echo "$total_line" | awk '{print $10}')
    fi
    local rx_gib=$(konversi_ke_gib "$rx_value" "$rx_unit")
    local tx_gib=$(konversi_ke_gib "$tx_value" "$tx_unit")
    local total_gib=$(konversi_ke_gib "$total_value" "$total_unit")
    echo "${total_gib}|${rx_gib}|${tx_gib}"
}

# Fungsi untuk mengirim pesan ke Telegram
kirim_pesan_telegram() {
    local PESAN="$1"
    local response=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        -d "text=${PESAN}" \
        -d "parse_mode=HTML")
    if echo "$response" | jq -e '.ok' >/dev/null; then
        catat_log "Pesan Telegram berhasil dikirim"
        return 0
    else
        catat_log "ERROR: Gagal mengirim pesan Telegram"
        return 1
    fi
}

# ⚡ FUNGSI BACKUP2 INTERAKTIF ⚡
jalankan_backup2() {
    catat_log "Menjalankan command backup2..."
    
    # Kirim notifikasi mulai backup
    kirim_pesan_telegram "🔄 <b>Memulai Backup...</b>\n⏰ $(date '+%H:%M:%S')\n\n[ INFO ] Processing...\n[ INFO ] Mohon Ditunggu..."
    
    # ⚡ JALANKAN BACKUP2 ASLI DAN TANGKAP OUTPUT ⚡
    local backup_output=$(/usr/local/sbin/backup2 2>&1)
    
    # Cek apakah backup berhasil
    local exit_code=$?
    
    catat_log "Backup selesai. Exit code: $exit_code"
    catat_log "Output: $backup_output"
    
    # Format output untuk Telegram
    if [ $exit_code -eq 0 ]; then
        # Backup sukses
        if [ -n "$backup_output" ]; then
            # Jika ada output, kirim outputnya
            kirim_pesan_telegram "✅ <b>Backup Berhasil!</b>\n\n<code>$backup_output</code>\n\n⏰ Selesai: $(date '+%H:%M:%S')"
        else
            # Jika tidak ada output, kirim pesan default
            kirim_pesan_telegram "✅ <b>Backup Berhasil!</b>\n\n⏰ Selesai: $(date '+%H:%M:%S')"
        fi
    else
        # Backup gagal
        kirim_pesan_telegram "❌ <b>Backup Gagal!</b>\nExit Code: $exit_code\n\n<code>$backup_output</code>\n\n⏰ Selesai: $(date '+%H:%M:%S')"
    fi
    
    echo "$backup_output"
    return $exit_code
}

# Fungsi untuk memproses command dari user
proses_command() {
    local command="$1"
    
    case "$command" in
        "/start")
            kirim_pesan_telegram "🤖 <b>BWM Bot Aktif!</b>\n\nPerintah yang tersedia:\n• /status - Status bandwidth\n• /backup2 - Jalankan backup\n• /info - Info server\n• /help - Bantuan"
            ;;
            
        "/status"|"/bwm")
            # Jalankan monitoring seperti biasa
            main
            ;;
            
        "/backup2"|"/backup")
            jalankan_backup2
            ;;
            
        "/info")
            local info_sistem=$(dapatkan_info_sistem)
            local info_ip=$(dapatkan_ip_vps)
            kirim_pesan_telegram "🖥️ <b>Informasi Server</b>\n\n<code>$info_sistem</code>\n<code>$info_ip</code>\n\n⏰ $(date '+%H:%M:%S')"
            ;;
            
        "/help")
            kirim_pesan_telegram "📋 <b>Bantuan BWM Bot</b>\n\nPerintah:\n• /status - Cek bandwidth\n• /backup2 - Jalankan backup\n• /info - Info server\n• /help - Bantuan ini\n\n⚡ Bot aktif: $(uptime -p)"
            ;;
            
        *)
            kirim_pesan_telegram "❌ Perintah tidak dikenali: <code>$command</code>\n\nKetik /help untuk melihat perintah yang tersedia."
            ;;
    esac
}

# Fungsi untuk mendengarkan perintah dari Telegram
listen_commands() {
    echo "🔍 Mendengarkan perintah dari Telegram..."
    catat_log "Memulai listener untuk perintah Telegram"
    
    local last_update_id=0
    
    while true; do
        # Get updates from Telegram
        local response=$(curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getUpdates?offset=$((last_update_id + 1))&timeout=30")
        
        if echo "$response" | jq -e '.result | length > 0' >/dev/null; then
            # Process each update
            local update_count=$(echo "$response" | jq '.result | length')
            
            for ((i=0; i<update_count; i++)); do
                local update_id=$(echo "$response" | jq -r ".result[$i].update_id")
                local chat_id=$(echo "$response" | jq -r ".result[$i].message.chat.id")
                local text=$(echo "$response" | jq -r ".result[$i].message.text")
                
                # Update last_update_id
                last_update_id=$update_id
                
                # Only process if from authorized chat
                if [ "$chat_id" = "$CHAT_ID" ]; then
                    catat_log "Received command: $text from $chat_id"
                    echo "📩 Command received: $text"
                    
                    # Process the command
                    proses_command "$text"
                else
                    catat_log "Unauthorized access attempt from: $chat_id"
                fi
            done
        fi
        
        sleep 1
    done
}

# Fungsi utama untuk monitoring
main() {
    cek_dependensi
    catat_log "Memulai monitoring bandwidth..."
    
    local harian_data=$(dapatkan_penggunaan_harian)
    local total_harian=$(echo "$harian_data" | cut -d'|' -f1)
    local rx_harian=$(echo "$harian_data" | cut -d'|' -f2)
    local tx_harian=$(echo "$harian_data" | cut -d'|' -f3)
    
    local kumulatif_data=$(dapatkan_total_kumulatif)
    local total_kumulatif=$(echo "$kumulatif_data" | cut -d'|' -f1)
    local rx_kumulatif=$(echo "$kumulatif_data" | cut -d'|' -f2)
    local tx_kumulatif=$(echo "$kumulatif_data" | cut -d'|' -f3)
    
    local info_sistem=$(dapatkan_info_sistem)
    local info_ip=$(dapatkan_ip_vps)
    local first_date=$(vnstat -i $INTERFACE 2>/dev/null | grep "first day:" | cut -d':' -f2- | sed 's/^ *//')
    if [ -z "$first_date" ]; then
        first_date="Data belum tersedia"
    fi

    local PESAN="<b>📊 LAPORAN BANDWIDTH HARIAN</b>
    
<b>🖥️ INFORMASI SERVER:</b>
<code>$info_sistem</code>
<code>$info_ip</code>

<b>📈 PENGGUNAAN BANDWIDTH:</b>
• <b>Hari Ini ($(date +'%d/%m/%Y')):</b>
  - Total: <code>${total_harian} GiB</code>
  - Download (RX): <code>${rx_harian} GiB</code>
  - Upload (TX): <code>${tx_harian} GiB</code>

• <b>Total Kumulatif (sejak $first_date):</b>
  - Total: <code>${total_kumulatif} GiB</code>
  - Download (RX): <code>${rx_kumulatif} GiB</code>
  - Upload (TX): <code>${tx_kumulatif} GiB</code>"

    if [ "$BULANAN_LIMIT" -gt 0 ]; then
        local limit_bulanan_gib=$(echo "$BULANAN_LIMIT * 1024" | bc)
        local persentase=$(echo "scale=2; ($total_kumulatif / $limit_bulanan_gib) * 100" | bc 2>/dev/null || echo "0")
        PESAN="${PESAN}
        
<b>📊 LIMIT BULANAN (${BULANAN_LIMIT} TB):</b>
• <b>Digunakan:</b> <code>${persentase}%</code>
• <b>Sisa Kuota:</b> <code>$(echo "scale=2; $limit_bulanan_gib - $total_kumulatif" | bc) GiB</code>"
    fi

    PESAN="${PESAN}
    
<b>⏰ Update:</b> <code>$(date +'%H:%M:%S')</code>"

    if kirim_pesan_telegram "$PESAN"; then
        echo "✅ Laporan berhasil dikirim ke Telegram"
        catat_log "SUKSES: Harian: ${total_harian}GiB, Kumulatif: ${total_kumulatif}GiB"
    else
        echo "❌ Gagal mengirim laporan"
        catat_log "ERROR: Gagal mengirim laporan"
    fi
}

# Check if we should run listener or normal monitoring
if [ "$1" = "listen" ] || [ "$1" = "daemon" ]; then
    listen_commands
elif [ "$1" = "backup" ] || [ "$1" = "backup2" ]; then
    jalankan_backup2
elif [ "$1" = "status" ]; then
    main
else
    # Default: show help
    echo "🤖 BWM Bot Interaktif"
    echo "Usage:"
    echo "  bwm              - Monitoring bandwidth"
    echo "  bwm listen       - Jalankan bot listener"
    echo "  bwm backup2      - Jalankan backup"
    echo "  bwm status       - Status bandwidth"
    echo ""
    echo "📋 Perintah Telegram:"
    echo "  /start   - Mulai bot"
    echo "  /status  - Status bandwidth" 
    echo "  /backup2 - Jalankan backup"
    echo "  /info    - Info server"
    echo "  /help    - Bantuan"
fi
SCRIPTEOF

chmod +x /usr/local/bin/bwm

# Create systemd service for bot listener
echo "📁 Membuat service untuk bot listener..."
cat > /etc/systemd/system/bwm-bot.service << SERVICEEOF
[Unit]
Description=BWM Telegram Bot Listener
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/bwm listen
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICEEOF

# Setup log file
touch /var/log/bwm.log
chmod 644 /var/log/bwm.log

# Setup crontab for daily monitoring
(crontab -l 2>/dev/null | grep -v "/usr/local/bin/bwm"; echo "0 19 * * * /usr/local/bin/bwm") | crontab -

# Start services
systemctl daemon-reload
systemctl enable bwm-bot
systemctl start bwm-bot

echo ""
echo "🎉 BOT INTERAKTIF BERHASIL DIINSTAL!"
echo ""
echo "🤖 PERINTAH TELEGRAM:"
echo "  /start   - Mulai bot"
echo "  /status  - Cek bandwidth"
echo "  /backup2 - ⚡ JALANKAN BACKUP ⚡"
echo "  /info    - Info server"
echo "  /help    - Bantuan"
echo ""
echo "⚙️  PERINTAH DI VPS:"
echo "  bwm              - Monitoring"
echo "  bwm listen       - Jalankan bot"
echo "  bwm backup2      - Backup manual"
echo "  bwm status       - Status"
echo ""
echo "📊 SERVICE:"
echo "  systemctl status bwm-bot  - Cek status bot"
echo "  journalctl -u bwm-bot -f  - Lihat log live"
echo "  tail -f /var/log/bwm.log  - Lihat log file"
echo ""

# Test run
sleep 3
echo "🚀 Testing bot..."
/usr/local/bin/bwm status

EOF

bash /tmp/bwm_complete.sh
