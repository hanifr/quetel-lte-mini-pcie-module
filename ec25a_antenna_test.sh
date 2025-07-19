#!/bin/bash
# ec25a_antenna_test.sh
# Test EC25-A antenna and complete setup
# For use after main setup script fails at AT port detection

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
echo "  EC25-A Antenna Test & Setup Completion"
echo "  Using ttyUSB3 (known working AT port)"
echo "=============================================="
echo -e "${NC}"

# 1. Verify device status
check_devices() {
    log "Checking device status..."
    
    # Check USB device
    if lsusb | grep -q "2c7c:0125"; then
        success "EC25-A USB device detected"
    else
        error "EC25-A USB device not found"
        exit 1
    fi
    
    # Check ttyUSB devices
    if ls /dev/ttyUSB{0,1,2,3} >/dev/null 2>&1; then
        success "All 4 ttyUSB devices present"
    else
        error "Missing ttyUSB devices"
        exit 1
    fi
    
    # Check QMI device
    if [ -e /dev/cdc-wdm0 ]; then
        success "QMI device present"
    else
        warning "QMI device missing"
    fi
}

# 2. Find working AT command port
find_working_at_port() {
    log "Testing AT commands on ALL ttyUSB ports..."
    
    for port in 0 1 2 3; do
        if [ -e "/dev/ttyUSB$port" ]; then
            log "Testing ttyUSB$port..."
            
            # Clear any processes using the port
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
                success "AT commands working on ttyUSB$port"
                echo "$port" > /tmp/ec25a_working_port
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

# 3. CRITICAL: Test antenna signal strength
test_antenna_signal() {
    log "🔍 CRITICAL TEST: Checking UFL antenna signal..."
    
    echo -e "\n${BLUE}======================================${NC}"
    echo -e "${BLUE}      UFL ANTENNA SIGNAL TEST${NC}"
    echo -e "${BLUE}    Using ttyUSB$AT_PORT for AT commands${NC}"
    echo -e "${BLUE}======================================${NC}"
    
    # Clear port
    sudo fuser -k /dev/ttyUSB$AT_PORT 2>/dev/null || true
    sleep 1
    
    # Send AT+CSQ command
    {
        echo -e "AT+CSQ\r"
        sleep 3
    } | sudo tee /dev/ttyUSB$AT_PORT >/dev/null
    
    # Get response
    signal_response=$(sudo timeout 5 cat /dev/ttyUSB$AT_PORT 2>/dev/null)
    echo "Raw AT+CSQ response:"
    echo "$signal_response"
    echo ""
    
    # Parse signal strength
    if echo "$signal_response" | grep -q "+CSQ: 99,99"; then
        echo ""
        error "NO SIGNAL DETECTED (+CSQ: 99,99)"
        echo -e "${RED}🔧 UFL ANTENNA ISSUE!${NC}"
        echo ""
        echo "Possible problems:"
        echo "   📡 UFL connector not properly seated"
        echo "   📡 Antenna cable damaged" 
        echo "   📡 Antenna positioned poorly"
        echo "   📡 Need to try different location"
        echo ""
        warning "Try reconnecting UFL connector firmly!"
        return 1
        
    elif echo "$signal_response" | grep -qE "\+CSQ: ([0-9]+),"; then
        # Extract signal number
        signal_num=$(echo "$signal_response" | grep -oE "\+CSQ: ([0-9]+)," | grep -oE "[0-9]+" | head -1)
        
        if [ "$signal_num" -ge 15 ]; then
            echo ""
            success "🎉 EXCELLENT SIGNAL! (+CSQ: $signal_num,xx)"
            echo -e "${GREEN}📡 UFL antenna working perfectly!${NC}"
            return 0
        elif [ "$signal_num" -ge 10 ]; then
            echo ""
            success "✅ GOOD SIGNAL! (+CSQ: $signal_num,xx)"
            echo -e "${GREEN}📡 UFL antenna working well!${NC}"
            return 0
        elif [ "$signal_num" -ge 5 ]; then
            echo ""
            success "⚠️  WEAK SIGNAL (+CSQ: $signal_num,xx)"
            echo -e "${YELLOW}📡 UFL antenna working but try repositioning${NC}"
            return 0
        else
            echo ""
            warning "VERY WEAK SIGNAL (+CSQ: $signal_num,xx)"
            echo -e "${YELLOW}📡 UFL antenna detected signal but very weak${NC}"
            return 0
        fi
    else
        warning "Could not parse signal response"
        echo "Response: $signal_response"
        return 1
    fi
}

# 4. Test SIM card (DiGi)
test_sim_card() {
    log "Testing DiGi SIM card..."
    
    echo -e "\n${BLUE}--- SIM Card Status ---${NC}"
    
    # Clear port
    sudo fuser -k /dev/ttyUSB$AT_PORT 2>/dev/null || true
    sleep 1
    
    # Test SIM PIN status
    {
        echo -e "AT+CPIN?\r"
        sleep 2
    } | sudo tee /dev/ttyUSB$AT_PORT >/dev/null
    
    sim_response=$(sudo timeout 3 cat /dev/ttyUSB$AT_PORT 2>/dev/null)
    echo "SIM PIN Status:"
    echo "$sim_response"
    
    if echo "$sim_response" | grep -q "READY"; then
        success "DiGi SIM card ready (no PIN required)"
    elif echo "$sim_response" | grep -q "SIM PIN"; then
        warning "SIM card requires PIN"
    else
        warning "SIM card status unclear"
    fi
    
    # Get SIM card ID
    {
        echo -e "AT+CCID\r"
        sleep 2
    } | sudo tee /dev/ttyUSB$AT_PORT >/dev/null
    
    ccid_response=$(sudo timeout 3 cat /dev/ttyUSB$AT_PORT 2>/dev/null)
    if echo "$ccid_response" | grep -q "+CCID:"; then
        success "SIM card ID detected"
        echo "$ccid_response" | grep "+CCID:"
    fi
}

# 5. Test QMI interface
test_qmi_interface() {
    log "Testing QMI interface..."
    
    if [ ! -e /dev/cdc-wdm0 ]; then
        warning "QMI device not available, skipping QMI tests"
        return 1
    fi
    
    echo -e "\n${BLUE}--- QMI Information ---${NC}"
    
    # Test QMI signal
    echo "QMI Signal Strength:"
    sudo qmicli -d /dev/cdc-wdm0 --nas-get-signal-strength 2>/dev/null || warning "QMI signal query failed"
    
    echo ""
    echo "QMI Module Info:"
    sudo qmicli -d /dev/cdc-wdm0 --dms-get-manufacturer 2>/dev/null || warning "QMI manufacturer query failed"
    sudo qmicli -d /dev/cdc-wdm0 --dms-get-model 2>/dev/null || warning "QMI model query failed"
}

# 6. Network scan (optional, takes time)
scan_networks() {
    log "Would you like to scan for networks? (takes 2+ minutes)"
    echo "This will show available networks like DiGi, Maxis, Celcom..."
    read -p "Run network scan? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log "Scanning for networks (please wait 2+ minutes)..."
        
        {
            echo -e "AT+COPS=?\r"
            sleep 120
        } | sudo tee /dev/ttyUSB$AT_PORT >/dev/null
        
        scan_result=$(sudo timeout 10 cat /dev/ttyUSB$AT_PORT 2>/dev/null)
        
        if echo "$scan_result" | grep -q "("; then
            success "Networks found!"
            echo "$scan_result"
        else
            warning "No networks found in scan"
        fi
    else
        log "Skipping network scan"
    fi
}

# 7. Create test scripts
create_test_scripts() {
    log "Creating test scripts..."
    
    # Quick test script
    cat > /home/pi/ec25a_quick_test.sh << EOF
#!/bin/bash
# Quick EC25-A test script
# Using ttyUSB$AT_PORT for AT commands

echo "=== EC25-A Quick Tests ==="

echo "📶 Signal Strength:"
echo -e "AT+CSQ\r" | sudo tee /dev/ttyUSB$AT_PORT >/dev/null
sleep 2
sudo timeout 3 cat /dev/ttyUSB$AT_PORT | grep "+CSQ:"

echo ""
echo "📱 SIM Status:"
echo -e "AT+CPIN?\r" | sudo tee /dev/ttyUSB$AT_PORT >/dev/null
sleep 2
sudo timeout 3 cat /dev/ttyUSB$AT_PORT | grep -E "(READY|PIN)"

echo ""
echo "ℹ️  Module Info:"
echo -e "ATI\r" | sudo tee /dev/ttyUSB$AT_PORT >/dev/null
sleep 2
sudo timeout 3 cat /dev/ttyUSB$AT_PORT
EOF

    chmod +x /home/pi/ec25a_quick_test.sh
    success "Quick test script: ~/ec25a_quick_test.sh"
    
    # DiGi connection script
    cat > /home/pi/ec25a_connect_digi.sh << EOF
#!/bin/bash
# Connect to DiGi network
# Using ttyUSB$AT_PORT for AT commands

echo "=== Connecting to DiGi Network ==="

# Check signal first
echo "📶 Checking signal..."
signal=\$(echo -e "AT+CSQ\r" | sudo tee /dev/ttyUSB$AT_PORT >/dev/null && sleep 2 && sudo timeout 3 cat /dev/ttyUSB$AT_PORT | grep "+CSQ:")
echo "\$signal"

if echo "\$signal" | grep -q "99,99"; then
    echo "❌ No signal - check antenna!"
    exit 1
fi

echo ""
echo "🌐 Starting DiGi connection..."

# Start network with DiGi APN
if sudo qmicli -d /dev/cdc-wdm0 --wds-start-network="apn=diginet" --client-no-release-cid; then
    echo "✅ Network connection started"
    
    echo "🔧 Configuring IP address..."
    sudo dhclient wwan0
    
    echo "🌐 Testing connectivity..."
    if ping -c 3 google.com; then
        echo "✅ Internet connection working!"
    else
        echo "⚠️  Network connected but no internet"
    fi
else
    echo "❌ Failed to start network connection"
fi
EOF

    chmod +x /home/pi/ec25a_connect_digi.sh
    success "DiGi connection script: ~/ec25a_connect_digi.sh"
}

# Main function
main() {
    echo "Starting EC25-A antenna test and setup completion..."
    
    # Global variable for AT port
    AT_PORT=""
    
    check_devices
    find_working_at_port
    
    # The critical antenna test
    echo ""
    if test_antenna_signal; then
        echo ""
        success "🎉 UFL ANTENNA IS WORKING!"
        echo ""
        
        # Continue with other tests
        test_sim_card
        test_qmi_interface
        scan_networks
        create_test_scripts
        
        echo ""
        echo -e "${GREEN}======================================${NC}"
        echo -e "${GREEN}        SETUP COMPLETED!${NC}"
        echo -e "${GREEN}======================================${NC}"
        echo ""
        echo "📋 Next Steps:"
        echo "1. Connect to DiGi: ~/ec25a_connect_digi.sh"
        echo "2. Quick tests: ~/ec25a_quick_test.sh"
        echo "3. Check status anytime: lsusb | grep -i quectel"
        echo ""
        success "Your EC25-A with UFL antenna is ready for use!"
        success "AT commands working on ttyUSB$AT_PORT"
        
    else
        echo ""
        error "UFL antenna needs attention"
        echo ""
        echo "📋 Troubleshooting steps:"
        echo "1. Check UFL connector is firmly connected"
        echo "2. Try different antenna position/orientation"
        echo "3. Move to location with better coverage"
        echo "4. Re-run this test: ./ec25a_antenna_test.sh"
        
        # Still create basic test scripts
        create_test_scripts
    fi
    
    echo ""
    echo "📁 Created files:"
    echo "   ~/ec25a_quick_test.sh - Quick signal/SIM tests"
    echo "   ~/ec25a_connect_digi.sh - DiGi connection setup"
    
    # Clean up
    rm -f /tmp/ec25a_working_port
}

# Run the tests
main "$@"