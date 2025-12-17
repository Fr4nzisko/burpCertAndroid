#!/bin/bash
# Author: Lautaro D. Villarreal Culic'
# https://lautarovculic.com
# Modified by: Jose Francisco Flores aka: Fr4nzisko 
# (For macOS/Linux compatibility)

# Colors #########################
greenColor="\e[0;32m\033[1m"
endColor="\033[0m\e[0m"
redColor="\e[0;31m\033[1m"
blueColor="\e[0;34m\033[1m"
yellowColor="\e[0;33m\033[1m"
purpleColor="\e[0;35m\033[1m"
turquoiseColor="\e[0;36m\033[1m"
grayColor="\e[0;37m\033[1m"
##################################

# Helper function for echo with colors (macOS compatible)
echo_color() {
    local color_code="$1"
    local message="$2"
    printf "%b%s%b\n" "$color_code" "$message" "$endColor"
}

# CTRL C #########################
trap ctrl_c INT
function ctrl_c(){
    echo_color "$redColor" "[*] Exiting..."
    exit 0
}
##################################

# DOWNLOAD CERT ######################################################################################################
function downloadCert() {
    echo_color "$redColor" "[*] Downloading Cert"
    if curl -s http://127.0.0.1:8080/cert -o cacert.der; then
        echo_color "$redColor" "[*] Converting .der to .pem format"
        if openssl x509 -inform der -in cacert.der -out burpsuite.pem 2>/dev/null; then
            echo_color "$redColor" "[*] Checking and Renaming cert to hash"
            # Para macOS, usar head -n 1
            hash_value=$(openssl x509 -inform PEM -subject_hash_old -in burpsuite.pem 2>/dev/null | head -n 1)
            export hash_value
            if [[ -n $hash_value ]]; then
                mv burpsuite.pem "$hash_value.0"
                rm cacert.der
                echo_color "$greenColor" "[DONE]"
                selectDevice
            else
                echo_color "$redColor" "[ERROR] Failed to generate hash value"
                rm cacert.der burpsuite.pem
            fi
        else
            echo_color "$redColor" "[ERROR] Failed to convert .der to .pem format"
            rm cacert.der
        fi
    else
        echo_color "$redColor" "[ERROR] Failed to download certificate"
    fi
}

# SELECT DEVICE ######################################################################################################
function selectDevice() {
    echo_color "$redColor" "[*] Searching for Devices"
    # Asegurarse de que adb está en el PATH
    ADB_PATH=$(which adb 2>/dev/null)
    if [[ -z "$ADB_PATH" ]]; then
        # Buscar en ubicaciones comunes de macOS
        if [[ -f "/usr/local/bin/adb" ]]; then
            ADB_PATH="/usr/local/bin/adb"
        elif [[ -f "$HOME/Library/Android/sdk/platform-tools/adb" ]]; then
            ADB_PATH="$HOME/Library/Android/sdk/platform-tools/adb"
        else
            echo_color "$redColor" "[ERROR] ADB not found. Please install Android Platform Tools"
            return
        fi
    fi
    
    devices=$("$ADB_PATH" devices -l | grep -w 'device')
    device_count=$(echo "$devices" | wc -l | tr -d ' ')

    if [ "$device_count" -eq 0 ]; then
        echo_color "$redColor" "[ERROR] Please, run Genymotion or Android Emulator."
        return
    elif [ "$device_count" -eq 1 ]; then
        device=$(echo "$devices" | awk '{print $1}')
        echo_color "$greenColor" "[*] One device has been found: $device"
    else
        echo_color "$greenColor" "[*] Some devices have been found:"
        echo "$devices" | nl -w2 -s') '
        read -p "Select a number for one device: " device_number
        device=$(echo "$devices" | sed -n "${device_number}p" | awk '{print $1}')
    fi

    if [ -n "$device" ]; then
        # Obtener IP del dispositivo (manera más robusta)
        device_ip=$("$ADB_PATH" -s "$device" shell "ip route get 1 2>/dev/null | awk '{print \$NF; exit}'")
        if [[ -z "$device_ip" ]]; then
            device_ip=$("$ADB_PATH" -s "$device" shell "ifconfig 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print \$2}'")
        fi
        
        echo_color "$greenColor" "[*] Device selected: $device"
        if [[ -n "$device_ip" ]]; then
            echo_color "$greenColor" "[*] Device IP: $device_ip"
        fi
        echo_color "$greenColor" "[DONE]"
        export DEVICE_NAME="$device"
        export DEVICE_IP="$device_ip"
        installCert
    else
        echo_color "$redColor" "[ERROR] Can't get a device. Check connections and try again."
    fi
}

