#!/bin/bash

# Script atualizado para configurar servidor com endpoint de upload
# Execute como root ou com sudo

echo "=== Configurando Servidor de Atualizações com Upload ==="

# Atualizar sistema
apt update && apt upgrade -y

# Instalar Node.js se não estiver instalado
if ! command -v node &> /dev/null; then
    echo "Instalando Node.js..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt install -y nodejs
fi

# Instalar PM2 para gerenciar o processo Node.js
if ! command -v pm2 &> /dev/null; then
    echo "Instalando PM2..."
    npm install -g pm2
fi

# Instalar Nginx se não estiver instalado
if ! command -v nginx &> /dev/null; then
    echo "Instalando Nginx..."
    apt install nginx -y
fi

# Criar diretório para as atualizações
UPDATE_DIR="/var/www/electron-updates"
mkdir -p $UPDATE_DIR
chmod 755 $UPDATE_DIR

# Criar diretório para o servidor de upload
SERVER_DIR="/opt/electron-update-server"
mkdir -p $SERVER_DIR

# Copiar arquivo do servidor
cp server-upload-endpoint.js $SERVER_DIR/

# Criar package.json para o servidor
cat > $SERVER_DIR/package.json << 'EOF'
{
  "name": "electron-update-server",
  "version": "1.0.0",
  "main": "server-upload-endpoint.js",
  "dependencies": {
    "express": "^4.18.2",
    "multer": "^1.4.5-lts.1"
  }
}
EOF

# Instalar dependências
cd $SERVER_DIR
npm install

# Gerar chave API aleatória
API_KEY=$(node -e "console.log(require('crypto').randomBytes(32).toString('hex'))")
echo "API_KEY=$API_KEY" > .env

# Atualizar o arquivo do servidor com a chave API
sed -i "s/SUA_CHAVE_API_AQUI/$API_KEY/g" server-upload-endpoint.js

# Configurar PM2 para iniciar o servidor
pm2 start server-upload-endpoint.js --name electron-update-server
pm2 save
pm2 startup

# Configurar Nginx como proxy reverso
NGINX_CONFIG="/etc/nginx/sites-available/electron-updates"
cat > $NGINX_CONFIG << 'EOF'
server {
    listen 80;
    server_name _;  # Substitua com seu domínio ou IP
    
    # Limite de tamanho de upload (500MB)
    client_max_body_size 500M;
    
    # Timeout para uploads grandes
    proxy_connect_timeout 300;
    proxy_send_timeout 300;
    proxy_read_timeout 300;
    send_timeout 300;
    
    # Diretório das atualizações (acesso direto)
    location /updates/ {
        alias /var/www/electron-updates/;
        autoindex off;
        
        # Permitir CORS
        add_header Access-Control-Allow-Origin *;
        add_header Access-Control-Allow-Methods "GET, OPTIONS";
        add_header Access-Control-Allow-Headers "Origin, X-Requested-With, Content-Type, Accept";
        
        # Cache para arquivos estáticos
        location ~* \.(exe|dmg|AppImage|deb|rpm|yml|yaml|json)$ {
            expires 1h;
            add_header Cache-Control "public, immutable";
        }
    }
    
    # Proxy para o servidor de upload Node.js
    location /upload {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    # Health check
    location /health {
        proxy_pass http://localhost:3000;
    }
    
    # Listar arquivos (protegido)
    location /files {
        proxy_pass http://localhost:3000;
    }
}
EOF

# Ativar configuração
ln -sf $NGINX_CONFIG /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Testar configuração do Nginx
nginx -t

# Reiniciar Nginx
systemctl restart nginx
systemctl enable nginx

# Configurar firewall se UFW estiver ativo
if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
    ufw allow 'Nginx Full'
    ufw allow 3000/tcp
fi

echo ""
echo "=== Configuração Concluída ==="
echo ""
echo "Servidor de atualizações configurado!"
echo ""
echo "IMPORTANTE - Anote estas informações:"
echo "======================================"
echo "URL do servidor: http://SEU_IP/"
echo "Endpoint de upload: http://SEU_IP/upload"
echo "Diretório de atualizações: $UPDATE_DIR"
echo ""
echo "CHAVE API: $API_KEY"
echo ""
echo "======================================"
echo ""
echo "Use esta chave API no aplicativo de upload!"
echo "Guarde esta chave em local seguro!"
echo ""
echo "Para verificar o status do servidor:"
echo "  pm2 status"
echo "  pm2 logs electron-update-server"