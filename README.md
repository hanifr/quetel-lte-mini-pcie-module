# Quectel EC25-A LTE Module Setup Guide for Raspberry Pi 4

## 🎯 Summary of Issues Discovered & Solutions

### **Primary Issue: ModemManager Interference**
- **Problem**: ModemManager causes 45-second disconnect cycles
- **Solution**: Disable ModemManager permanently
- **Result**: Stable connection achieved

### **Secondary Issue: Antenna Requirement**
- **Problem**: `+CSQ: 99,99` indicates no signal
- **Cause**: Missing cellular antennas  
- **Solution**: Install proper 700-2700MHz antennas

---

## 📋 Complete Setup Script

### 1. System Preparation & Package Installation

```bash
#!/bin/bash
# ec25a_setup.sh - Complete Quectel EC25-A setup script

set -e  # Exit on any error

echo "=== Quectel EC25-A Setup for Raspberry Pi 4 ==="
echo "Starting setup process..."

# Update system
echo "📦 Updating system packages..."
sudo apt update && sudo apt upgrade -y

# Install required packages
echo "📦 Installing required packages..."
sudo apt install -y \
    libqmi-utils \
    usbutils \
    screen \
    picocom \
    minicom \
    ppp \
    usb-modeswitch \
    usb-modeswitch-data

# Stop and disable ModemManager (CRITICAL!)
echo "🛑 Disabling ModemManager (fixes disconnect issues)..."
sudo systemctl stop ModemManager 2>/dev/null || true
sudo systemctl disable ModemManager 2>/dev/null || true  
sudo systemctl mask ModemManager 2>/dev/null || true

echo "✅ Package installation complete!"
```

### 2. Device Detection and Verification

```bash
# Device detection function
check_ec25a_device() {
    echo "🔍 Checking for EC25-A device..."
    
    # Check USB detection
    if lsusb | grep -q "2c7c:0125"; then
        echo "✅ EC25-A detected in USB"
        lsusb | grep "2c7c:0125"
    else
        echo "❌ EC25-A not detected in USB"
        echo "   Check physical connection and power supply"
        return 1
    fi
    
    # Check ttyUSB devices
    echo "📱 Available ttyUSB devices:"
    ls /dev/ttyUSB* 2>/dev/null || echo "❌ No ttyUSB devices found"
    
    # Check QMI device
    if [ -e /dev/cdc-wdm0 ]; then
        echo "✅ QMI device found: /dev/cdc-wdm0"
    else
        echo "❌ QMI device not found"
    fi
    
    return 0
}
```

### 3. Find Working AT Command Port

```bash
# Find which ttyUSB port handles AT commands
find_at_port() {
    echo "🔍 Testing AT command ports..."
    
    for port in 0 1 2 3; do
        if [ -e "/dev/ttyUSB$port" ]; then
            echo "Testing ttyUSB$port..."
            
            # Send AT command and check for OK response
            response=$(timeout 3 bash -c "
                echo -e 'AT\r' > /dev/ttyUSB$port 2>/dev/null
                sleep 1
                cat /dev/ttyUSB$port 2>/dev/null
            " | grep -o "OK" | head -1)
            
            if [ "$response" = "OK" ]; then
                echo "✅ AT commands work on ttyUSB$port"
                echo "$port" > /tmp/at_port
                return 0
            fi
        fi
    done
    
    echo "❌ No working AT command port found"
    return 1
}
```

### 4. Module Information and Status Check

```bash
# Get module information
get_module_info() {
    local at_port=$(cat /tmp/at_port 2>/dev/null || echo "3")
    
    echo "📋 Getting module information..."
    
    # QMI method (most reliable)
    if [ -e /dev/cdc-wdm0 ]; then
        echo "--- QMI Information ---"
        sudo qmicli -d /dev/cdc-wdm0 --dms-get-manufacturer 2>/dev/null || echo "QMI manufacturer failed"
        sudo qmicli -d /dev/cdc-wdm0 --dms-get-model 2>/dev/null || echo "QMI model failed"  
        sudo qmicli -d /dev/cdc-wdm0 --dms-get-ids 2>/dev/null || echo "QMI IDs failed"
    fi
    
    # AT command method
    echo "--- AT Command Information ---"
    {
        echo -e "ATI\r"
        sleep 2
    } | sudo tee /dev/ttyUSB$at_port > /dev/null
    sudo timeout 5 cat /dev/ttyUSB$at_port 2>/dev/null || echo "AT command failed"
}
```

