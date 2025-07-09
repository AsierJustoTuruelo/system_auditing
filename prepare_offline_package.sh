#!/bin/bash

set -e

BASE_DIR="$(pwd)"
BIN_DIR="$BASE_DIR/bin"
OUTPUT_DIR="$BASE_DIR/output"
PACKAGE_NAME="offline_security_tools"
TAR_FILE="$PACKAGE_NAME.tar.gz"

mkdir -p "$BIN_DIR" "$OUTPUT_DIR"

echo "[*] Descargando herramientas..."

# Tiger (requiere instalación desde .deb)
echo " - Descargando tiger..."
apt download tiger -y >/dev/null 2>&1 || echo "Tiger no pudo descargarse, revisa repositorios habilitados."
mv tiger_*.deb "$BIN_DIR" 2>/dev/null || echo "⚠️ Tiger .deb no encontrado tras descarga."

# RKHunter
echo " - Descargando rkhunter..."
apt download rkhunter -y >/dev/null 2>&1 || echo "RKHunter no pudo descargarse."
mv rkhunter_*.deb "$BIN_DIR" 2>/dev/null || echo "⚠️ RKHunter .deb no encontrado tras descarga."

# AIDE
echo " - Descargando AIDE..."
apt download aide aide-common -y >/dev/null 2>&1 || echo "AIDE no pudo descargarse."
mv aide*.deb "$BIN_DIR" 2>/dev/null || echo "⚠️ AIDE .deb no encontrado tras descarga."

# Nmap
echo " - Descargando nmap..."
apt download nmap -y >/dev/null 2>&1 || echo "Nmap no pudo descargarse."
mv nmap_*.deb "$BIN_DIR" 2>/dev/null || echo "⚠️ Nmap .deb no encontrado tras descarga."

# Lynx
echo " - Descargando lynx..."
apt download lynx -y >/dev/null 2>&1 || echo "Lynx no pudo descargarse."
mv lynx_*.deb "$BIN_DIR" 2>/dev/null || echo "⚠️ Lynx .deb no encontrado tras descarga."

# Trivy (directo desde GitHub)
echo " - Descargando Trivy..."
TRIVY_URL=$(curl -s https://api.github.com/repos/aquasecurity/trivy/releases/latest | grep browser_download_url | grep 'trivy_.*Linux-64bit.tar.gz' | cut -d '"' -f 4)
wget -q "$TRIVY_URL" -O trivy.tar.gz
tar -xzf trivy.tar.gz
mv trivy "$BIN_DIR/"
rm -rf trivy.tar.gz LICENSE README.md

# Lynis
echo " - Descargando Lynis..."
wget -q https://downloads.cisofy.com/lynis/lynis-3.0.9.tar.gz -O lynis.tar.gz
tar -xzf lynis.tar.gz
mv lynis "$BIN_DIR/"
rm lynis.tar.gz

# OpenSCAP
echo " - Descargando oscap scanner..."
apt download libopenscap8 -y >/dev/null 2>&1 || echo "OpenSCAP no pudo descargarse."
mv libopenscap*.deb "$BIN_DIR" 2>/dev/null || echo "⚠️ OpenSCAP .deb no encontrado tras descarga."

# Scripts personalizados
echo " - Copiando scripts de ejecución..."
cat > "$BASE_DIR/run_all.sh" << 'EOF'
#!/bin/bash
set -e
OUTPUT_DIR="./output"
mkdir -p "$OUTPUT_DIR"

echo "[*] Ejecutando Tiger..."
dpkg -x bin/tiger_*.deb ./tmp && ./tmp/usr/sbin/tiger > "$OUTPUT_DIR/tiger.log" 2>&1 || echo "⚠️ Tiger falló."

echo "[*] Ejecutando RKHunter..."
dpkg -x bin/rkhunter_*.deb ./tmp && ./tmp/usr/bin/rkhunter --check --sk --nocolors > "$OUTPUT_DIR/rkhunter.log" 2>&1 || echo "⚠️ RKHunter falló."

echo "[*] Ejecutando AIDE..."
dpkg -x bin/aide_*.deb ./tmp
dpkg -x bin/aide-common_*.deb ./tmp
./tmp/usr/bin/aide --init > "$OUTPUT_DIR/aide.log" 2>&1 || echo "⚠️ AIDE falló."

echo "[*] Ejecutando Lynis..."
./bin/lynis/lynis audit system > "$OUTPUT_DIR/lynis.txt" 2>&1 || echo "⚠️ Lynis falló."

echo "[*] Ejecutando Nmap..."
./bin/nmap -sV -oN "$OUTPUT_DIR/nmap.log" 127.0.0.1 || echo "⚠️ Nmap falló."

echo "[*] Ejecutando Lynx..."
./bin/lynx -dump https://example.com > "$OUTPUT_DIR/lynx.txt" || echo "⚠️ Lynx falló."

echo "[*] Ejecutando Trivy..."
./bin/trivy fs --quiet --severity HIGH,CRITICAL --output "$OUTPUT_DIR/trivy.txt" ./ || echo "⚠️ Trivy falló."

echo "[*] Ejecutando OpenSCAP..."
dpkg -x bin/libopenscap*.deb ./tmp
./tmp/usr/bin/oscap xccdf eval --profile xccdf_org.ssgproject.content_profile_standard --results "$OUTPUT_DIR/openscap-results.xml" /usr/share/openscap/scap-yast2sec-xccdf.xml || echo "⚠️ OpenSCAP falló."

echo "[✔] Todas las herramientas ejecutadas."
EOF

chmod +x "$BASE_DIR/run_all.sh"

# Report generator
cat > "$BASE_DIR/generate_report.sh" << 'EOF'
#!/bin/bash
OUTPUT_DIR="./output"
REPORT="$OUTPUT_DIR/report.html"
mkdir -p "$OUTPUT_DIR"

echo "[*] Generando informe HTML completo..."

cat << 'HTML' > "$REPORT"
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <title>Informe de Auditoría</title>
  <style>
    body { font-family: Arial; padding: 20px; background: #f0f0f0; }
    h1 { color: #005b96; }
    summary { font-weight: bold; cursor: pointer; margin-top: 10px; }
    pre { background: #fff; padding: 10px; border: 1px solid #ccc; overflow-x: auto; }
  </style>
</head>
<body>
  <h1>🛡 Informe de Auditoría de Seguridad</h1>
  <ul>
HTML

for file in "$OUTPUT_DIR"/*; do
  name=$(basename "$file")
  id=$(echo "$name" | tr -c '[:alnum:]' '_')
  echo "<li><a href=\"#$id\">$name</a></li>" >> "$REPORT"
done

echo "</ul><hr>" >> "$REPORT"

for file in "$OUTPUT_DIR"/*; do
  name=$(basename "$file")
  id=$(echo "$name" | tr -c '[:alnum:]' '_')
  echo "<details id=\"$id\"><summary>$name</summary><pre>" >> "$REPORT"
  cat "$file" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' >> "$REPORT"
  echo "</pre></details>" >> "$REPORT"
done

echo "</body></html>" >> "$REPORT"

echo "[✔] Informe generado: $REPORT"
EOF

chmod +x "$BASE_DIR/generate_report.sh"

# Crear archivo tar final
echo "[*] Empaquetando..."
tar -czf "$TAR_FILE" bin run_all.sh generate_report.sh output/

echo "[✔] Paquete creado: $TAR_FILE"
