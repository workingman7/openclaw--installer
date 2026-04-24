#!/data/data/com.termux/files/usr/bin/bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║     OpenClaw Auto-Installer v1.0 — Rooted Android Edition       ║
# ║     Run this ONCE inside Termux — everything installs auto      ║
# ╚══════════════════════════════════════════════════════════════════╝
# Usage (inside Termux): curl -sL https://YOUR_HOST/install.sh | bash
# OR: bash install.sh

set -e

# ─── Colors ───────────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
B='\033[0;34m'; C='\033[0;36m'; W='\033[1;37m'; N='\033[0m'

# ─── Config ───────────────────────────────────────────────────────
INSTALL_LOG="/data/data/com.termux/files/home/openclaw_install.log"
UBUNTU_HOME="/data/data/com.termux/files/home/../usr/var/lib/proot-distro/installed-rootfs/ubuntu/root"
TERMUX_PREFIX="/data/data/com.termux/files/usr"
BOOT_SCRIPT="$HOME/.termux/boot/openclaw.sh"

# ─── Helpers ──────────────────────────────────────────────────────
log()  { echo -e "${W}[$(date '+%H:%M:%S')]${N} $1" | tee -a "$INSTALL_LOG"; }
ok()   { echo -e "${G}  ✓ $1${N}" | tee -a "$INSTALL_LOG"; }
warn() { echo -e "${Y}  ⚠ $1${N}" | tee -a "$INSTALL_LOG"; }
err()  { echo -e "${R}  ✗ $1${N}" | tee -a "$INSTALL_LOG"; }
step() { echo -e "\n${C}━━━ $1 ━━━${N}" | tee -a "$INSTALL_LOG"; }
ask()  { echo -e "${Y}  → $1${N}"; read -r REPLY; echo "$REPLY"; }

banner() {
  clear
  echo -e "${C}"
  cat << 'EOF'
  ╔═══════════════════════════════════════════════╗
  ║   ██████╗ ██████╗ ███████╗███╗   ██╗         ║
  ║  ██╔═══██╗██╔══██╗██╔════╝████╗  ██║         ║
  ║  ██║   ██║██████╔╝█████╗  ██╔██╗ ██║         ║
  ║  ██║   ██║██╔═══╝ ██╔══╝  ██║╚██╗██║         ║
  ║  ╚██████╔╝██║     ███████╗██║ ╚████║         ║
  ║   ╚═════╝ ╚═╝     ╚══════╝╚═╝  ╚═══╝         ║
  ║         CLAW  —  Auto Installer v1.0          ║
  ║         APK Modding Agent for Android         ║
  ╚═══════════════════════════════════════════════╝
EOF
  echo -e "${N}"
}

# ─── Preflight checks ─────────────────────────────────────────────
preflight_check() {
  step "Pre-flight Checks"

  # Check Termux
  if [ ! -d "/data/data/com.termux" ]; then
    err "Termux not found! Install from F-Droid first."
    exit 1
  fi
  ok "Termux detected"

  # Check root
  if ! su -c "id" 2>/dev/null | grep -q "uid=0"; then
    err "Root access not available! Grant root to Termux in APatch."
    err "APatch → SuperUser → Termux → Grant"
    exit 1
  fi
  ok "Root access confirmed (APatch)"

  # Check internet
  if ! ping -c 1 8.8.8.8 &>/dev/null && ! ping -c 1 1.1.1.1 &>/dev/null; then
    err "No internet connection! Connect to WiFi or mobile data."
    exit 1
  fi
  ok "Internet connection OK"

  # Check storage
  AVAIL=$(df "$HOME" | tail -1 | awk '{print $4}')
  if [ "$AVAIL" -lt 2000000 ]; then
    warn "Low storage: ${AVAIL}KB available. Need at least 2GB."
    warn "Proceeding anyway — will fail if space runs out."
  else
    ok "Storage: $(( AVAIL / 1024 ))MB available"
  fi
}

