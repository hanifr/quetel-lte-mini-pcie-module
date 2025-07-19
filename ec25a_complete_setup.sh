#!/bin/bash
# ec25a_complete_setup.sh
# Complete Quectel EC25-A setup script for Raspberry Pi 4
# Based on troubleshooting session findings

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

# Header
echo -e "${BLUE}"
echo "=============================================="
echo "  Quectel EC25-A Complete Setup Script"
echo "  For Raspberry Pi 4"
echo "=============================================="
echo -e "${NC}"

# 1. Install required packages
install_packages() {
    log "Installing required packages..."
    
    # Update system
    sudo apt update
    
    # Install packages
    sudo apt install -y \
        libqmi-utils \
        usbutils \
        screen \
        picocom \
        minicom \
        ppp \
        usb-modeswitch \
        usb-modeswitch-data \
        || { error "Package installation failed"; exit 1; }
    
    success "Required packages installed"
}

# 2. Fix ModemManager interference (CRITICAL!)
fix_modemmanager() {
    log "Disabling ModemManager (fixes 45-second disconnect cycles)..."
    
    # Stop ModemManager
    sudo systemctl stop ModemManager 2>/dev/null || true
    sudo systemctl disable ModemManager 2>/dev/null || true  
    sudo systemctl mask ModemManager 2>/dev/null || true
    
    # Kill any remaining processes
    sudo pkill -f ModemManager 2>/dev/null || true
    sudo pkill -f qmi-proxy 2>/dev/null || true
    
    success "ModemManager disabled - no more disconnect cycles!"
}

# 3. Wait for device and check detection
check_device() {
    log "Waiting for EC25-A device detection..."
    
    # Wait up to 30 seconds for device
    for i in {1..30}; do
        if lsusb | grep -q "2c7c:0125"; then
            success "EC25-A detected in USB"
            lsusb | grep "2c7c:0125"
            break
        fi
        
        if [ $i -eq 30 ]; then
            error "EC25-A not detected after 30 seconds"
            error "Check: Physical connection, power supply (5V/3A+)"
            exit 1
        fi
        
        sleep 1
    done
    
    # Check for ttyUSB devices
    log "Checking for ttyUSB devices..."
    if ls /dev/ttyUSB* >/dev/null 2>&1; then
        success "ttyUSB devices found: $(ls /dev/ttyUSB* | tr '\n' ' ')"
    else
        error "No ttyUSB devices found"
        exit 1
    fi
    
    # Check for QMI device
    if [ -e /dev/cdc-wdm0 ]; then
        success "QMI device found: /dev/cdc-wdm0"
    else
        warning "QMI device not found"
    fi
}

# 4. Find working AT command port
find_at_port() {
    log "Finding working AT command port..."
    
    for port in 0 1 2 3; do
        if [ -e "/dev/ttyUSB$port" ]; then
            log "Testing ttyUSB$port..."
            
            # Clear any existing processes
            sudo fuser -k /dev/ttyUSB$port 2>/dev/null || true
            sleep 1
            
            # Test AT command
            {
                echo -e "AT\r"
                sleep 2
            } | sudo tee /dev/ttyUSB$port >/dev/null 2>&1 &
            
            sleep 3
            response=$(sudo timeout 3 cat /dev/ttyUSB$port 2>/dev/null | grep -o "OK" | head -1)
            
            if [ "$response" = "OK" ]; then
                success "AT commands work on ttyUSB$port"
                echo "$port" > /tmp/ec25a_at_port
                AT_PORT=$port
                return 0
            else
                warning "ttyUSB$port - No AT response"
            fi
        fi
    done
    
    error "No working AT command port found on any ttyUSB device"
    exit 1
}

# 5. Get module information
get_module_info() {
    log "Getting module information..."
    
    # QMI information (most reliable)
    if [ -e /dev/cdc-wdm0 ]; then
        echo -e "\n${BLUE}--- QMI Information ---${NC}"
        sudo qmicli -d /dev/cdc-wdm0 --dms-get-manufacturer 2>/dev/null || warning "QMI manufacturer query failed"
        sudo qmicli -d /dev/cdc-wdm0 --dms-get-model 2>/dev/null || warning "QMI model query failed"  
        sudo qmicli -d /dev/cdc-wdm0 --dms-get-ids 2>/dev/null || warning "QMI IDs query failed"
    fi
    
    # AT command information
    local at_port=$(cat /tmp/ec25a_at_port 2>/dev/null || echo "$AT_PORT")
    echo -e "\n${BLUE}--- AT Command Information (ttyUSB$at_port) ---${NC}"
    
    {
        echo -e "ATI\r"
        sleep 3
    } | sudo tee /dev/ttyUSB$at_port >/dev/null
    
    sudo timeout 5 cat /dev/ttyUSB$at_port 2>/dev/null || warning "AT command info query failed"
}