# DETECT DEVICE TYPE #################################################################################################
function detectDeviceType() {
    local device_info=$("$ADB_PATH" -s "$device" shell getprop ro.kernel.qemu 2>/dev/null)
    local build_product=$("$ADB_PATH" -s "$device" shell getprop ro.build.product 2>/dev/null)
    local build_model=$("$ADB_PATH" -s "$device" shell getprop ro.product.model 2>/dev/null)
    
    if [[ "$device_info" == "1" ]]; then
        if [[ "$build_product" == *"google_apis"* ]] || [[ "$build_model" == *"Google APIs"* ]] || [[ "$build_product" == *"sdk"* ]]; then
            echo "android_studio_emulator"
        elif [[ "$build_product" == *"genymotion"* ]] || [[ "$build_model" == *"Genymotion"* ]]; then
            echo "genymotion"
        else
            echo "generic_emulator"
        fi
    else
        echo "physical_device"
    fi
}

# CHECK ROOT ACCESS ##################################################################################################
function checkRootAccess() {
    local device_type="$1"
    
    # For Android Studio emulators try adb root first ####
    if [[ "$device_type" == "android_studio_emulator" ]] || [[ "$device_type" == "generic_emulator" ]]; then
        echo_color "$redColor" "[*] Attempting adb root for emulator"
        "$ADB_PATH" -s "$device" root >/dev/null 2>&1
        sleep 2
        
        # Check if we have root via adb ####
        local whoami_result=$("$ADB_PATH" -s "$device" shell whoami 2>/dev/null)
        if [[ "$whoami_result" == "root" ]]; then
            echo_color "$greenColor" "[*] Root access confirmed via adb root"
            echo "adb_root"
            return
        fi
    fi
    
    # Try su -c method for other devices ####
    local root_check=$("$ADB_PATH" -s "$device" shell "su -c 'id'" 2>/dev/null)
    if [[ $root_check == *"uid=0"* ]]; then
        echo_color "$greenColor" "[*] Root access confirmed via su"
        echo "su_root"
        return
    fi
    
    # Try alternative su syntax ####
    local root_check2=$("$ADB_PATH" -s "$device" shell "su 0 id" 2>/dev/null)
    if [[ $root_check2 == *"uid=0"* ]]; then
        echo_color "$greenColor" "[*] Root access confirmed via su 0"
        echo "su0_root"
        return
    fi
    
    echo "no_root"
}

# INSTALL CERT #######################################################################################################
function installCert() {
    local cert="$hash_value.0"
    local device_type=$(detectDeviceType)

    echo_color "$redColor" "[*] Installing cert on device"
    echo_color "$blueColor" "[*] Device type detected: $device_type"
    
    # Push certificate to device first ####
    echo_color "$redColor" "[*] Pushing certificate to device"
    "$ADB_PATH" -s "$device" push "$cert" /sdcard/ >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo_color "$redColor" "[ERROR] Failed to push certificate to device"
        return
    fi

    # Check root access ####
    echo_color "$redColor" "[*] Checking root access"
    local root_method=$(checkRootAccess "$device_type")
    
    if [[ "$root_method" == "no_root" ]]; then
        handleNonRootDevice "$cert" "$device_type"
        return
    fi

    # Install certificate ####
    case $root_method in
        "adb_root")
            installCertWithAdbRoot "$cert"
            ;;
        "su_root")
            installCertWithSu "$cert"
            ;;
        "su0_root")
            installCertWithSu0 "$cert"
            ;;
        *)
            echo_color "$yellowColor" "[!] Unknown root method, trying standard approach"
            installCertWithSu "$cert"
            ;;
    esac
}