# ─── Collect credentials from user ───────────────────────────────
collect_credentials() {
  step "API Keys & Configuration"
  echo -e "${W}These are needed ONCE — will be saved securely in config.${N}\n"

  echo -e "${B}1. OpenRouter API Key${N}"
  echo -e "   Get free at: ${C}https://openrouter.ai${N} → Keys → Create Key"
  printf "   Paste your key (sk-or-v1-...): "
  read -r OPENROUTER_KEY
  if [[ ! "$OPENROUTER_KEY" =~ ^sk-or-v1- ]]; then
    warn "Key doesn't look right — double check format. Continuing anyway."
  fi

  echo -e "\n${B}2. Telegram Bot Token${N}"
  echo -e "   Get from: ${C}@BotFather${N} → /newbot → copy token"
  printf "   Paste bot token (1234...:ABCxxx): "
  read -r BOT_TOKEN
  if [[ ! "$BOT_TOKEN" =~ ^[0-9]+: ]]; then
    warn "Token format looks off. Check @BotFather output."
  fi

  echo -e "\n${B}3. Your Telegram User ID${N}"
  echo -e "   Get from: ${C}@userinfobot${N} → /start → copy number"
  printf "   Paste your Telegram ID: "
  read -r TG_USER_ID
  if ! [[ "$TG_USER_ID" =~ ^[0-9]+$ ]]; then
    err "Telegram ID must be a number only (e.g. 123456789)"
    exit 1
  fi

  echo -e "\n${B}4. AI Model (press Enter for recommended)${N}"
  echo -e "   Options: deepseek (best), llama (fast), qwen (balanced)"
  printf "   Choose [deepseek/llama/qwen] (default: deepseek): "
  read -r MODEL_CHOICE
  case "$MODEL_CHOICE" in
    llama) AI_MODEL="meta-llama/llama-3.3-70b-instruct:free" ;;
    qwen)  AI_MODEL="qwen/qwen-2.5-72b-instruct:free" ;;
    *)     AI_MODEL="deepseek/deepseek-r1:free" ;;
  esac

  ok "Credentials collected. Starting installation..."
  sleep 1
}

# ─── Termux setup ─────────────────────────────────────────────────
setup_termux() {
  step "Termux Environment Setup"

  log "Updating Termux packages..."
  pkg update -y >> "$INSTALL_LOG" 2>&1 && ok "Packages updated" || warn "Some packages had errors — continuing"

  log "Installing Termux dependencies..."
  pkg install -y proot-distro tsu termux-tools >> "$INSTALL_LOG" 2>&1
  ok "proot-distro, tsu installed"

  log "Setting up storage access..."
  if [ ! -d "$HOME/storage" ]; then
    termux-setup-storage 2>/dev/null || true
  fi
  ok "Storage configured"

  log "Setting up Termux:Boot directory..."
  mkdir -p "$HOME/.termux/boot"
  ok "Boot directory ready"
}

# ─── Ubuntu install ───────────────────────────────────────────────
setup_ubuntu() {
  step "Ubuntu Installation (proot)"

  if proot-distro list 2>/dev/null | grep -q "ubuntu.*installed"; then
    ok "Ubuntu already installed — skipping download"
  else
    log "Downloading Ubuntu (~400MB)..."
    proot-distro install ubuntu >> "$INSTALL_LOG" 2>&1
    ok "Ubuntu installed"
  fi
}

# ─── Run commands inside Ubuntu ───────────────────────────────────
ubuntu_run() {
  proot-distro login ubuntu -- bash -c "$1" >> "$INSTALL_LOG" 2>&1
}

ubuntu_run_log() {
  log "$1"
  proot-distro login ubuntu -- bash -c "$2" >> "$INSTALL_LOG" 2>&1
  ok "$1 done"
}

# ─── Ubuntu environment setup ────────────────────────────────────
setup_ubuntu_env() {
  step "Ubuntu Environment"

  ubuntu_run_log "Updating Ubuntu packages" "apt update -y && apt upgrade -y"

  ubuntu_run_log "Installing base tools" \
    "apt install -y curl wget git python3 python3-pip unzip zip nano build-essential 2>&1"

  ubuntu_run_log "Installing Java 17" \
    "apt install -y openjdk-17-jdk 2>&1"

  # Set JAVA_HOME
  ubuntu_run "
    echo 'export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-arm64' >> /root/.bashrc
    echo 'export PATH=\$JAVA_HOME/bin:\$PATH' >> /root/.bashrc
    source /root/.bashrc
  "
  ok "JAVA_HOME configured"
}

