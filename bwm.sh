#!/bin/bash

# Konfigurasi
BOT_TOKEN="8054048255:AAHrEvs_qClO6DGXyiPzCcWJB8-D1KHekyQ"
CHAT_ID="5347438783"
LOG_FILE="/var/log/bwm.log"
INTERFACE="ens3"
BULANAN_LIMIT="5"

# Fungsi untuk mencatat log
catat_log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Cek dependensi
cek_dependensi() {
    for dep in vnstat bc curl; do
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
    if [ $? -eq 0 ]; then
        catat_log "Pesan Telegram berhasil dikirim"
        return 0
    else
        catat_log "ERROR: Gagal mengirim pesan Telegram"
        return 1
    fi
}

# Fungsi utama
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
        if (( $(echo "$persentase > 80" | bc -l) )); then
            PESAN="${PESAN}
            
⚠️ <b>PERINGATAN:</b> Penggunaan mendekati limit!"
        elif (( $(echo "$persentase > 95" | bc -l) )); then
            PESAN="${PESAN}
            
🚨 <b>PERINGATAN TINGGI:</b> Kuota hampir habis!"
        fi
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

main