### 5. Signal Strength and Network Detection

```bash
# Check signal strength and network status
check_signal_and_network() {
    local at_port=$(cat /tmp/at_port 2>/dev/null || echo "3")
    
    echo "📶 Checking signal strength..."
    
    # Method 1: QMI signal check
    if [ -e /dev/cdc-wdm0 ]; then
        echo "--- QMI Signal Information ---"
        sudo qmicli -d /dev/cdc-wdm0 --nas-get-signal-strength 2>/dev/null || echo "QMI signal check failed"
        sudo qmicli -d /dev/cdc-wdm0 --nas-get-serving-system 2>/dev/null || echo "QMI serving system failed"
    fi
    
    # Method 2: AT command signal check  
    echo "--- AT Command Signal Check ---"
    {
        echo -e "AT+CSQ\r"
        sleep 2
    } | sudo tee /dev/ttyUSB$at_port > /dev/null
    
    signal_response=$(sudo timeout 5 cat /dev/ttyUSB$at_port 2>/dev/null | grep "+CSQ:")
    echo "Signal response: $signal_response"
    
    if echo "$signal_response" | grep -q "+CSQ: 99,99"; then
        echo "❌ NO SIGNAL DETECTED (+CSQ: 99,99)"
        echo "🔧 ACTION REQUIRED: Install cellular antennas!"
        echo "   - Main antenna (required)"  
        echo "   - Diversity antenna (recommended)"
        echo "   - Frequency range: 700-2700 MHz"
        return 1
    elif echo "$signal_response" | grep -q "+CSQ: [0-9]"; then
        echo "✅ Signal detected!"
        return 0
    else
        echo "⚠️  Could not determine signal status"
        return 1
    fi
}
```

### 6. SIM Card Status Check

```bash
# Check SIM card status
check_sim_status() {
    echo "📱 Checking SIM card status..."
    
    # QMI SIM check
    if [ -e /dev/cdc-wdm0 ]; then
        echo "--- QMI SIM Status ---"
        sudo qmicli -d /dev/cdc-wdm0 --uim-get-card-status 2>/dev/null || echo "QMI SIM check failed"
    fi
    
    # AT SIM check
    local at_port=$(cat /tmp/at_port 2>/dev/null || echo "3")
    echo "--- AT Command SIM Check ---"
    {
        echo -e "AT+CPIN?\r"
        sleep 2
        echo -e "AT+CCID\r"  
        sleep 2
    } | sudo tee /dev/ttyUSB$at_port > /dev/null
    sudo timeout 5 cat /dev/ttyUSB$at_port 2>/dev/null || echo "AT SIM check failed"
}
```

### 7. Network Scan (Optional - Takes 2+ Minutes)

```bash
# Scan for available networks
scan_networks() {
    local at_port=$(cat /tmp/at_port 2>/dev/null || echo "3")
    
    echo "🌐 Scanning for networks (this takes 2+ minutes)..."
    echo "   Press Ctrl+C to skip if needed"
    
    {
        echo -e "AT+COPS=?\r"
        sleep 120  # Wait 2 minutes for scan
    } | sudo tee /dev/ttyUSB$at_port > /dev/null
    
    scan_result=$(sudo timeout 10 cat /dev/ttyUSB$at_port 2>/dev/null)
    
    if echo "$scan_result" | grep -q "("; then
        echo "✅ Networks found:"
        echo "$scan_result"
        return 0
    else
        echo "❌ No networks found"
        echo "🔧 This confirms antenna installation is required"
        return 1
    fi
}
```

---

## 🚀 Main Setup Function