# INSTALL CERT WITH ADB ROOT (Android Studio Emulators) ##############################################################
function installCertWithAdbRoot() {
    local cert="$1"
    
    echo_color "$yellowColor" "[*] Using adb root method for emulator"
    
    # Remount system as read-write ####
    echo_color "$redColor" "[*] Remounting system partition"
    "$ADB_PATH" -s "$device" shell "mount -o remount,rw /" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        "$ADB_PATH" -s "$device" shell "mount -o rw,remount /system" >/dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo_color "$redColor" "[ERROR] Failed to remount system partition"
            fallbackUserInstall "$cert"
            return
        fi
    fi

    # Copy certificate ####
    echo_color "$redColor" "[*] Copying certificate to system directory"
    "$ADB_PATH" -s "$device" shell "cp /sdcard/$cert /system/etc/security/cacerts/" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo_color "$redColor" "[ERROR] Failed to copy certificate to system directory"
        fallbackUserInstall "$cert"
        return
    fi

    # Set ownership ####
    echo_color "$redColor" "[*] Setting certificate ownership"
    "$ADB_PATH" -s "$device" shell "chown root:root /system/etc/security/cacerts/$cert" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo_color "$yellowColor" "[!] Warning: Failed to set certificate ownership (might still work)"
    fi

    # Set permissions ####
    echo_color "$redColor" "[*] Setting certificate permissions"
    "$ADB_PATH" -s "$device" shell "chmod 644 /system/etc/security/cacerts/$cert" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo_color "$yellowColor" "[!] Warning: Failed to set certificate permissions (might still work)"
    fi

    # Verify installation ####
    echo_color "$redColor" "[*] Verifying certificate installation"
    "$ADB_PATH" -s "$device" shell "ls -la /system/etc/security/cacerts/$cert" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo_color "$greenColor" "[*] Certificate successfully installed as SYSTEM certificate"
        
        # Clean temp files #### 
        "$ADB_PATH" -s "$device" shell "rm /sdcard/$cert" >/dev/null 2>&1
        rm "$cert"
        
        echo_color "$greenColor" "[DONE]"
        echo_color "$greenColor" "[*] Please restart your emulator for the certificate to take effect"
        echo_color "$greenColor" "[*] https://lautarovculic.com"
        echo ""
        echo "Do you want to automate and control the flow of proxy?"
        echo "Check https://github.com/lautarovculic/burpCertAndroid/?tab=readme-ov-file#setup-your-proxy-in-bash"
        echo ""
    else
        echo_color "$redColor" "[ERROR] Certificate installation verification failed"
        fallbackUserInstall "$cert"
    fi
}

