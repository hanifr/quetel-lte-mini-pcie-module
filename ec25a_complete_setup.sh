#!/bin/bash
# enhanced_quectel_setup.sh
# Enhanced Quectel setup script supporting both USB and PCIe operation
# Improved power management, stability, and device detection

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Global variables
MODEM_TYPE=""
DEVICE_PATH=""
AT_PORT=""
QMI_DEVICE=""
CONNECTION_MODE=""

# Logging functions
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

debug() {
    echo -e "${CYAN}🔍 DEBUG: $1${NC}"
}

# Header
echo -e "${BLUE}"
echo "=============================================="
echo "  Enhanced Quectel Modem Setup Script"
echo "  Supports: USB (EC25, EC21) & PCIe (RM500Q, EM05)"
echo "=============================================="
echo -e "${NC}"

# 1. System health and power checks (Critical for stability)
check_system_health() {
    log "Checking system health and power status..."
    
    # Check voltage - critical for stability
    voltage=$(vcgencmd measure_volts | grep -o '[0-9.]*')
    temp=$(cat /sys/class/thermal/thermal_zone0/temp)
    temp_c=$((temp/1000))
    
    echo "📊 System Status:"
    echo "   Core Voltage: ${voltage}V"
    echo "   Temperature: ${temp_c}°C"
    
    # Voltage warnings
    if (( $(echo "$voltage < 1.1" | bc -l) )); then
        error "CRITICAL: Low voltage detected (${voltage}V < 1.1V)"
        echo "   🔧 Required fixes:"
        echo "   - Use 5V/4A+ power supply"
        echo "   - Check power cable connections"
        echo "   - Consider powered USB hub for USB modems"
        return 1
    elif (( $(echo "$voltage < 1.15" | bc -l) )); then
        warning "Voltage is marginal (${voltage}V). Monitor for stability issues."
    else
        success "Voltage OK (${voltage}V)"
    fi
    
    # Temperature check
    if [ "$temp_c" -gt 70 ]; then
        warning "High temperature (${temp_c}°C). Ensure adequate cooling."
    else
        success "Temperature OK (${temp_c}°C)"
    fi
    
    # Check throttling history
    throttled=$(vcgencmd get_throttled)
    if [ "$throttled" != "throttled=0x0" ]; then
        warning "Throttling detected: $throttled"
        echo "   Bit meanings: 0x1=undervoltage, 0x2=arm_freq_capped, 0x4=throttled, 0x8=soft_temp_limit"
    else
        success "No throttling detected"
    fi
}

# 2. Enhanced device detection (USB + PCIe)
detect_modem_type() {
    log "Detecting Quectel modem type and connection method..."
    
    # Check for USB modems first
    if lsusb | grep -q "2c7c:"; then
        usb_device=$(lsusb | grep "2c7c:")
        success "USB Quectel modem detected"
        echo "   $usb_device"
        
        # Identify specific model
        if echo "$usb_device" | grep -q "0125"; then
            MODEM_TYPE="EC25-A"
            CONNECTION_MODE="USB"
        elif echo "$usb_device" | grep -q "0121"; then
            MODEM_TYPE="EC21-A"
            CONNECTION_MODE="USB"
        elif echo "$usb_device" | grep -q "0306"; then
            MODEM_TYPE="EP06-E"
            CONNECTION_MODE="USB"
        else
            MODEM_TYPE="Unknown USB"
            CONNECTION_MODE="USB"
        fi
        
        success "Identified: $MODEM_TYPE (USB mode)"
        return 0
    fi
    
    # Check for PCIe modems
    if lspci | grep -i qualcomm | grep -q -E "(SDX|QDX)"; then
        pcie_device=$(lspci | grep -i qualcomm)
        success "PCIe Quectel modem detected"
        echo "   $pcie_device"
        
        # Try to identify PCIe model
        if lspci -v | grep -q "RM500Q"; then
            MODEM_TYPE="RM500Q-GL"
        elif lspci -v | grep -q "RM505Q"; then
            MODEM_TYPE="RM505Q-AE"
        elif lspci -v | grep -q "EM05"; then
            MODEM_TYPE="EM05-CE"
        else
            MODEM_TYPE="Unknown PCIe"
        fi
        
        CONNECTION_MODE="PCIe"
        success "Identified: $MODEM_TYPE (PCIe mode)"
        return 0
    fi
    
    # Check for MHI devices (PCIe modems)
    if ls /dev/mhi_* >/dev/null 2>&1; then
        success "MHI devices found (PCIe modem)"
        ls /dev/mhi_* | head -5
        CONNECTION_MODE="PCIe"
        MODEM_TYPE="PCIe (MHI detected)"
        return 0
    fi
    
    error "No Quectel modem detected"
    echo "   Checked: USB (lsusb), PCIe (lspci), MHI devices"
    echo "   🔧 Troubleshooting:"
    echo "   - Check physical connections"
    echo "   - Verify power supply (USB modems need 5V/3A+)"
    echo "   - For PCIe: Check PCIe slot seating"
    echo "   - Run: lsusb && lspci | grep -i qualcomm"
    return 1
}

