#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# First Install
#
# Debian Trixie / ARM64
#
# Instala:
#   - SSH keys para root
#   - Tailscale
#   - Docker
#   - MooseFS 5 client + chunkserver
#   - Montaje /mnt/mfs
#
# Uso:
#   sudo TAILSCALE_AUTH_KEY='tskey-auth-xxxx' bash first-install.sh
#
# ============================================================

TAILSCALE_AUTH_KEY="${TAILSCALE_AUTH_KEY:-}"

MOOSEFS_MASTER="${MOOSEFS_MASTER:-mfsmaster}"
MOOSEFS_MOUNT="/mnt/mfs"

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------

log() {
    echo
    echo "============================================================"
    echo " $*"
    echo "============================================================"
}

fail() {
    echo
    echo "ERROR: $*" >&2
    exit 1
}

# ------------------------------------------------------------
# Root
# ------------------------------------------------------------

[[ "$EUID" -eq 0 ]] || fail "Este script debe ejecutarse como root."

# ------------------------------------------------------------
# Sistema
# ------------------------------------------------------------

. /etc/os-release

ARCH="$(dpkg --print-architecture)"

[[ "$ARCH" == "arm64" ]] || \
    fail "Arquitectura no soportada: $ARCH. Se esperaba arm64."

if [[ "${ID:-}" != "debian" ]] || [[ "${VERSION_CODENAME:-}" != "trixie" ]]; then
    echo "ADVERTENCIA: este script está preparado para Debian Trixie."
    echo "Sistema detectado: ${PRETTY_NAME:-unknown}"
    echo
fi

log "Sistema"

echo "OS:   ${PRETTY_NAME:-unknown}"
echo "Arch: $ARCH"

# ------------------------------------------------------------
# SSH
# ------------------------------------------------------------

log "Configurando claves SSH de root"

install -d -m 0700 /root/.ssh
touch /root/.ssh/authorized_keys
chmod 0600 /root/.ssh/authorized_keys

while IFS= read -r key; do
    [[ -z "$key" ]] && continue

    if grep -Fqx "$key" /root/.ssh/authorized_keys; then
        echo "Clave SSH ya existente."
    else
        echo "$key" >> /root/.ssh/authorized_keys
        echo "Clave SSH añadida."
    fi
done <<'EOF'
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICwyR3lVXdm1NutBfDpPjVwowDGunn2kTvjf2oqsV3Nu mbp
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILLcMG5ZrtDn+uTgrctVyYQCcWL7Iqbyk4RV8oGZnswb farm
EOF

chown -R root:root /root/.ssh

# ------------------------------------------------------------
# APT
# ------------------------------------------------------------

log "Preparando APT"

apt-get update

apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    gpg

# ------------------------------------------------------------
# Tailscale
# ------------------------------------------------------------

log "Instalando Tailscale"

if command -v tailscale >/dev/null 2>&1; then
    echo "Tailscale ya está instalado."
else
    curl -fsSL https://tailscale.com/install.sh | sh
fi

systemctl enable --now tailscaled

if tailscale status >/dev/null 2>&1; then
    echo "Tailscale ya está conectado."
else
    [[ -n "$TAILSCALE_AUTH_KEY" ]] || \
        fail "Falta TAILSCALE_AUTH_KEY."

    log "Conectando Tailscale"

    tailscale up \
        --auth-key="$TAILSCALE_AUTH_KEY"
fi

# ------------------------------------------------------------
# Docker
# ------------------------------------------------------------

log "Instalando Docker"

if command -v docker >/dev/null 2>&1; then
    echo "Docker ya está instalado."
else
    curl -fsSL https://get.docker.com | sh
fi

systemctl enable --now docker

echo
docker --version

# ------------------------------------------------------------
# MooseFS repository
# ------------------------------------------------------------

log "Configurando repositorio MooseFS"

install -d -m 0755 /etc/apt/keyrings

if [[ ! -f /etc/apt/keyrings/moosefs.gpg ]]; then
    curl -fsSL https://repository.moosefs.com/moosefs.key \
        | gpg --dearmor \
        -o /etc/apt/keyrings/moosefs.gpg

    chmod 0644 /etc/apt/keyrings/moosefs.gpg
else
    echo "Clave del repositorio MooseFS ya existe."
fi

cat > /etc/apt/sources.list.d/moosefs.list <<'EOF'
deb [arch=arm64 signed-by=/etc/apt/keyrings/moosefs.gpg] http://repository.moosefs.com/moosefs-5/apt/debian/trixie trixie main
EOF

apt-get update

# ------------------------------------------------------------
# MooseFS
# ------------------------------------------------------------

log "Instalando MooseFS"

apt-get install -y \
    moosefs-pro-chunkserver \
    moosefs-pro-client

# ------------------------------------------------------------
# MooseFS mount
# ------------------------------------------------------------

log "Configurando /mnt/mfs"

install -d -m 0755 "$MOOSEFS_MOUNT"

# Eliminar cualquier entrada MooseFS anterior para /mnt/mfs.
sed -i "\|[[:space:]]${MOOSEFS_MOUNT}[[:space:]]\+moosefs[[:space:]]|d" /etc/fstab

cat >> /etc/fstab <<EOF
${MOOSEFS_MASTER}:/mnt/mfs ${MOOSEFS_MOUNT} moosefs defaults,_netdev,noauto,x-systemd.automount,mfsdelayedinit 0 0
EOF

systemctl daemon-reload

# ------------------------------------------------------------
# Montaje
# ------------------------------------------------------------

log "Montando MooseFS"

mount "$MOOSEFS_MOUNT"

# ------------------------------------------------------------
# Verificación
# ------------------------------------------------------------

log "Verificando instalación"

echo
echo "--- SSH ---"

if [[ -f /root/.ssh/authorized_keys ]]; then
    echo "authorized_keys: OK"
    echo "Claves configuradas: $(wc -l < /root/.ssh/authorized_keys)"
fi

echo
echo "--- Tailscale ---"

tailscale status
echo
echo "IP Tailscale:"
tailscale ip -4 || true

echo
echo "--- Docker ---"

docker info >/dev/null
echo "Docker: OK"
docker --version

echo
echo "--- MooseFS ---"

if findmnt "$MOOSEFS_MOUNT" >/dev/null 2>&1; then
    echo "Montaje: OK"
    findmnt "$MOOSEFS_MOUNT"
else
    echo "ADVERTENCIA: /mnt/mfs no aparece montado."
fi

echo
echo "--- Servicios ---"

systemctl is-active --quiet tailscaled \
    && echo "tailscaled: OK" \
    || echo "tailscaled: ERROR"

systemctl is-active --quiet docker \
    && echo "docker: OK" \
    || echo "docker: ERROR"

echo
echo "============================================================"
echo " FIRST INSTALL COMPLETADO"
echo "============================================================"
echo
echo "Tailscale:"
tailscale ip -4 2>/dev/null || true

echo
echo "MooseFS:"
findmnt "$MOOSEFS_MOUNT" -o TARGET,SOURCE,FSTYPE,OPTIONS 2>/dev/null || true

echo
echo "Docker:"
docker --version

echo