# ─── Node.js via NVM ──────────────────────────────────────────────
setup_nodejs() {
  step "Node.js v20 Installation"

  ubuntu_run "
    export HOME=/root
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    export NVM_DIR=\"\$HOME/.nvm\"
    [ -s \"\$NVM_DIR/nvm.sh\" ] && \\. \"\$NVM_DIR/nvm.sh\"
    nvm install 20
    nvm alias default 20
    # Persist NVM in bashrc
    grep -q 'NVM_DIR' /root/.bashrc || cat >> /root/.bashrc << 'BASHEOF'
export NVM_DIR=\"\$HOME/.nvm\"
[ -s \"\$NVM_DIR/nvm.sh\" ] && \\. \"\$NVM_DIR/nvm.sh\"
BASHEOF
  "
  ok "Node.js 20 LTS installed"

  ubuntu_run "
    export NVM_DIR=\"/root/.nvm\"
    [ -s \"\$NVM_DIR/nvm.sh\" ] && \\. \"\$NVM_DIR/nvm.sh\"
    npm install -g openclaw
  "
  ok "OpenClaw npm package installed"
}

# ─── hijack.js (Android network fix) ─────────────────────────────
create_hijack_js() {
  step "Android Network Fix (hijack.js)"

  ubuntu_run "cat > /root/hijack.js << 'JSEOF'
const os = require('os');
const orig = os.networkInterfaces.bind(os);
os.networkInterfaces = function() {
  try {
    const i = orig();
    if (!i || Object.keys(i).length === 0) {
      return { lo: [{ address: '127.0.0.1', netmask: '255.0.0.0', family: 'IPv4', mac: '00:00:00:00:00:00', internal: true, cidr: '127.0.0.1/8' }] };
    }
    return i;
  } catch(e) {
    return { lo: [{ address: '127.0.0.1', netmask: '255.0.0.0', family: 'IPv4', mac: '00:00:00:00:00:00', internal: true, cidr: '127.0.0.1/8' }] };
  }
};
require('openclaw');
JSEOF"
  ok "hijack.js created — Android network bug fixed"
}

# ─── APK Modding Tools ────────────────────────────────────────────
setup_apk_tools() {
  step "APK Modding Tools (JADX + Apktool + Signer)"

  ubuntu_run "mkdir -p /root/apk-tools"

  # Apktool
  log "Downloading Apktool..."
  ubuntu_run "
    wget -q https://bitbucket.org/iBotPeaches/apktool/downloads/apktool_2.9.3.jar \
      -O /root/apk-tools/apktool.jar
    printf '#!/bin/bash\njava -jar /root/apk-tools/apktool.jar \"\$@\"\n' > /usr/local/bin/apktool
    chmod +x /usr/local/bin/apktool
  "
  ok "Apktool 2.9.3 installed"

  # JADX
  log "Downloading JADX..."
  ubuntu_run "
    wget -q https://github.com/skylot/jadx/releases/download/v1.4.7/jadx-1.4.7.zip \
      -O /root/apk-tools/jadx.zip
    unzip -q /root/apk-tools/jadx.zip -d /root/apk-tools/jadx/
    ln -sf /root/apk-tools/jadx/bin/jadx /usr/local/bin/jadx
    chmod +x /root/apk-tools/jadx/bin/jadx
  "
  ok "JADX 1.4.7 installed"

  # uber-apk-signer
  log "Downloading APK Signer..."
  ubuntu_run "
    wget -q https://github.com/patrickfav/uber-apk-signer/releases/download/v1.3.0/uber-apk-signer-1.3.0.jar \
      -O /root/apk-tools/uber-apk-signer.jar
    printf '#!/bin/bash\njava -jar /root/apk-tools/uber-apk-signer.jar \"\$@\"\n' > /usr/local/bin/apksign
    chmod +x /usr/local/bin/apksign
  "
  ok "uber-apk-signer 1.3.0 installed"
}

# ─── Write OpenClaw config ────────────────────────────────────────
write_config() {
  step "OpenClaw Configuration"

  ubuntu_run "mkdir -p /root/.openclaw"

  # Write config.json with actual credentials
  ubuntu_run "cat > /root/.openclaw/config.json << CFEOF
{
  \"shell\": \"/data/data/com.termux/files/usr/bin/tsu\",
  \"shellArgs\": [\"-c\"],
  \"rootEnabled\": true,
  \"ai\": {
    \"provider\": \"openrouter\",
    \"apiKey\": \"$OPENROUTER_KEY\",
    \"model\": \"$AI_MODEL\",
    \"baseURL\": \"https://openrouter.ai/api/v1\"
  },
  \"telegram\": {
    \"token\": \"$BOT_TOKEN\",
    \"allowedUsers\": [$TG_USER_ID],
    \"maxFileSize\": 50
  },
  \"systemPromptFile\": \"/root/.openclaw/system_prompt.txt\"
}
CFEOF"
  ok "config.json written with your credentials"

  # Write system prompt
  ubuntu_run "cat > /root/.openclaw/system_prompt.txt << 'SPEOF'
You are an expert Android APK modding agent running on a rooted OnePlus 9 (APatch root, 12GB RAM).
Available tools: apktool 2.9.3, jadx 1.4.7, apksign (uber-apk-signer), java 17, root shell via tsu.
Working directory: /tmp

STANDARD APK MODDING WORKFLOW:
1. Receive APK via Telegram → save to /tmp/input.apk
2. Decompile: apktool d /tmp/input.apk -o /tmp/apk_out -f
3. Analyze Java source: jadx -d /tmp/apk_java /tmp/input.apk
4. Make requested changes to smali files in /tmp/apk_out/smali/
5. Recompile: apktool b /tmp/apk_out -o /tmp/output_unsigned.apk
   If fails: apktool b /tmp/apk_out --use-aapt2 -o /tmp/output_unsigned.apk
6. Sign: apksign -a /tmp/output_unsigned.apk -o /tmp/
7. Send signed APK back to user via Telegram

COMMON MOD TECHNIQUES:
- Remove ads: Find ad SDK init in smali (AdMob: Lcom/google/android/gms/ads), comment with # or replace invoke with return-void
- Unlock premium: Find boolean checks, change const/4 v0, 0x0 to const/4 v0, 0x1
- Remove license check: Find LicenseValidator/LicenseChecker calls, replace block with return-void
- Enable debug: Find BuildConfig.DEBUG reference, patch to return true (0x1)

RULES:
- Always explain in simple terms what changes were made
- If step fails, try fallback approaches before giving up
- Clean up /tmp/ between operations to save space
- Use root shell for any permission issues
SPEOF"
  ok "System prompt written — AI knows APK modding workflow"
}

# ─── Boot auto-start script ───────────────────────────────────────
setup_autostart() {
  step "Auto-Start on Boot"

  cat > "$BOOT_SCRIPT" << 'BOOTEOF'
#!/data/data/com.termux/files/usr/bin/bash
sleep 30
termux-wake-lock
proot-distro login ubuntu -- bash -c '
  export HOME=/root
  export NVM_DIR="$HOME/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-arm64
  export PATH=$JAVA_HOME/bin:$PATH
  cd /root
  node hijack.js >> /tmp/openclaw.log 2>&1
' &
BOOTEOF

  chmod +x "$BOOT_SCRIPT"
  ok "Boot script created — OpenClaw will auto-start on reboot"
}

# ─── Create convenient launcher ───────────────────────────────────
create_launcher() {
  step "Creating Launcher Script"

  cat > "$HOME/start_openclaw.sh" << 'LAUNCHEOF'
#!/data/data/com.termux/files/usr/bin/bash
echo "Starting OpenClaw..."
proot-distro login ubuntu -- bash -c '
  export HOME=/root
  export NVM_DIR="$HOME/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-arm64
  export PATH=$JAVA_HOME/bin:$PATH
  cd /root
  node hijack.js
'
LAUNCHEOF

  chmod +x "$HOME/start_openclaw.sh"

  # Also create a Termux widget shortcut script
  mkdir -p "$HOME/.shortcuts"
  cat > "$HOME/.shortcuts/OpenClaw" << 'WEOF'
#!/data/data/com.termux/files/usr/bin/bash
bash ~/start_openclaw.sh
WEOF
  chmod +x "$HOME/.shortcuts/OpenClaw"

  ok "Launcher created: ~/start_openclaw.sh"
  ok "Widget shortcut: ~/.shortcuts/OpenClaw"
}

# ─── Verification ─────────────────────────────────────────────────
verify_installation() {
  step "Verifying Installation"

  ERRORS=0

  # Check proot-distro
  proot-distro list 2>/dev/null | grep -q "ubuntu" && ok "Ubuntu: OK" || { err "Ubuntu: MISSING"; ERRORS=$((ERRORS+1)); }

  # Check tsu
  command -v tsu &>/dev/null && ok "tsu (root bridge): OK" || { err "tsu: MISSING"; ERRORS=$((ERRORS+1)); }

  # Check Java
  ubuntu_run "java -version" 2>/dev/null && ok "Java 17: OK" || { err "Java: MISSING"; ERRORS=$((ERRORS+1)); }

  # Check Node
  ubuntu_run "node --version" 2>/dev/null && ok "Node.js: OK" || { err "Node.js: MISSING"; ERRORS=$((ERRORS+1)); }

  # Check OpenClaw
  ubuntu_run "ls /root/hijack.js" 2>/dev/null && ok "hijack.js: OK" || { err "hijack.js: MISSING"; ERRORS=$((ERRORS+1)); }

  # Check APK tools
  ubuntu_run "ls /root/apk-tools/apktool.jar" 2>/dev/null && ok "Apktool: OK" || { err "Apktool: MISSING"; ERRORS=$((ERRORS+1)); }
  ubuntu_run "ls /root/apk-tools/jadx.zip" 2>/dev/null && ok "JADX: OK" || { err "JADX: MISSING"; ERRORS=$((ERRORS+1)); }
  ubuntu_run "ls /root/apk-tools/uber-apk-signer.jar" 2>/dev/null && ok "Signer: OK" || { err "Signer: MISSING"; ERRORS=$((ERRORS+1)); }

  # Check config
  ubuntu_run "cat /root/.openclaw/config.json" 2>/dev/null | grep -q "openrouter" && ok "Config: OK" || { err "Config: MISSING"; ERRORS=$((ERRORS+1)); }

  if [ "$ERRORS" -eq 0 ]; then
    return 0
  else
    return 1
  fi
}

# ─── Final summary ────────────────────────────────────────────────
show_summary() {
  echo -e "\n${G}"
  cat << 'EOF'
  ╔═══════════════════════════════════════════════╗
  ║        ✓  INSTALLATION COMPLETE!              ║
  ╚═══════════════════════════════════════════════╝
EOF
  echo -e "${N}"

  echo -e "${W}What was installed:${N}"
  echo -e "  ${G}✓${N} Ubuntu (proot-distro)"
  echo -e "  ${G}✓${N} Java 17 (OpenJDK)"
  echo -e "  ${G}✓${N} Node.js 20 LTS (via NVM)"
  echo -e "  ${G}✓${N} OpenClaw + Android fix (hijack.js)"
  echo -e "  ${G}✓${N} Apktool 2.9.3"
  echo -e "  ${G}✓${N} JADX 1.4.7"
  echo -e "  ${G}✓${N} uber-apk-signer 1.3.0"
  echo -e "  ${G}✓${N} Config with your API keys"
  echo -e "  ${G}✓${N} Auto-start on boot"

  echo -e "\n${W}How to start OpenClaw:${N}"
  echo -e "  ${C}bash ~/start_openclaw.sh${N}"
  echo -e "  ${B}Or just reboot phone — it starts automatically!${N}"

  echo -e "\n${W}How to use:${N}"
  echo -e "  1. Open Telegram → your bot"
  echo -e "  2. Send any APK file with a caption like:"
  echo -e "     ${Y}\"Remove ads and unlock premium\"${N}"
  echo -e "  3. Wait — agent will send modified APK back"

  echo -e "\n${W}Log file:${N} ${C}$INSTALL_LOG${N}"
  echo -e "${W}Start script:${N} ${C}~/start_openclaw.sh${N}"

  echo -e "\n${Y}First launch: Run 'bash ~/start_openclaw.sh' now!${N}\n"
}

# ─── MAIN ─────────────────────────────────────────────────────────
main() {
  > "$INSTALL_LOG"  # Clear log

  banner
  echo -e "${W}This will auto-install everything needed for OpenClaw APK modding.${N}"
  echo -e "${Y}Estimated time: 10-20 minutes (depends on internet speed)${N}"
  echo -e "${R}Requirements: Termux (F-Droid), APatch root granted to Termux${N}\n"

  printf "Press ENTER to start installation (Ctrl+C to cancel)..."
  read -r

  preflight_check
  collect_credentials
  setup_termux
  setup_ubuntu
  setup_ubuntu_env
  setup_nodejs
  create_hijack_js
  setup_apk_tools
  write_config
  setup_autostart
  create_launcher

  echo ""
  if verify_installation; then
    show_summary
  else
    echo -e "\n${R}Some components failed to install.${N}"
    echo -e "${Y}Check log: cat $INSTALL_LOG${N}"
    echo -e "${Y}Try running the script again — partial installs usually succeed on retry.${N}"
    exit 1
  fi
}

main "$@"
