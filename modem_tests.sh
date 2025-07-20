#!/bin/bash
# ModemManager Commands for Quectel Modems
# After enabling ModemManager service

echo "=== ModemManager Quectel Commands ==="

# 1. List detected modems
echo "📱 List all modems:"
echo "mmcli -L"
echo ""

# 2. Get detailed modem information
echo "🔍 Get modem details (replace X with modem number):"
echo "mmcli -m X"
echo ""

# 3. Check modem status
echo "📊 Check modem status:"
echo "mmcli -m X --query-status"
echo ""

# 4. Get signal strength
echo "📶 Signal strength:"
echo "mmcli -m X --signal-get"
echo ""

# 5. SIM card information
echo "📱 SIM info:"
echo "mmcli -m X --sim-get"
echo ""

# 6. Enable modem (if disabled)
echo "🔌 Enable modem:"
echo "mmcli -m X --enable"
echo ""

# 7. Create connection (replace with your APN)
echo "🌐 Create connection profile:"
echo "mmcli -m X --simple-connect=\"apn=diginet\""
echo ""

# Alternative for Malaysia carriers:
echo "# For different Malaysian carriers:"
echo "# DiGi: mmcli -m X --simple-connect=\"apn=diginet\""
echo "# Maxis: mmcli -m X --simple-connect=\"apn=unet\""
echo "# Celcom: mmcli -m X --simple-connect=\"apn=celcom3g\""
echo ""

# 8. Check connection status
echo "📡 Check connection:"
echo "mmcli -m X --query-bearer"
echo ""

# 9. Disconnect
echo "❌ Disconnect:"
echo "mmcli -m X --simple-disconnect"
echo ""

# 10. Monitor connection
echo "👁️  Monitor (continuous):"
echo "watch -n 2 'mmcli -m X --query-status'"
echo ""

# NetworkManager integration
echo "=== NetworkManager Integration ==="
echo "If using desktop GUI:"
echo "1. ModemManager will auto-detect the modem"
echo "2. Network settings will show mobile broadband option"
echo "3. Can configure APN through GUI"
echo ""

# Troubleshooting commands
echo "=== Troubleshooting ==="
echo "🔧 Reset modem:"
echo "mmcli -m X --reset"
echo ""

echo "🔍 Debug logs:"
echo "journalctl -u ModemManager -f"
echo ""

echo "📊 List all bearers:"
echo "mmcli -L --bearers"
echo ""

# GPS commands (if supported)
echo "=== GPS Commands (if supported) ==="
echo "🗺️  Enable GPS:"
echo "mmcli -m X --location-enable-gps-raw"
echo ""

echo "📍 Get location:"
echo "mmcli -m X --location-get"
echo ""

# Complete example workflow
echo "=== Complete Connection Example ==="
echo "# 1. List modems"
echo "mmcli -L"
echo ""
echo "# 2. Enable modem (use actual modem number)"
echo "mmcli -m 0 --enable"
echo ""
echo "# 3. Connect with APN"
echo "mmcli -m 0 --simple-connect=\"apn=diginet\""
echo ""
echo "# 4. Check IP address"
echo "ip addr show wwan0"
echo ""
echo "# 5. Test connectivity"
echo "ping google.com"