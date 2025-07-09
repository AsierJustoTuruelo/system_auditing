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
  lynx
  auditd
  bastille
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

echo "[*] Copiando ejecutables estáticos si existen..."

# Buscar binarios instalados y copiarlos al directorio /bin
for cmd in osqueryi trivy aide debsecan rkhunter chkrootkit tiger lynx bastille ausearch; do
  if command -v "$cmd" &> /dev/null; then
    cp "$(command -v $cmd)" "$BIN_DIR/" || echo "   [!] No se pudo copiar $cmd"
  fi
done

echo "[*] Copia de binarios completa."

# Guardar scripts de instalación y ejecución
cat > "$OFFLINE_DIR/install.sh" << 'EOF'
#!/bin/bash
set -e
echo "[*] Instalando paquetes locales..."
sudo dpkg -i packages/*.deb 2>/dev/null || true
echo "[*] Herramientas listas. Puedes ejecutarlas con run_all.sh"
EOF

chmod +x "$OFFLINE_DIR/install.sh"

cat > "$OFFLINE_DIR/run_all.sh" << 'EOF'
#!/bin/bash

OUTPUT_DIR="./output"
mkdir -p "$OUTPUT_DIR"

declare -A TOOLS=(
  [Lynis]="tools/lynis/lynis audit system --quick --quiet --logfile \$OUTPUT_DIR/lynis.log"
  [Chkrootkit]="bin/chkrootkit > \$OUTPUT_DIR/chkrootkit.log"
  [RKHunter]="bin/rkhunter --check --skip-keypress > \$OUTPUT_DIR/rkhunter.log"
  [Debsecan]="bin/debsecan > \$OUTPUT_DIR/debsecan.log"
  [Osquery]="bin/osqueryi --json 'SELECT name,path,pid,uid FROM processes LIMIT 10;' > \$OUTPUT_DIR/osquery.json"
  [AIDE]="bin/aide --check > \$OUTPUT_DIR/aide.log"
  [LinPEAS]="tools/linpeas.sh -a > \$OUTPUT_DIR/linpeas.log"
  [Tiger]="bin/tiger -H > \$OUTPUT_DIR/tiger.log"
  [OpenSCAP]="oscap xccdf eval --report \$OUTPUT_DIR/openscap.html --profile xccdf_org.ssgproject.content_profile_standard --results-arf \$OUTPUT_DIR/arf.xml tools/ssg-ubuntu2204-ds.xml"
  [Clair]="tools/clair-scanner some_image > \$OUTPUT_DIR/clair.log 2>&1"
  [Trivy]="bin/trivy fs / --format json > \$OUTPUT_DIR/trivy.json"
  [Lynx]="bin/lynx -dump https://example.com > \$OUTPUT_DIR/lynx.txt"
  [Auditd]="bin/ausearch -x /usr/bin/sudo > \$OUTPUT_DIR/auditd.log"
  [Bastille]="bin/bastille -c > \$OUTPUT_DIR/bastille.log"
)

for tool in "${!TOOLS[@]}"; do
  echo "[*] Ejecutando $tool..."
  eval "${TOOLS[$tool]}"
done

echo "[*] Auditoría completa. Resultados en \$OUTPUT_DIR"
EOF

chmod +x "$OFFLINE_DIR/run_all.sh"

echo "[*] Empaquetando todo para transferencia..."
tar -czvf offline_security_tools.tar.gz "$OFFLINE_DIR"

echo "[✔] Paquete creado: offline_security_tools.tar.gz"
