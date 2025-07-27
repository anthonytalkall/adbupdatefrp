#!/bin/bash
# Script mínimo para servidores com pouca RAM

echo "======================================"
echo "🚀 Instalação Mínima FRP Server"
echo "======================================"

# Criar swap se não existir
if [ ! -f /swapfile ]; then
    echo "📦 Criando swap..."
    sudo fallocate -l 1G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
fi

# Baixar FRP apenas
echo "📥 Baixando FRP..."
cd /opt
sudo wget -q https://github.com/fatedier/frp/releases/download/v0.52.3/frp_0.52.3_linux_amd64.tar.gz
sudo tar -xzf frp_0.52.3_linux_amd64.tar.gz
sudo mv frp_0.52.3_linux_amd64 frp
sudo rm frp_0.52.3_linux_amd64.tar.gz

# Configuração
echo "⚙️ Configurando..."
sudo tee /opt/frp/frps.ini > /dev/null << 'EOF'
[common]
bind_port = 7000
dashboard_port = 7500
dashboard_user = admin
dashboard_pwd = adb2024admin
token = adb-bridge-2024
# Portas permitidas: ADB, WS-SCRCPY, e portas adicionais
allow_ports = 5037,7100,7200,8000-8002,8886-8899
EOF

# Serviço
echo "🔧 Criando serviço..."
sudo tee /etc/systemd/system/frps.service > /dev/null << 'EOF'
[Unit]
Description=FRP Server
After=network.target

[Service]
Type=simple
ExecStart=/opt/frp/frps -c /opt/frp/frps.ini
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Firewall básico
echo "🔥 Configurando firewall..."
# SSH, FRP Control, FRP Dashboard
sudo ufw allow 22/tcp > /dev/null 2>&1
sudo ufw allow 7000/tcp > /dev/null 2>&1
sudo ufw allow 7500/tcp > /dev/null 2>&1
# WS-SCRCPY ports
sudo ufw allow 8000:8002/tcp > /dev/null 2>&1
sudo ufw allow 8886:8899/tcp > /dev/null 2>&1
# ADB port
sudo ufw allow 5037/tcp > /dev/null 2>&1
# Additional ports
sudo ufw allow 7100/tcp > /dev/null 2>&1
sudo ufw allow 7200/tcp > /dev/null 2>&1
echo "y" | sudo ufw enable > /dev/null 2>&1

# Iniciar
echo "▶️ Iniciando FRP..."
sudo systemctl daemon-reload
sudo systemctl enable frps > /dev/null 2>&1
sudo systemctl start frps

# Info
echo ""
echo "======================================"
echo "✅ FRP Instalado!"
echo "======================================"
echo "IP: $(curl -s ifconfig.me)"
echo "Dashboard: http://$(curl -s ifconfig.me):7500"
echo "User: admin | Pass: adb2024admin"
echo ""
echo "📋 Portas Configuradas:"
echo "  - FRP Control: 7000"
echo "  - FRP Dashboard: 7500"
echo "  - WS-SCRCPY Web: 8000"
echo "  - WS-SCRCPY WebSocket: 8001"
echo "  - WS-SCRCPY API: 8002"
echo "  - Device Streams: 8886-8899"
echo "  - ADB Server: 5037"
echo "  - Additional: 7100, 7200"
echo "======================================"
