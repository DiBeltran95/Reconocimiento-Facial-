#!/usr/bin/env bash
# Prepara la firma de iOS en el runner de macOS a partir de los secretos:
#   IOS_P12_BASE64       certificado .p12 (Apple Development / Apple Distribution) en base64
#   IOS_P12_PASSWORD     contraseña del .p12
#   IOS_PROVISION_BASE64 perfil .mobileprovision en base64 (ad hoc recomendado)
# Ajusta el proyecto Runner a firma manual con ese perfil y genera ExportOptions.plist.
set -euo pipefail
: "${IOS_P12_BASE64:?Falta el secreto IOS_P12_BASE64}"
: "${IOS_P12_PASSWORD:?Falta el secreto IOS_P12_PASSWORD}"
: "${IOS_PROVISION_BASE64:?Falta el secreto IOS_PROVISION_BASE64}"

certificado="$RUNNER_TEMP/certificado.p12"
perfil="$RUNNER_TEMP/perfil.mobileprovision"
llavero="$RUNNER_TEMP/firma.keychain-db"
clave_llavero="$(openssl rand -hex 16)"

echo -n "$IOS_P12_BASE64" | base64 --decode -o "$certificado"
echo -n "$IOS_PROVISION_BASE64" | base64 --decode -o "$perfil"

security create-keychain -p "$clave_llavero" "$llavero"
security set-keychain-settings -lut 21600 "$llavero"
security unlock-keychain -p "$clave_llavero" "$llavero"
security import "$certificado" -P "$IOS_P12_PASSWORD" -A -t cert -f pkcs12 -k "$llavero"
security set-key-partition-list -S apple-tool:,apple: -k "$clave_llavero" "$llavero" > /dev/null
# shellcheck disable=SC2046
security list-keychains -d user -s "$llavero" $(security list-keychains -d user | tr -d '"')

security cms -D -i "$perfil" > "$RUNNER_TEMP/perfil.plist"
mkdir -p "$HOME/Library/MobileDevice/Provisioning Profiles"
uuid=$(/usr/libexec/PlistBuddy -c 'Print :UUID' "$RUNNER_TEMP/perfil.plist")
cp "$perfil" "$HOME/Library/MobileDevice/Provisioning Profiles/$uuid.mobileprovision"

python3 - "$RUNNER_TEMP/perfil.plist" "$RUNNER_TEMP/ExportOptions.plist" <<'PY'
import plistlib, re, sys

with open(sys.argv[1], 'rb') as f:
    p = plistlib.load(f)

nombre = p['Name']
equipo = p['TeamIdentifier'][0]
app_id = p['Entitlements']['application-identifier']
bundle = app_id.split('.', 1)[1]
original = 'co.controlpersonal.controlPersonal'
if '*' in bundle:  # perfil comodín: se conserva el identificador del proyecto
    bundle = original

if p.get('ProvisionsAllDevices'):
    metodo, identidad = 'enterprise', 'Apple Distribution'
elif p.get('ProvisionedDevices'):
    if p['Entitlements'].get('get-task-allow'):
        metodo, identidad = 'development', 'Apple Development'
    else:
        metodo, identidad = 'ad-hoc', 'Apple Distribution'
else:
    metodo, identidad = 'app-store', 'Apple Distribution'

proyecto = 'ios/Runner.xcodeproj/project.pbxproj'
texto = open(proyecto, encoding='utf-8').read()
reemplazo = (
    f'PRODUCT_BUNDLE_IDENTIFIER = {bundle};\n'
    f'\t\t\t\tCODE_SIGN_STYLE = Manual;\n'
    f'\t\t\t\tDEVELOPMENT_TEAM = {equipo};\n'
    f'\t\t\t\tPROVISIONING_PROFILE_SPECIFIER = "{nombre}";\n'
    f'\t\t\t\t"CODE_SIGN_IDENTITY[sdk=iphoneos*]" = "{identidad}";'
)
texto, cambios = re.subn(re.escape(f'PRODUCT_BUNDLE_IDENTIFIER = {original};'), lambda _: reemplazo, texto)
if cambios == 0:
    sys.exit('No se encontró el identificador del Runner en project.pbxproj')
open(proyecto, 'w', encoding='utf-8').write(texto)

with open(sys.argv[2], 'wb') as f:
    plistlib.dump({
        'method': metodo,
        'teamID': equipo,
        'signingStyle': 'manual',
        'signingCertificate': identidad,
        'provisioningProfiles': {bundle: nombre},
        'compileBitcode': False,
        'stripSwiftSymbols': True,
    }, f)
print(f'Firma manual: {bundle} · equipo {equipo} · método {metodo} · perfil "{nombre}"')
PY
