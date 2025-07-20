#!/bin/bash
# ModemManager Quick Setup for Quectel Modems

echo "=== ModemManager Quick Setup ==="

# Enable ModemManager
echo "🔌 Enabling ModemManager..."
sudo systemctl unmask ModemManager
sudo systemctl enable ModemManager
sudo systemctl start ModemManager

# Wait for service to start
echo "⏳ Waiting for ModemManager to start..."
sleep 5

# Check if ModemManager is running
if systemctl is-active --quiet ModemManager; then
    echo "✅ ModemManager is running"
else
    echo "❌ ModemManager failed to start"
    exit 1
fi

# Wait for modem detection
echo "🔍 Waiting for modem detection..."
sleep 10

# List detected modems
echo ""
echo "📱 Detected modems:"
mmcli -L

# Get modem number
MODEM_NUM=$(mmcli -L | grep -o '/org/freedesktop/ModemManager1/Modem/[0-9]*' | tail -1 | grep -o '[0-9]*$')

if [ -z "$MODEM_NUM" ]; then
    echo "❌ No modem detected by ModemManager"
    echo "   Troubleshooting:"
    echo "   - Check hardware connection"
    echo "   - Wait longer for detection"
    echo "   - Check with: journalctl -u ModemManager -f"
    exit 1
fi

echo "✅ Using modem number: $MODEM_NUM"

# Get modem details
echo ""
echo "📊 Modem information:"
mmcli -m $MODEM_NUM

# Enable modem if not enabled
echo ""
echo "🔌 Enabling modem..."
mmcli -m $MODEM_NUM --enable
sleep 3

# Check status
echo ""
echo "📊 Modem status:"
mmcli -m $MODEM_NUM --query-status

# Check signal
echo ""
echo "📶 Signal strength:"
mmcli -m $MODEM_NUM --signal-get 2>/dev/null || echo "Signal info not available yet"

echo ""
echo "🎉 ModemManager setup complete!"
echo ""
echo "📋 Next steps:"
echo "1. Connect: mmcli -m $MODEM_NUM --simple-connect=\"apn=diginet\""
echo "2. Check IP: ip addr show wwan0"
echo "3. Test: ping google.com"
echo "4. Monitor: watch -n 2 'mmcli -m $MODEM_NUM --query-status'"
echo ""
echo "🔧 If connection fails:"
echo "   - Try different APN (diginet, unet, celcom3g)"
echo "   - Check SIM card: mmcli -m $MODEM_NUM --sim-get"
echo "   - Check logs: journalctl -u ModemManager -f"