```bash
# Main setup function
main_setup() {
    echo "Starting Quectel EC25-A setup..."
    
    # Install packages
    install_packages
    
    # Wait for device to be ready
    echo "⏳ Waiting for device to be ready..."
    sleep 5
    
    # Check device detection
    if ! check_ec25a_device; then
        echo "❌ Setup failed: Device not detected"
        exit 1
    fi
    
    # Find AT command port
    if ! find_at_port; then
        echo "❌ Setup failed: No AT command port found"
        exit 1
    fi
    
    # Get module information
    get_module_info
    
    # Check SIM status
    check_sim_status
    
    # Check signal (this will show if antennas are needed)
    check_signal_and_network
    
    echo "🎉 Setup complete!"
    echo ""
    echo "📋 Next Steps:"
    echo "1. If signal shows +CSQ: 99,99 - Install cellular antennas"
    echo "2. If signal is good - Configure APN for your carrier"
    echo "3. Test data connection"
}

# Run main setup
main_setup
```

---

## 🔧 Troubleshooting Commands

### Quick Status Check
```bash
# Quick device status check
echo "USB Device:" && lsusb | grep -i quectel
echo "TTY Devices:" && ls /dev/ttyUSB* 2>/dev/null || echo "None"
echo "QMI Device:" && ls /dev/cdc-wdm* 2>/dev/null || echo "None"
echo "ModemManager:" && sudo systemctl is-active ModemManager 2>/dev/null || echo "Stopped"
```

### Manual AT Testing
```bash
# Test AT commands manually (replace X with working port number)
sudo screen /dev/ttyUSBX 115200

# In screen, type:
# AT          (basic test)
# AT+CSQ      (signal strength)  
# AT+CPIN?    (SIM status)
# ATI         (module info)
# Exit: Ctrl+A then K then Y
```

### QMI Testing
```bash
# Test QMI interface
sudo qmicli -d /dev/cdc-wdm0 --dms-get-manufacturer
sudo qmicli -d /dev/cdc-wdm0 --nas-get-signal-strength
sudo qmicli -d /dev/cdc-wdm0 --uim-get-card-status
```

---

## 📁 Auto-Start Setup

### Create systemd service for auto-setup
```bash
# Create service file
sudo tee /etc/systemd/system/ec25a-setup.service > /dev/null << 'EOF'
[Unit]
Description=Quectel EC25-A Setup Service
After=multi-user.target
Wants=multi-user.target

[Service]
Type=oneshot
ExecStart=/home/pi/ec25a_setup.sh
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Enable service
sudo systemctl enable ec25a-setup.service
sudo systemctl daemon-reload
```

---

## ⚡ Quick Reference Commands

```bash
# Check if setup worked
lsusb | grep -i quectel && echo "✅ USB OK" || echo "❌ USB Failed"
ls /dev/ttyUSB* && echo "✅ TTY OK" || echo "❌ TTY Failed"  
sudo systemctl is-active ModemManager && echo "❌ ModemManager Running" || echo "✅ ModemManager Stopped"

# Test signal quickly
echo -e "AT+CSQ\r" | sudo tee /dev/ttyUSB3 > /dev/null && sleep 2 && sudo timeout 3 cat /dev/ttyUSB3

# Common DiGi APN setup (for when antennas are installed)
# APN: diginet
# Username: (blank)
# Password: (blank)
```

---

## 🎯 Key Success Criteria

✅ **USB Device Detection**: `lsusb` shows Quectel EC25  
✅ **TTY Devices**: 4 devices (/dev/ttyUSB0-3)  
✅ **QMI Device**: /dev/cdc-wdm0 exists  
✅ **ModemManager**: Stopped/Disabled  
✅ **AT Commands**: Working on one of the ttyUSB ports  
✅ **Signal**: NOT +CSQ: 99,99 (requires antennas)  
✅ **SIM**: Detected and ready  

---

## 🔧 Hardware Requirements

**Essential:**
- Quectel EC25-A mini PCIe module
- **Cellular antennas** (700-2700 MHz range)
- Antenna cables (U.FL to SMA typically)
- Adequate power supply (5V/3A+ for Pi 4)

**Without antennas, the module will show `+CSQ: 99,99` and find no networks!**

---

This guide covers the complete setup process based on the troubleshooting session. The main discovery was that ModemManager interference caused the disconnect issues, and missing antennas cause the no-signal problem.