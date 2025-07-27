#!/bin/bash

# Script para corrigir/instalar servidor de upload no Digital Ocean
# Execute como root: ./fix-server.sh

echo "=== Corrigindo Servidor de Upload Electron ==="
echo "IP: 157.245.116.170"
echo ""

# 1. Criar estrutura de diretórios
echo "1. Criando diretórios..."
mkdir -p /opt/electron-update-server
mkdir -p /var/www/electron-updates
chmod 755 /var/www/electron-updates

# 2. Navegar para o diretório do servidor
cd /opt/electron-update-server

# 3. Criar package.json
echo "2. Criando package.json..."
cat > package.json << 'EOF'
{
  "name": "electron-update-server",
  "version": "1.0.0",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "multer": "^1.4.5-lts.1"
  }
}
EOF

# 4. Instalar dependências
echo "3. Instalando dependências..."
npm install

# 5. Criar servidor com configurações específicas
echo "4. Criando servidor.js..."
cat > server.js << 'EOF'
const express = require('express');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const crypto = require('crypto');

const app = express();
const PORT = 3000;

// Configurações específicas do servidor
const UPDATE_DIR = '/var/www/electron-updates';
const API_KEY = '223792c1af497b87e8a949d85ea275296a030003204f4226a0324800aafbe4c8';

// Criar diretório se não existir
if (!fs.existsSync(UPDATE_DIR)) {
  fs.mkdirSync(UPDATE_DIR, { recursive: true });
  console.log('Diretório de updates criado:', UPDATE_DIR);
}

// Configurar multer para upload
const storage = multer.diskStorage({
  destination: function (req, file, cb) {
    cb(null, UPDATE_DIR);
  },
  filename: function (req, file, cb) {
    cb(null, file.originalname);
  }
});

const upload = multer({ 
  storage: storage,
  limits: {
    fileSize: 500 * 1024 * 1024 // 500MB
  },
  fileFilter: function (req, file, cb) {
    const allowedExtensions = ['.exe', '.dmg', '.AppImage', '.deb', '.rpm', '.yml', '.yaml'];
    const ext = path.extname(file.originalname).toLowerCase();
    
    if (allowedExtensions.includes(ext)) {
      cb(null, true);
    } else {
      cb(new Error('Tipo de arquivo não permitido: ' + ext));
    }
  }
});

// Middleware para verificar API key
function verifyApiKey(req, res, next) {
  const providedKey = req.headers['x-api-key'] || req.body.apiKey;
  
  if (!providedKey || providedKey !== API_KEY) {
    console.log('Tentativa com chave inválida:', providedKey);
    return res.status(401).json({ error: 'Chave API inválida' });
  }
  
  next();
}

// CORS
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.header('Access-Control-Allow-Headers', 'Origin, X-Requested-With, Content-Type, Accept, X-API-Key');
  
  if (req.method === 'OPTIONS') {
    return res.sendStatus(200);
  }
  
  next();
});

// Endpoint de upload
app.post('/upload', verifyApiKey, upload.single('file'), (req, res) => {
  if (!req.file) {
    return res.status(400).json({ error: 'Nenhum arquivo enviado' });
  }
  
  console.log(`[${new Date().toISOString()}] Upload recebido: ${req.file.originalname} (${req.file.size} bytes)`);
  
  // Ajustar permissões
  fs.chmod(req.file.path, '644', (err) => {
    if (err) {
      console.error('Erro ao ajustar permissões:', err);
    }
  });
  
  res.json({ 
    message: 'Upload concluído com sucesso',
    file: req.file.originalname,
    size: req.file.size
  });
});

// Health check
app.get('/health', (req, res) => {
  res.json({ 
    status: 'OK',
    server: '157.245.116.170',
    updateDir: UPDATE_DIR,
    time: new Date().toISOString()
  });
});

// Listar arquivos (protegido)
app.get('/files', verifyApiKey, (req, res) => {
  fs.readdir(UPDATE_DIR, (err, files) => {
    if (err) {
      console.error('Erro ao listar arquivos:', err);
      return res.status(500).json({ error: 'Erro ao listar arquivos' });
    }
    
    const fileDetails = files.map(file => {
      try {
        const stats = fs.statSync(path.join(UPDATE_DIR, file));
        return {
          name: file,
          size: stats.size,
          modified: stats.mtime
        };
      } catch (e) {
        return { name: file, error: 'Não foi possível obter detalhes' };
      }
    });
    
    res.json({ 
      total: files.length,
      files: fileDetails 
    });
  });
});

