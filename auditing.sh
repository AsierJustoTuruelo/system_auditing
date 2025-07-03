#!/bin/bash

OUTPUT_DIR="./report_output"
REPORT_HTML="$OUTPUT_DIR/final_report.html"
mkdir -p "$OUTPUT_DIR"

# --- Ejecutar herramientas y guardar logs ---
echo "[*] Ejecutando herramientas..."

declare -A TOOLS=(
  [Lynis]="lynis audit system --quick --quiet --logfile $OUTPUT_DIR/lynis.log"
  [Chkrootkit]="chkrootkit > $OUTPUT_DIR/chkrootkit.log"
  [RKHunter]="rkhunter --check --skip-keypress > $OUTPUT_DIR/rkhunter.log"
  [Debsecan]="debsecan > $OUTPUT_DIR/debsecan.log"
  [Osquery]="osqueryi --json \"SELECT name,path,pid,uid FROM processes LIMIT 10;\" > $OUTPUT_DIR/osquery.json"
  [AIDE]="aide --check > $OUTPUT_DIR/aide.log"
  [LinPEAS]="./linpeas.sh -a > $OUTPUT_DIR/linpeas.log"
  [Tiger]="tiger -H > $OUTPUT_DIR/tiger.log"
  [OpenSCAP]="oscap xccdf eval --report $OUTPUT_DIR/openscap.html --profile xccdf_org.ssgproject.content_profile_standard --results-arf $OUTPUT_DIR/arf.xml /usr/share/xml/scap/ssg/content/ssg-ubuntu2204-ds.xml"
  [Clair]="clair-scanner some_image > $OUTPUT_DIR/clair.log 2>&1"
  [Trivy]="trivy fs / --format json > $OUTPUT_DIR/trivy.json"
  [Lynx]="lynx -dump https://example.com > $OUTPUT_DIR/lynx.txt"
  [Auditd]="ausearch -x /usr/bin/sudo > $OUTPUT_DIR/auditd.log"
  [Bastille]="bastille -c > $OUTPUT_DIR/bastille.log"
)

for tool in "${!TOOLS[@]}"; do
  echo "[+] $tool"
  eval "${TOOLS[$tool]}"
done

# --- Generar reporte HTML ---
echo "[*] Generando reporte HTML..."

cat <<EOF > "$REPORT_HTML"
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <title>Informe de Auditoría de Seguridad</title>
  <style>
    body { font-family: Arial, sans-serif; background: #f4f4f4; padding: 2em; }
    h1 { color: #2c3e50; }
    h2 { color: #1a5276; }
    pre { background: #272822; color: #f8f8f2; padding: 1em; overflow-x: auto; border-radius: 6px; max-height: 400px; }
    section { background: white; margin-bottom: 30px; padding: 1em; border-radius: 8px; box-shadow: 0 0 10px rgba(0,0,0,0.1); }
    nav { position: fixed; top: 10px; right: 10px; background: #fff; border: 1px solid #ccc; padding: 1em; border-radius: 8px; max-height: 90vh; overflow-y: auto; }
    nav h3 { margin-top: 0; }
    nav a { display: block; margin: 5px 0; text-decoration: none; color: #2c3e50; }
    details summary { cursor: pointer; font-weight: bold; color: #154360; }
  </style>
</head>
<body>
  <h1>🔐 Informe de Auditoría de Seguridad</h1>

  <nav>
    <h3>📋 Índice</h3>
EOF

# Crear índice navegable
for tool in "${!TOOLS[@]}"; do
  anchor=$(echo "$tool" | tr '[:upper:]' '[:lower:]')
  echo "    <a href=\"#$anchor\">$tool</a>" >> "$REPORT_HTML"
done

echo "  </nav>" >> "$REPORT_HTML"

# Agregar secciones con resultados
for tool in "${!TOOLS[@]}"; do
  anchor=$(echo "$tool" | tr '[:upper:]' '[:lower:]')
  file_txt="$OUTPUT_DIR/${tool,,}.log"
  file_json="$OUTPUT_DIR/${tool,,}.json"
  file_html="$OUTPUT_DIR/${tool,,}.html"

  echo "<section id=\"$anchor\">" >> "$REPORT_HTML"
  echo "<h2>$tool</h2>" >> "$REPORT_HTML"

  if [[ -f "$file_txt" ]]; then
    echo "<details open><summary>Ver resultado</summary><pre>$(cat "$file_txt" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')</pre></details>" >> "$REPORT_HTML"
  elif [[ -f "$file_json" ]]; then
    echo "<details><summary>Ver JSON</summary><pre>$(jq . "$file_json" 2>/dev/null | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')</pre></details>" >> "$REPORT_HTML"
  elif [[ -f "$file_html" ]]; then
    echo "<details><summary>Ver HTML incrustado (iframe)</summary><iframe src=\"$file_html\" width=\"100%\" height=\"500\"></iframe></details>" >> "$REPORT_HTML"
  else
    echo "<p><em>⚠️ Resultado no disponible.</em></p>" >> "$REPORT_HTML"
  fi

  echo "</section>" >> "$REPORT_HTML"
done

# Cerrar HTML
echo "</body></html>" >> "$REPORT_HTML"

echo "[✅] Reporte generado: $REPORT_HTML"
