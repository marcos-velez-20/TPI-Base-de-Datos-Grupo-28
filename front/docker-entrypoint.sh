#!/bin/sh
# nginx ejecuta este script al arrancar (carpeta /docker-entrypoint.d).
# Genera config.js con la URL de la API que usará el NAVEGADOR.
set -e
API_URL="${API_URL:-http://localhost:8000}"
cat > /usr/share/nginx/html/config.js <<CONF
window.__CONFIG__ = { API_URL: "${API_URL}" };
CONF
echo "config.js generado con API_URL=${API_URL}"