# INSTALL CERT WITH SU -C (Physical devices, Genymotion) #############################################################
function installCertWithSu() {
    local cert="$1"
    
    echo_color "$yellowColor" "[*] Using su -c method"
    
    # Remount system as read-write ####
    echo_color "$redColor" "[*] Remounting system partition"
    "$ADB_PATH" -s "$device" shell "su -c 'mount -o remount,rw /'" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo_color "$redColor" "[ERROR] Failed to remount system partition"
        fallbackUserInstall "$cert"
        return
    fi

    # Copy certificate to system directory ####
    echo_color "$redColor" "[*] Copying certificate to system directory"
    "$ADB_PATH" -s "$device" shell "su -c 'cp /sdcard/$cert /system/etc/security/cacerts/'" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo_color "$redColor" "[ERROR] Failed to copy certificate to system directory"
        fallbackUserInstall "$cert"
        return
    fi

    # Set ownership ####
    echo_color "$redColor" "[*] Setting certificate ownership"
    "$ADB_PATH" -s "$device" shell "su -c 'chown root:root /system/etc/security/cacerts/$cert'" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo_color "$yellowColor" "[!] Warning: Failed to set certificate ownership (might still work)"
    fi

    # Set permissions ####
    echo_color "$redColor" "[*] Setting certificate permissions"
    "$ADB_PATH" -s "$device" shell "su -c 'chmod 644 /system/etc/security/cacerts/$cert'" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo_color "$yellowColor" "[!] Warning: Failed to set certificate permissions (might still work)"
    fi

    # Verify installation ####
    echo_color "$redColor" "[*] Verifying certificate installation"
    "$ADB_PATH" -s "$device" shell "su -c 'ls -la /system/etc/security/cacerts/$cert'" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo_color "$greenColor" "[*] Certificate successfully installed as SYSTEM certificate"
        
        # Clean temp files ####
        "$ADB_PATH" -s "$device" shell "su -c 'rm /sdcard/$cert'" >/dev/null 2>&1
        rm "$cert"
        
        echo_color "$greenColor" "[DONE]"
        echo_color "$greenColor" "[*] Please reboot your device for the certificate to take effect"
        echo_color "$greenColor" "[*] https://lautarovculic.com"
        echo ""
        echo "Do you want to automate and control the flow of proxy?"
        echo "Check https://github.com/lautarovculic/burpCertAndroid/?tab=readme-ov-file#setup-your-proxy-in-bash"
        echo ""
    else
        echo_color "$redColor" "[ERROR] Certificate installation verification failed"
        fallbackUserInstall "$cert"
    fi
}

# INSTALL CERT WITH SU 0 (Alternative su syntax) #####################################################################
function installCertWithSu0() {
    local cert="$1"
    
    echo_color "$yellowColor" "[*] Using su 0 method"
    
    # Remount system as read-write ####
    echo_color "$redColor" "[*] Remounting system partition"
    "$ADB_PATH" -s "$device" shell "su 0 mount -o remount,rw /" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo_color "$redColor" "[ERROR] Failed to remount system partition"
        fallbackUserInstall "$cert"
        return
    fi

    # Copy certificate to system directory ####
    echo_color "$redColor" "[*] Copying certificate to system directory"
    "$ADB_PATH" -s "$device" shell "su 0 cp /sdcard/$cert /system/etc/security/cacerts/" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo_color "$redColor" "[ERROR] Failed to copy certificate to system directory"
        fallbackUserInstall "$cert"
        return
    fi

    # Set ownership ####
    echo_color "$redColor" "[*] Setting certificate ownership"
    "$ADB_PATH" -s "$device" shell "su 0 chown root:root /system/etc/security/cacerts/$cert" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo_color "$yellowColor" "[!] Warning: Failed to set certificate ownership (might still work)"
    fi

    # Set permissions ####
    echo_color "$redColor" "[*] Setting certificate permissions"
    "$ADB_PATH" -s "$device" shell "su 0 chmod 644 /system/etc/security/cacerts/$cert" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo_color "$yellowColor" "[!] Warning: Failed to set certificate permissions (might still work)"
    fi

    # Verify installation ####
    echo_color "$redColor" "[*] Verifying certificate installation"
    "$ADB_PATH" -s "$device" shell "su 0 ls -la /system/etc/security/cacerts/$cert" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo_color "$greenColor" "[*] Certificate successfully installed as SYSTEM certificate"
        
        # Clean temp files ####
        "$ADB_PATH" -s "$device" shell "su 0 rm /sdcard/$cert" >/dev/null 2>&1
        rm "$cert"
        
        echo_color "$greenColor" "[DONE]"
        echo_color "$greenColor" "[*] Please reboot your device for the certificate to take effect"
        echo_color "$greenColor" "[*] https://lautarovculic.com"
        echo ""
        echo "Do you want to automate and control the flow of proxy?"
        echo "Check https://github.com/lautarovculic/burpCertAndroid/?tab=readme-ov-file#setup-your-proxy-in-bash"
        echo ""
    else
        echo_color "$redColor" "[ERROR] Certificate installation verification failed"
        fallbackUserInstall "$cert"
    fi
}

