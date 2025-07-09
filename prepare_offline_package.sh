#!/bin/bash

set -e
OFFLINE_DIR="offline_security_tools"
BIN_DIR="$OFFLINE_DIR/bin"
TOOLS_DIR="$OFFLINE_DIR/tools"
PKG_DIR="$OFFLINE_DIR/packages"

echo "[*] Creando estructura de directorios..."
mkdir -p "$BIN_DIR" "$TOOLS_DIR" "$PKG_DIR"

echo "[*] Descargando herramientas portables y scripts..."

# Lynis
git clone https://github.com/CISOfy/lynis.git "$TOOLS_DIR/lynis"

# LinPEAS
curl -L -o "$TOOLS_DIR/linpeas.sh" https://github.com/carlospolop/PEASS-ng/releases/latest/download/linpeas.sh
chmod +x "$TOOLS_DIR/linpeas.sh"

# OpenSCAP profile (ajustar según tu sistema)
curl -L -o "$TOOLS_DIR/ssg-ubuntu2204-ds.xml" https://github.com/ComplianceAsCode/content/releases/latest/download/ssg-ubuntu2204-ds.xml

echo "[*] Descargando binarios necesarios y dependencias..."

# Lista de paquetes
PACKAGES=(
  chkrootkit
  rkhunter
  debsecan
  osquery
  aide
  tiger
  auditd
  trivy
)

# Descargar .deb + dependencias (Ubuntu/Debian)
for pkg in "${PACKAGES[@]}"; do
  echo "[+] Descargando $pkg y sus dependencias..."
  apt download "$pkg" -y -o=dir::cache="$PKG_DIR" 2>/dev/null || echo "   [!] Falló $pkg (puede que no exista en este sistema)"
done

# Clair-scanner binario (ejemplo sencillo)
curl -L -o "$TOOLS_DIR/clair-scanner" https://github.com/arminc/clair-scanner/releases/latest/download/clair-scanner_linux_amd64
chmod +x "$TOOLS_DIR/clair-scanner"

# Copiar binarios instalados al directorio bin
for cmd in osqueryi trivy aide debsecan rkhunter chkrootkit tiger lynx bastille ausearch; do
  if command -v "$cmd" &> /dev/null; then
    cp "$(command -v $cmd)" "$BIN_DIR/" || echo "   [!] No se pudo copiar $cmd"
  fi
done

# Copiar configuración de AIDE
if [[ -f /etc/aide/aide.conf ]]; then
  echo "[*] Copiando configuración de AIDE..."
  cp /etc/aide/aide.conf "$TOOLS_DIR/aide.conf"
else
  echo "[!] No se encontró /etc/aide/aide.conf"
fi

