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

# OpenSCAP Profile (ajustar si usas otra distro)
curl -L -o "$TOOLS_DIR/ssg-ubuntu2204-ds.xml" https://github.com/ComplianceAsCode/content/releases/latest/download/ssg-ubuntu2204-ds.xml

# Clair Scanner (versión estática)
curl -L -o "$TOOLS_DIR/clair-scanner" https://github.com/arminc/clair-scanner/releases/latest/download/clair-scanner_linux_amd64
chmod +x "$TOOLS_DIR/clair-scanner"

echo "[*] Descargando paquetes .deb y dependencias..."

PACKAGES=(
  chkrootkit
  rkhunter
  debsecan
  aide
  tiger
  lynx
  auditd
  bastille
  trivy
)

for pkg in "${PACKAGES[@]}"; do
  echo "[+] Descargando $pkg..."
  apt download "$pkg" -o=dir::cache="$PKG_DIR" 2>/dev/null || echo "   [!] Falló $pkg (puede que no esté disponible)"
done

echo "[*] Copiando ejecutables del sistema si están instalados..."

for cmd in osqueryi trivy aide debsecan rkhunter chkrootkit tiger lynx bastille ausearch; do
  if command -v "$cmd" &> /dev/null; then
    cp "$(command -v $cmd)" "$BIN_DIR/" || echo "   [!] No se pudo copiar $cmd"
  fi
done

echo "[*] Guardando scripts de instalación y ejecución..."

# install.sh
cat > "$OFFLINE_DIR/install.sh" << 'EOF'
#!/bin/bash
set -e
echo "[*] Instalando paquetes locales..."
sudo dpkg -i packages/*.deb 2>/dev/null || true
echo "[*] Instalación completa. Ejecuta ./run_all.sh para iniciar la auditoría."
EOF
chmod +x "$OFFLINE_DIR/install.sh"

# run_all.sh
cat > "$OFFLINE_DIR/run_all.sh" << 'EOF'
#!/bin/bash

set -e
OUTPUT_DIR="./output"
HTML_REPORT="$OUTPUT_DIR/report.html"
mkdir -p "$OUTPUT_DIR"

GREEN="\033[0;32m"
RED="\033[0;31m"
NC="\033[0m"

declare -A TOOLS=(
  [Lynis]="tools/lynis/lynis audit system --quick --quiet --logfile \$OUTPUT_DIR/lynis.log"
  [Chkrootkit]="bin/chkrootkit > \$OUTPUT_DIR/chkrootkit.log"
  [RKHunter]="bin/rkhunter --check --skip-keypress > \$OUTPUT_DIR/rkhunter.log"
  [Debsecan]="bin/debsecan > \$OUTPUT_DIR/debsecan.log"
  [AIDE]="bin/aide --check > \$OUTPUT_DIR/aide.log"
  [LinPEAS]="tools/linpeas.sh -a > \$OUTPUT_DIR/linpeas.log"
  [Tiger]="bin/tiger -H > \$OUTPUT_DIR/tiger.log"
  [OpenSCAP]="oscap xccdf eval --report \$OUTPUT_DIR/openscap.html --profile xccdf_org.ssgproject.content_profile_standard --results-arf \$OUTPUT_DIR/arf.xml tools/ssg-ubuntu2204-ds.xml"
  [Trivy]="bin/trivy fs / --format json > \$OUTPUT_DIR/trivy.json"
  [Auditd]="bin/ausearch -x /usr/bin/sudo > \$OUTPUT_DIR/auditd.log"
  [Bastille]="bin/bastille -c > \$OUTPUT_DIR/bastille.log"
)

echo "<html><head><title>Informe de Seguridad</title><style>
body { font-family: Arial; background-color: #f4f4f4; padding: 20px; }
h2 { background-color: #003366; color: white; padding: 10px; }
pre { background-color: #ffffff; padding: 10px; border-left: 5px solid #003366; overflow-x: auto; }
</style></head><body><h1>Informe de Seguridad</h1>" > "$HTML_REPORT"

for tool in "${!TOOLS[@]}"; do
  echo -e "[*] Ejecutando ${GREEN}$tool${NC}..."
  eval "${TOOLS[$tool]}" || echo -e "${RED}[!] Error al ejecutar $tool${NC}"
  
  FILE=$(echo "${TOOLS[$tool]}" | grep -oE '> \$OUTPUT_DIR/[^ ]+' | awk -F '/' '{print $NF}')
  FILE_PATH="$OUTPUT_DIR/${FILE}"

  if [[ -f "$FILE_PATH" ]]; then
    echo "<h2>$tool</h2><pre>" >> "$HTML_REPORT"
    head -n 100 "$FILE_PATH" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' >> "$HTML_REPORT"
    echo "</pre>" >> "$HTML_REPORT"
  fi
done

echo "<p><strong>Informe generado el:</strong> $(date)</p></body></html>" >> "$HTML_REPORT"

echo -e "\n${GREEN}[✔] Auditoría completa. Resultados guardados en '$OUTPUT_DIR'.${NC}"
echo -e "${GREEN}[✔] Reporte HTML generado: '$HTML_REPORT'${NC}"
EOF
chmod +x "$OFFLINE_DIR/run_all.sh"

echo "[*] Empaquetando para transferencia..."
tar -czf offline_security_tools.tar.gz "$OFFLINE_DIR"

echo "[✔] Paquete offline preparado: offline_security_tools.tar.gz"