# 6. Check SIM card status
check_sim_status() {
    log "Checking SIM card status..."
    
    # QMI SIM check
    if [ -e /dev/cdc-wdm0 ]; then
        echo -e "\n${BLUE}--- QMI SIM Status ---${NC}"
        sim_status=$(sudo qmicli -d /dev/cdc-wdm0 --uim-get-card-status 2>/dev/null)
        
        if echo "$sim_status" | grep -q "ready"; then
            success "SIM card detected and ready"
        else
            warning "SIM card status unclear"
        fi
        echo "$sim_status"
    fi
    
    # AT SIM check
    local at_port=$(cat /tmp/ec25a_at_port 2>/dev/null || echo "$AT_PORT")
    echo -e "\n${BLUE}--- AT Command SIM Check (ttyUSB$at_port) ---${NC}"
    
    {
        echo -e "AT+CPIN?\r"
        sleep 2
        echo -e "AT+CCID\r"  
        sleep 2
    } | sudo tee /dev/ttyUSB$at_port >/dev/null
    
    sudo timeout 5 cat /dev/ttyUSB$at_port 2>/dev/null || warning "AT SIM check failed"
}

# 7. Critical signal strength check
check_signal() {
    log "Checking signal strength (antenna test)..."
    
    # QMI signal check
    if [ -e /dev/cdc-wdm0 ]; then
        echo -e "\n${BLUE}--- QMI Signal Information ---${NC}"
        sudo qmicli -d /dev/cdc-wdm0 --nas-get-signal-strength 2>/dev/null || warning "QMI signal check failed"
        sudo qmicli -d /dev/cdc-wdm0 --nas-get-serving-system 2>/dev/null || warning "QMI serving system failed"
    fi
    
    # AT command signal check (most reliable)
    local at_port=$(cat /tmp/ec25a_at_port 2>/dev/null || echo "$AT_PORT")
    echo -e "\n${BLUE}--- AT Command Signal Check (ttyUSB$at_port) ---${NC}"
    
    {
        echo -e "AT+CSQ\r"
        sleep 3
    } | sudo tee /dev/ttyUSB$at_port >/dev/null
    
    signal_response=$(sudo timeout 5 cat /dev/ttyUSB$at_port 2>/dev/null)
    echo "Raw response: $signal_response"
    
    # Check signal quality
    if echo "$signal_response" | grep -q "+CSQ: 99,99"; then
        echo ""
        error "NO SIGNAL DETECTED (+CSQ: 99,99)"
        echo -e "${RED}🔧 CRITICAL: CHECK ANTENNA CONNECTION!${NC}"
        echo "   📡 Verify UFL antenna installation:"
        echo "   - UFL connector properly seated on main port"  
        echo "   - Antenna positioned correctly"
        echo "   - Try different location/orientation"
        echo ""
        warning "UFL antenna might need repositioning or better connection!"
        return 1
    elif echo "$signal_response" | grep -qE "\+CSQ: [0-9]+,[0-9]+"; then
        # Extract signal strength number
        signal_num=$(echo "$signal_response" | grep -o "+CSQ: [0-9]*" | grep -o "[0-9]*$")
        if [ "$signal_num" -ge 10 ]; then
            success "🎉 EXCELLENT signal detected! (+CSQ: $signal_num,xx) - UFL antenna working perfectly!"
        elif [ "$signal_num" -ge 5 ]; then
            success "✅ Good signal detected! (+CSQ: $signal_num,xx) - UFL antenna working!"
        else
            warning "⚠️  Weak signal detected (+CSQ: $signal_num,xx) - Try repositioning UFL antenna"
        fi
        echo "$signal_response" | grep "+CSQ:"
        return 0
    else
        warning "Could not determine signal status"
        echo "Response: $signal_response"
        return 1
    fi
}

# 8. Create quick test commands file
create_test_commands() {
    log "Creating test commands file..."
    
    local at_port=$(cat /tmp/ec25a_at_port 2>/dev/null || echo "$AT_PORT")
    
    cat > /home/pi/ec25a_test_commands.sh << EOF
#!/bin/bash
# Quick EC25-A test commands
# Generated by setup script
# Using ttyUSB$at_port for AT commands

AT_PORT=$at_port

echo "=== Quick EC25-A Tests ==="
echo "Using AT command port: ttyUSB\$AT_PORT"
echo ""

# Signal strength
echo "📶 Signal Strength:"
echo -e "AT+CSQ\r" | sudo tee /dev/ttyUSB\$AT_PORT >/dev/null
sleep 2
sudo timeout 3 cat /dev/ttyUSB\$AT_PORT

echo ""

# SIM status  
echo "📱 SIM Status:"
echo -e "AT+CPIN?\r" | sudo tee /dev/ttyUSB\$AT_PORT >/dev/null
sleep 2
sudo timeout 3 cat /dev/ttyUSB\$AT_PORT

echo ""

# Module info
echo "ℹ️  Module Info:"
echo -e "ATI\r" | sudo tee /dev/ttyUSB\$AT_PORT >/dev/null
sleep 2
sudo timeout 3 cat /dev/ttyUSB\$AT_PORT

echo ""
echo "💡 To scan networks (takes 2+ minutes): "
echo "echo -e \"AT+COPS=?\r\" | sudo tee /dev/ttyUSB\$AT_PORT >/dev/null && sleep 120 && sudo timeout 10 cat /dev/ttyUSB\$AT_PORT"

echo ""
echo "🌐 DiGi APN Configuration (run when signal is good):"
echo "sudo qmicli -d /dev/cdc-wdm0 --wds-start-network=\"apn=diginet\" --client-no-release-cid"
echo "sudo dhclient wwan0"
echo "ping google.com"
EOF

    chmod +x /home/pi/ec25a_test_commands.sh
    success "Test commands saved to /home/pi/ec25a_test_commands.sh"
}