# Guardar script de instalación
cat > "$OFFLINE_DIR/install.sh" << 'EOF'
#!/bin/bash
set -e
echo "[*] Instalando paquetes locales..."
sudo dpkg -i packages/*.deb 2>/dev/null || true
echo "[*] Herramientas listas. Puedes ejecutarlas con run_all.sh"
EOF

chmod +x "$OFFLINE_DIR/install.sh"

# Guardar script de ejecución
cat > "$OFFLINE_DIR/run_all.sh" << 'EOF'
#!/bin/bash

set -e
OUTPUT_DIR="./output"
mkdir -p "$OUTPUT_DIR"

declare -A TOOLS=(
  [Lynis]="tools/lynis/lynis audit system --quick --quiet --logfile \$OUTPUT_DIR/lynis.log"
  [Chkrootkit]="bin/chkrootkit > \$OUTPUT_DIR/chkrootkit.log"
  [RKHunter]="bin/rkhunter --check --skip-keypress > \$OUTPUT_DIR/rkhunter.log"
  [Debsecan]="bin/debsecan > \$OUTPUT_DIR/debsecan.log"
  [Osquery]="bin/osqueryi --json 'SELECT name,path,pid,uid FROM processes LIMIT 10;' > \$OUTPUT_DIR/osquery.json"
  [AIDE]="bin/aide --check --config tools/aide.conf > \$OUTPUT_DIR/aide.log"
  [LinPEAS]="tools/linpeas.sh -a > \$OUTPUT_DIR/linpeas.log"
  [Tiger]="bin/tiger -H > \$OUTPUT_DIR/tiger.log"
  [OpenSCAP]="oscap xccdf eval --report \$OUTPUT_DIR/openscap.html --profile xccdf_org.ssgproject.content_profile_standard --results-arf \$OUTPUT_DIR/arf.xml tools/ssg-ubuntu2204-ds.xml"
  [Trivy]="bin/trivy fs / --format json > \$OUTPUT_DIR/trivy.json"
  [Auditd]="bin/ausearch -x /usr/bin/sudo > \$OUTPUT_DIR/auditd.log"
  [Bastille]="bin/bastille -c > \$OUTPUT_DIR/bastille.log"
)

for tool in "${!TOOLS[@]}"; do
  echo -e "\n\e[1;36m[*] Ejecutando $tool...\e[0m"
  eval "${TOOLS[$tool]}"
done

echo -e "\n\e[1;32m[✔] Auditoría completa. Resultados en \$OUTPUT_DIR\e[0m"
EOF

chmod +x "$OFFLINE_DIR/run_all.sh"

# Crear HTML bonito (opcional, puedes integrarlo luego)
cat > "$OFFLINE_DIR/generate_report.sh" << 'EOF'
#!/bin/bash

OUTPUT_DIR="./output"
REPORT="$OUTPUT_DIR/report.html"

echo "[*] Generando informe HTML completo..."

# Cabecera HTML con estilo
cat << 'EOF' > "$REPORT"
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <title>Informe de Auditoría de Seguridad</title>
  <style>
    body { font-family: sans-serif; background: #f9f9f9; color: #333; padding: 20px; }
    h1 { color: #005b96; }
    h2 { color: #003f5c; }
    pre { background: #f0f0f0; padding: 10px; border-left: 4px solid #005b96; overflow-x: auto; }
    .section { margin-bottom: 30px; }
    summary { font-weight: bold; cursor: pointer; color: #003f5c; }
    .index a { text-decoration: none; color: #0077cc; }
    .index li { margin-bottom: 5px; }
    .footer { margin-top: 40px; font-size: 0.9em; color: #777; }
  </style>
</head>
<body>
  <h1>🛡️ Informe de Auditoría de Seguridad</h1>
  <p>Este informe resume la salida de todas las herramientas ejecutadas.</p>

  <h2>📋 Índice de herramientas</h2>
  <ul class="index">
EOF

# Índice dinámico
for file in "$OUTPUT_DIR"/*; do
  [ -f "$file" ] || continue
  name=$(basename "$file")
  anchor_id=$(echo "$name" | sed 's/[^a-zA-Z0-9]/_/g')
  echo "    <li><a href=\"#$anchor_id\">$name</a></li>" >> "$REPORT"
done

# Inicio del cuerpo
echo "  </ul><hr>" >> "$REPORT"

# Cuerpo con secciones por archivo
for file in "$OUTPUT_DIR"/*; do
  [ -f "$file" ] || continue
  name=$(basename "$file")
  anchor_id=$(echo "$name" | sed 's/[^a-zA-Z0-9]/_/g')

  echo "<div class=\"section\" id=\"$anchor_id\">" >> "$REPORT"
  echo "<details open><summary>📄 $name</summary><br>" >> "$REPORT"

  # Detecta si es HTML y lo embebe
  if [[ "$file" == *.html ]]; then
    echo "<iframe src=\"$name\" width=\"100%\" height=\"600px\" style=\"border:1px solid #ccc;\"></iframe>" >> "$REPORT"
  else
    echo "<pre>" >> "$REPORT"
    cat "$file" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' >> "$REPORT"
    echo "</pre>" >> "$REPORT"
  fi

  echo "</details></div>" >> "$REPORT"
done

# Pie de página
cat << 'EOF' >> "$REPORT"
  <div class="footer">
    Generado automáticamente el <strong>$(date)</strong>.
  </div>
</body>
</html>
EOF

echo "[✔] Informe generado en $REPORT"

chmod +x "$OFFLINE_DIR/generate_report.sh"

# Crear el paquete final
echo "[*] Empaquetando todo..."
tar -czvf offline_security_tools.tar.gz "$OFFLINE_DIR"

echo -e "\n\e[1;32m[✔] Paquete creado: offline_security_tools.tar.gz\e[0m"