// Tratamento de erros
app.use((error, req, res, next) => {
  console.error('Erro:', error);
  
  if (error instanceof multer.MulterError) {
    if (error.code === 'LIMIT_FILE_SIZE') {
      return res.status(400).json({ error: 'Arquivo muito grande (limite: 500MB)' });
    }
  }
  
  res.status(500).json({ error: error.message });
});

// Iniciar servidor
app.listen(PORT, '0.0.0.0', () => {
  console.log(`=== Servidor de Upload Electron ===`);
  console.log(`Rodando na porta: ${PORT}`);
  console.log(`Diretório de updates: ${UPDATE_DIR}`);
  console.log(`API configurada para: 157.245.116.170`);
  console.log(`Iniciado em: ${new Date().toISOString()}`);
});
EOF

# 6. Parar servidor anterior se existir
echo "5. Parando servidor anterior..."
pm2 delete electron-update-server 2>/dev/null || true

# 7. Iniciar servidor com PM2
echo "6. Iniciando servidor com PM2..."
pm2 start server.js --name electron-update-server
pm2 save
pm2 startup systemd -u root --hp /root

# 8. Configurar Nginx
echo "7. Configurando Nginx..."
cat > /etc/nginx/sites-available/electron-updates << 'EOF'
server {
    listen 80;
    server_name 157.245.116.170;
    
    # Limite de upload
    client_max_body_size 500M;
    client_body_buffer_size 128k;
    client_body_timeout 300;
    proxy_connect_timeout 300;
    proxy_send_timeout 300;
    proxy_read_timeout 300;
    send_timeout 300;
    
    # Servir arquivos de atualização
    location /updates/ {
        alias /var/www/electron-updates/;
        autoindex off;
        
        # CORS
        add_header Access-Control-Allow-Origin *;
        add_header Access-Control-Allow-Methods "GET, OPTIONS";
        add_header Access-Control-Allow-Headers "Origin, X-Requested-With, Content-Type, Accept";
        
        # Cache
        location ~* \.(exe|dmg|AppImage|deb|rpm|yml|yaml|json)$ {
            expires 1h;
            add_header Cache-Control "public, immutable";
        }
    }
    
    # Proxy para upload
    location /upload {
        proxy_pass http://localhost:3000/upload;
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
        proxy_pass http://localhost:3000/health;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
    }
    
    # Listar arquivos
    location /files {
        proxy_pass http://localhost:3000/files;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
    }
}
EOF

# 9. Ativar site no Nginx
echo "8. Ativando configuração Nginx..."
ln -sf /etc/nginx/sites-available/electron-updates /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# 10. Testar e reiniciar Nginx
nginx -t
if [ $? -eq 0 ]; then
    systemctl restart nginx
    echo "✓ Nginx reiniciado com sucesso"
else
    echo "✗ Erro na configuração do Nginx"
    exit 1
fi

# 11. Mostrar status
echo ""
echo "=== Status do Servidor ==="
pm2 status

# 12. Testar endpoints
echo ""
echo "=== Testando Endpoints ==="
echo "Testando health check..."
curl -s http://localhost:3000/health | json_pp 2>/dev/null || curl -s http://localhost:3000/health

echo ""
echo ""
echo "=== Servidor Configurado com Sucesso! ==="
echo ""
echo "Informações do servidor:"
echo "------------------------"
echo "URL Base: http://157.245.116.170/"
echo "Upload: http://157.245.116.170/upload"
echo "Downloads: http://157.245.116.170/updates/"
echo "Health: http://157.245.116.170/health"
echo "API Key: 223792c1af497b87e8a949d85ea275296a030003204f4226a0324800aafbe4c8"
echo ""
echo "Comandos úteis:"
echo "- Ver logs: pm2 logs electron-update-server"
echo "- Reiniciar: pm2 restart electron-update-server"
echo "- Status: pm2 status"
echo ""
echo "Teste de upload via curl:"
echo "curl -X POST -H \"X-API-Key: 223792c1af497b87e8a949d85ea275296a030003204f4226a0324800aafbe4c8\" -F \"file=@arquivo.yml\" http://157.245.116.170/upload"