# 9. Create status check script
create_status_script() {
    log "Creating status check script..."
    
    cat > /home/pi/ec25a_status.sh << 'EOF'
#!/bin/bash
# EC25-A Status Check Script

echo "=== Quectel EC25-A Status ==="

echo "📱 USB Device:"
if lsusb | grep -q "2c7c:0125"; then
    echo "✅ EC25-A detected"
    lsusb | grep "2c7c:0125"
else
    echo "❌ EC25-A not detected"
fi

echo ""
echo "📟 TTY Devices:"
if ls /dev/ttyUSB* >/dev/null 2>&1; then
    echo "✅ $(ls /dev/ttyUSB* | wc -l) devices: $(ls /dev/ttyUSB* | tr '\n' ' ')"
else
    echo "❌ No ttyUSB devices"
fi

echo ""
echo "📡 QMI Device:"
if [ -e /dev/cdc-wdm0 ]; then
    echo "✅ /dev/cdc-wdm0 exists"
else
    echo "❌ No QMI device"
fi

echo ""
echo "🛑 ModemManager Status:"
if sudo systemctl is-active ModemManager >/dev/null 2>&1; then
    echo "❌ ModemManager is running (causes disconnections!)"
    echo "   Run: sudo systemctl stop ModemManager && sudo systemctl mask ModemManager"
else
    echo "✅ ModemManager stopped/disabled"
fi

echo ""
echo "🔧 Run tests: ~/ec25a_test_commands.sh"
EOF

    chmod +x /home/pi/ec25a_status.sh
    success "Status script saved to /home/pi/ec25a_status.sh"
}

# Main setup function
main() {
    echo "Starting complete EC25-A setup..."
    
    # Global variable for AT port
    AT_PORT=""
    
    # Core setup steps
    install_packages
    fix_modemmanager
    
    log "Waiting 5 seconds for device stabilization..."
    sleep 5
    
    check_device
    find_at_port
    get_module_info
    check_sim_status
    
    # Signal check (antenna verification)
    echo ""
    echo -e "${BLUE}======================================${NC}"
    echo -e "${BLUE}     CRITICAL: UFL ANTENNA CHECK${NC}"
    echo -e "${BLUE}    Using AT commands on ttyUSB$AT_PORT${NC}"
    echo -e "${BLUE}======================================${NC}"
    
    if check_signal; then
        success "Setup complete! Module is ready for use."
        echo ""
        echo "📋 Next steps:"
        echo "1. Configure DiGi APN: sudo qmicli -d /dev/cdc-wdm0 --wds-start-network=\"apn=diginet\" --client-no-release-cid"
        echo "2. Configure IP: sudo dhclient wwan0"
        echo "3. Test connectivity: ping google.com"
        echo ""
        success "🎉 UFL antenna working! AT commands on ttyUSB$AT_PORT"
    else
        echo ""
        warning "Setup complete, but UFL antenna needs attention!"
        echo ""
        echo "📋 Next steps:"
        echo "1. Check UFL antenna connection is secure on main port"
        echo "2. Try different antenna position/orientation"
        echo "3. Re-run signal test: ~/ec25a_test_commands.sh"
        echo ""
        warning "AT commands working on ttyUSB$AT_PORT, but no signal detected"
    fi
    
    # Create helper scripts
    create_test_commands
    create_status_script
    
    echo ""
    success "Setup completed!"
    echo ""
    echo "📁 Created files:"
    echo "   ~/ec25a_test_commands.sh - Quick test commands (uses ttyUSB$AT_PORT)"
    echo "   ~/ec25a_status.sh - Status check"
    echo ""
    echo "🚀 Quick status check: ~/ec25a_status.sh"
    
    # Clean up
    rm -f /tmp/ec25a_at_port
}

# Run main setup - THIS IS THE CRITICAL LINE!
main "$@"