# FALLBACK: INSTALL AS USER CERTIFICATE ##############################################################################
function fallbackUserInstall() {
    local cert="$1"
    
    echo_color "$yellowColor" "[!] Falling back to USER certificate installation"
    echo_color "$yellowColor" "[!] Note: Some apps may not trust user certificates"
    
    # Convert to .crt for user installation ####
    local user_cert="burpsuite_user.crt"
    cp "$cert" "$user_cert"
    
    "$ADB_PATH" -s "$device" push "$user_cert" /sdcard/ >/dev/null 2>&1
    
    echo_color "$blueColor" "[Manual Steps for User Certificate]"
    echo_color "$grayColor" "1. On your device, go to Settings > Security > Encryption & credentials"
    echo_color "$grayColor" "2. Tap 'Install a certificate'"
    echo_color "$grayColor" "3. Select 'CA certificate'"
    echo_color "$grayColor" "4. Navigate to /sdcard/ and select $user_cert"
    echo_color "$grayColor" "5. Give it a name and tap OK"
    
    echo_color "$purpleColor" "[*] User certificate will be installed and trusted for most apps"
    echo_color "$yellowColor" "[!] For apps with certificate pinning, you may need additional steps"
    echo ""
    
    rm "$cert" "$user_cert" 2>/dev/null
}

# HANDLE NON-ROOT DEVICES ############################################################################################
function handleNonRootDevice() {
    local cert="$1"
    local device_type="$2"
    
    echo_color "$yellowColor" "[!] Root access not available"
    
    if [[ "$device_type" == "android_studio_emulator" ]]; then
        echo_color "$yellowColor" "[!] For Android Studio emulators without root:"
        echo_color "$grayColor" "1. Use an emulator image WITHOUT Google Play Store"
        echo_color "$grayColor" "2. Or enable root access in AVD settings"
        echo_color "$grayColor" "3. Or use Magisk modules for rooting"
    fi
    
    echo_color "$blueColor" "[*] Attempting user certificate installation instead"
    fallbackUserInstall "$cert"
}

# MAIN VALIDATIONS ###################################################################################################
echo_color "$redColor" "[*] Checking if ADB is installed."
if ! command -v adb &>/dev/null; then
    echo_color "$redColor" "[!] ADB is not installed, please install ADB."
    echo_color "$yellowColor" "[*] You can install it using: brew install android-platform-tools"
    exit 1
fi
echo_color "$greenColor" "[DONE]"

echo_color "$redColor" "[*] Checking if OPENSSL is installed."
if ! command -v openssl &>/dev/null; then
    echo_color "$redColor" "[!] OPENSSL is not installed, please install OPENSSL."
    echo_color "$yellowColor" "[*] You can install it using: brew install openssl"
    exit 1
fi
echo_color "$greenColor" "[DONE]"

echo_color "$redColor" "[*] Checking if BurpSuite is Running."
# Método mejorado para detectar BurpSuite en macOS
# Buscar por múltiples patrones comunes
if [[ $(ps aux | grep -i "burpsuite" | grep -v grep | wc -l | tr -d ' ') -eq 0 ]] && \
   [[ $(ps aux | grep -i "burp" | grep -v grep | wc -l | tr -d ' ') -eq 0 ]] && \
   [[ $(ps aux | grep -i "java.*burp" | grep -v grep | wc -l | tr -d ' ') -eq 0 ]]; then
    
    echo_color "$redColor" "[!] BurpSuite doesn't seem to be running."
    echo_color "$yellowColor" "[*] Please make sure:"
    echo_color "$yellowColor" "1. BurpSuite Professional/Community is running"
    echo_color "$yellowColor" "2. Proxy listener is enabled on 127.0.0.1:8080"
    echo_color "$yellowColor" "3. Intercept is OFF to allow certificate download"
    
    # Preguntar si quieren continuar de todos modos
    echo ""
    read -p "Do you want to continue anyway? (y/n): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    else
        echo_color "$yellowColor" "[*] Continuing without BurpSuite verification..."
    fi
else
    echo_color "$greenColor" "[DONE] BurpSuite detected"
fi
echo ""

# Start it all
downloadCert