# 3. Enhanced package installation with PCIe support
install_packages() {
    log "Installing packages for both USB and PCIe operation..."
    
    # Update system
    sudo apt update
    
    # Base packages
    local packages=(
        "libqmi-utils"
        "usbutils"
        "pciutils"
        "screen"
        "picocom"
        "minicom"
        "ppp"
        "usb-modeswitch"
        "usb-modeswitch-data"
        "bc"  # For voltage calculations
    )
    
    # PCIe-specific packages
    if [ "$CONNECTION_MODE" = "PCIe" ]; then
        packages+=(
            "mhi-tools"
            "linux-modules-extra-$(uname -r)"
        )
    fi
    
    sudo apt install -y "${packages[@]}" || { 
        error "Package installation failed"; 
        return 1; 
    }
    
    success "Required packages installed for $CONNECTION_MODE mode"
}

# 4. USB-specific optimizations
optimize_usb_connection() {
    if [ "$CONNECTION_MODE" != "USB" ]; then
        return 0
    fi
    
    log "Applying USB optimizations for stability..."
    
    # Disable USB autosuspend for all devices
    echo 'on' | sudo tee /sys/bus/usb/devices/*/power/control >/dev/null 2>&1
    
    # Increase USB current limit if not already set
    if ! grep -q "max_usb_current" /boot/config.txt; then
        echo "max_usb_current=1" | sudo tee -a /boot/config.txt
        warning "Added max_usb_current=1 to /boot/config.txt - reboot required"
    fi
    
    # USB stability improvements
    if ! grep -q "dwc_otg.fiq_fsm_enable=0" /boot/config.txt; then
        echo "dwc_otg.fiq_fsm_enable=0" | sudo tee -a /boot/config.txt
        warning "Added USB FIQ fix to /boot/config.txt - reboot required"
    fi
    
    success "USB optimizations applied"
}

# 5. PCIe-specific initialization
initialize_pcie_modem() {
    if [ "$CONNECTION_MODE" != "PCIe" ]; then
        return 0
    fi
    
    log "Initializing PCIe modem..."
    
    # Check MHI state
    if [ -d "/sys/bus/mhi" ]; then
        success "MHI subsystem loaded"
        
        # List MHI devices
        if ls /sys/bus/mhi/devices/ >/dev/null 2>&1; then
            debug "MHI devices: $(ls /sys/bus/mhi/devices/ | tr '\n' ' ')"
        fi
    else
        warning "MHI subsystem not found - may need kernel module loading"
    fi
    
    # Load required modules for PCIe
    sudo modprobe mhi || warning "Failed to load MHI module"
    sudo modprobe qcom_q6v5_mss || warning "Failed to load Q6V5 module"
    
    success "PCIe modem initialization completed"
}

# 6. Enhanced device detection with retry logic
wait_for_devices() {
    log "Waiting for modem devices with enhanced detection..."
    
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        debug "Detection attempt $attempt/$max_attempts"
        
        if [ "$CONNECTION_MODE" = "USB" ]; then
            # USB device detection
            if ls /dev/ttyUSB* >/dev/null 2>&1; then
                success "USB serial devices found: $(ls /dev/ttyUSB* | tr '\n' ' ')"
                
                # Check for QMI device
                if [ -e /dev/cdc-wdm0 ]; then
                    QMI_DEVICE="/dev/cdc-wdm0"
                    success "QMI device found: $QMI_DEVICE"
                elif [ -e /dev/cdc-wdm1 ]; then
                    QMI_DEVICE="/dev/cdc-wdm1"
                    success "QMI device found: $QMI_DEVICE"
                fi
                break
            fi
        else
            # PCIe device detection
            if ls /dev/mhi_* >/dev/null 2>&1; then
                success "MHI devices found: $(ls /dev/mhi_* | head -3 | tr '\n' ' ')"
                
                # Look for QMI device in MHI
                for qmi_dev in /dev/mhi_*QMI*; do
                    if [ -e "$qmi_dev" ]; then
                        QMI_DEVICE="$qmi_dev"
                        success "MHI QMI device found: $QMI_DEVICE"
                        break
                    fi
                done
                
                # Look for AT command device
                for at_dev in /dev/mhi_*AT*; do
                    if [ -e "$at_dev" ]; then
                        AT_PORT="$at_dev"
                        success "MHI AT device found: $AT_PORT"
                        break
                    fi
                done
                break
            fi
        fi
        
        if [ $attempt -eq $max_attempts ]; then
            error "Device detection failed after $max_attempts attempts"
            return 1
        fi
        
        sleep 1
        ((attempt++))
    done
    
    return 0
}

# 7. Enhanced AT port detection
find_working_at_port() {
    if [ "$CONNECTION_MODE" = "PCIe" ] && [ -n "$AT_PORT" ]; then
        log "Using PCIe AT device: $AT_PORT"
        return 0
    fi
    
    if [ "$CONNECTION_MODE" != "USB" ]; then
        return 0
    fi
    
    log "Finding working AT command port (USB)..."
    
    for port in 0 1 2 3; do
        if [ -e "/dev/ttyUSB$port" ]; then
            log "Testing ttyUSB$port..."
            
            # Clear any existing processes
            sudo fuser -k /dev/ttyUSB$port 2>/dev/null || true
            sleep 1
            
            # Configure port settings for better reliability
            sudo stty -F /dev/ttyUSB$port 115200 cs8 -cstopb -parenb raw
            
            # Test AT command with timeout
            if timeout 5 bash -c "
                echo -e 'AT\r' > /dev/ttyUSB$port
                sleep 2
                read -t 3 response < /dev/ttyUSB$port
                echo \$response | grep -q 'OK'
            " 2>/dev/null; then
                success "✅ AT commands work on ttyUSB$port"
                AT_PORT="/dev/ttyUSB$port"
                return 0
            else
                warning "❌ ttyUSB$port - No AT response"
            fi
        fi
    done
    
    error "No working AT command port found"
    return 1
}

# 8. Enhanced signal strength check with better interpretation
check_signal_strength() {
    log "Checking signal strength and network registration..."
    
    local device_for_at=""
    if [ "$CONNECTION_MODE" = "USB" ]; then
        device_for_at="$AT_PORT"
    else
        device_for_at="$AT_PORT"
    fi
    
    if [ -z "$device_for_at" ]; then
        warning "No AT device available for signal check"
        return 1
    fi
    
    echo -e "\n${BLUE}--- Signal Strength Analysis ---${NC}"
    
    # Configure device for AT commands
    sudo stty -F "$device_for_at" 115200 cs8 -cstopb -parenb raw 2>/dev/null || true
    
    # AT+CSQ (Signal Quality)
    echo -e "AT+CSQ\r" | sudo tee "$device_for_at" >/dev/null
    sleep 2
    signal_response=$(sudo timeout 5 cat "$device_for_at" 2>/dev/null || echo "")
    
    debug "Raw CSQ response: $signal_response"
    
    if echo "$signal_response" | grep -q "+CSQ: 99,99"; then
        error "NO SIGNAL DETECTED (+CSQ: 99,99)"
        echo "🔧 Antenna troubleshooting:"
        echo "   📡 Check antenna connections (UFL/IPEX connectors)"
        echo "   📍 Try different location/orientation"
        echo "   🏠 Test near window or outdoors"
        return 1
    elif echo "$signal_response" | grep -qE '\+CSQ: [0-9]+,[0-9]+'; then
        signal_num=$(echo "$signal_response" | grep -o "+CSQ: [0-9]*" | grep -o "[0-9]*$")
        ber=$(echo "$signal_response" | grep -o "+CSQ: [0-9]*,[0-9]*" | cut -d',' -f2)
        
        # Signal strength interpretation
        if [ "$signal_num" -ge 20 ]; then
            success "🎉 EXCELLENT signal! (+CSQ: $signal_num,$ber) [-53dBm or better]"
        elif [ "$signal_num" -ge 15 ]; then
            success "✅ Very good signal (+CSQ: $signal_num,$ber) [-63 to -54dBm]"
        elif [ "$signal_num" -ge 10 ]; then
            success "✅ Good signal (+CSQ: $signal_num,$ber) [-73 to -64dBm]"
        elif [ "$signal_num" -ge 5 ]; then
            warning "⚠️  Adequate signal (+CSQ: $signal_num,$ber) [-83 to -74dBm]"
        else
            warning "⚠️  Weak signal (+CSQ: $signal_num,$ber) [-93 to -84dBm]"
        fi
    fi
    
    # Network registration check
    echo -e "AT+CREG?\r" | sudo tee "$device_for_at" >/dev/null
    sleep 2
    reg_response=$(sudo timeout 5 cat "$device_for_at" 2>/dev/null || echo "")
    
    debug "Network registration: $reg_response"
    
    if echo "$reg_response" | grep -q "+CREG: 0,1"; then
        success "📶 Registered on home network"
    elif echo "$reg_response" | grep -q "+CREG: 0,5"; then
        success "📶 Registered on roaming network"
    elif echo "$reg_response" | grep -q "+CREG: 0,2"; then
        warning "📡 Searching for network..."
    else
        warning "📡 Not registered on network"
    fi
    
    return 0
}

# 9. QMI connection setup with both USB and PCIe support
setup_qmi_connection() {
    if [ -z "$QMI_DEVICE" ]; then
        warning "No QMI device found - skipping QMI setup"
        return 1
    fi
    
    log "Setting up QMI connection..."
    
    # Get device info
    sudo qmicli -d "$QMI_DEVICE" --dms-get-manufacturer 2>/dev/null || warning "Failed to get manufacturer"
    sudo qmicli -d "$QMI_DEVICE" --dms-get-model 2>/dev/null || warning "Failed to get model"
    
    # Check if already connected
    if sudo qmicli -d "$QMI_DEVICE" --wds-get-packet-service-status 2>/dev/null | grep -q "connected"; then
        success "QMI already connected"
        return 0
    fi
    
    success "QMI device ready for connection at $QMI_DEVICE"
    echo "   To connect: sudo qmicli -d $QMI_DEVICE --wds-start-network=\"apn=diginet\" --client-no-release-cid"
    
    return 0
}

# 10. Create enhanced test scripts
create_enhanced_test_scripts() {
    log "Creating enhanced test scripts..."
    
    # Main test script
    cat > /home/pi/quectel_test.sh << EOF
#!/bin/bash
# Enhanced Quectel Test Script
# Generated by enhanced setup script

MODEM_TYPE="$MODEM_TYPE"
CONNECTION_MODE="$CONNECTION_MODE"
AT_DEVICE="$AT_PORT"
QMI_DEVICE="$QMI_DEVICE"

echo "=== Enhanced Quectel Test ==="
echo "Modem: \$MODEM_TYPE (\$CONNECTION_MODE)"
echo "AT Device: \$AT_DEVICE"
echo "QMI Device: \$QMI_DEVICE"
echo ""

# System health check
echo "🏥 System Health:"
voltage=\$(vcgencmd measure_volts | grep -o '[0-9.]*')
temp=\$(cat /sys/class/thermal/thermal_zone0/temp)
temp_c=\$((temp/1000))
echo "   Voltage: \${voltage}V, Temperature: \${temp_c}°C"

if (( \$(echo "\$voltage < 1.1" | bc -l) )); then
    echo "   ❌ Low voltage detected!"
else
    echo "   ✅ Voltage OK"
fi

echo ""

if [ -n "\$AT_DEVICE" ] && [ -e "\$AT_DEVICE" ]; then
    echo "📶 Signal Test:"
    sudo stty -F "\$AT_DEVICE" 115200 cs8 -cstopb -parenb raw 2>/dev/null || true
    echo -e "AT+CSQ\r" | sudo tee "\$AT_DEVICE" >/dev/null
    sleep 2
    sudo timeout 3 cat "\$AT_DEVICE" 2>/dev/null || echo "No response"
    
    echo ""
    echo "📱 SIM Status:"
    echo -e "AT+CPIN?\r" | sudo tee "\$AT_DEVICE" >/dev/null
    sleep 2
    sudo timeout 3 cat "\$AT_DEVICE" 2>/dev/null || echo "No response"
else
    echo "❌ No AT device available"
fi

echo ""
echo "🌐 QMI Status:"
if [ -n "\$QMI_DEVICE" ] && [ -e "\$QMI_DEVICE" ]; then
    sudo qmicli -d "\$QMI_DEVICE" --nas-get-signal-strength 2>/dev/null || echo "QMI query failed"
else
    echo "❌ No QMI device available"
fi

echo ""
echo "📋 Connection Commands:"
echo "   Connect: sudo qmicli -d \$QMI_DEVICE --wds-start-network=\"apn=diginet\" --client-no-release-cid"
echo "   IP config: sudo dhclient wwan0"
echo "   Test: ping google.com"
EOF

    chmod +x /home/pi/quectel_test.sh
    success "Enhanced test script: ~/quectel_test.sh"
    
    # Status monitoring script
    cat > /home/pi/quectel_monitor.sh << 'EOF'
#!/bin/bash
# Continuous monitoring script

echo "Starting Quectel modem monitoring..."
echo "Press Ctrl+C to stop"

while true; do
    clear
    echo "=== Quectel Monitor - $(date) ==="
    
    # Voltage check
    voltage=$(vcgencmd measure_volts | grep -o '[0-9.]*')
    temp=$(cat /sys/class/thermal/thermal_zone0/temp)
    temp_c=$((temp/1000))
    
    printf "System: %sV %s°C" "$voltage" "$temp_c"
    if (( $(echo "$voltage < 1.1" | bc -l) )); then
        printf " ❌ LOW VOLTAGE!"
    fi
    echo ""
    
    # Device detection
    if lsusb | grep -q "2c7c:"; then
        echo "📱 USB: $(lsusb | grep "2c7c:" | cut -d' ' -f6-)"
    fi
    
    if lspci | grep -qi qualcomm; then
        echo "📱 PCIe: $(lspci | grep -i qualcomm | cut -d' ' -f3-)"
    fi
    
    # Devices
    if ls /dev/ttyUSB* >/dev/null 2>&1; then
        echo "📟 USB: $(ls /dev/ttyUSB* | wc -l) devices"
    fi
    
    if ls /dev/mhi_* >/dev/null 2>&1; then
        echo "📟 MHI: $(ls /dev/mhi_* | wc -l) devices"
    fi
    
    echo ""
    echo "Run ~/quectel_test.sh for detailed tests"
    
    sleep 5
done
EOF

    chmod +x /home/pi/quectel_monitor.sh
    success "Monitor script: ~/quectel_monitor.sh"
}

# Main execution function
main() {
    log "Starting enhanced Quectel setup..."
    
    # System health check first
    if ! check_system_health; then
        error "System health check failed - fix power issues first"
        exit 1
    fi
    
    # Detect modem type and connection method
    if ! detect_modem_type; then
        exit 1
    fi
    
    # Install appropriate packages
    install_packages
    
    # Apply connection-specific optimizations
    optimize_usb_connection
    initialize_pcie_modem
    
    # Critical: Fix ModemManager interference
    log "Disabling ModemManager interference..."
    sudo systemctl stop ModemManager 2>/dev/null || true
    sudo systemctl disable ModemManager 2>/dev/null || true
    sudo systemctl mask ModemManager 2>/dev/null || true
    sudo pkill -f ModemManager 2>/dev/null || true
    success "ModemManager disabled"
    
    # Wait for device stabilization
    log "Waiting for device stabilization..."
    sleep 5
    
    # Enhanced device detection
    if ! wait_for_devices; then
        exit 1
    fi
    
    # Find working AT port
    find_working_at_port || warning "AT port detection failed"
    
    # Setup QMI
    setup_qmi_connection || warning "QMI setup incomplete"
    
    # Signal strength check
    echo ""
    echo -e "${BLUE}======================================${NC}"
    echo -e "${BLUE}        SIGNAL & ANTENNA CHECK${NC}"
    echo -e "${BLUE}======================================${NC}"
    
    if check_signal_strength; then
        success "✅ Modem ready with good signal!"
    else
        warning "⚠️  Signal issues detected - check antenna"
    fi
    
    # Create test scripts
    create_enhanced_test_scripts
    
    # Final summary
    echo ""
    echo -e "${GREEN}============ SETUP COMPLETE ============${NC}"
    echo -e "${GREEN}Modem Type: $MODEM_TYPE${NC}"
    echo -e "${GREEN}Connection: $CONNECTION_MODE${NC}"
    echo -e "${GREEN}AT Device: $AT_PORT${NC}"
    echo -e "${GREEN}QMI Device: $QMI_DEVICE${NC}"
    echo ""
    echo "📁 Scripts created:"
    echo "   ~/quectel_test.sh - Quick tests"
    echo "   ~/quectel_monitor.sh - Continuous monitoring"
    echo ""
    echo "🚀 Next steps:"
    echo "1. Run: ~/quectel_test.sh"
    echo "2. Connect: sudo qmicli -d $QMI_DEVICE --wds-start-network=\"apn=diginet\" --client-no-release-cid"
    echo "3. IP config: sudo dhclient wwan0"
    echo "4. Test: ping google.com"
    
    success "Enhanced setup completed successfully!"
}

# Execute main function
main "$@"