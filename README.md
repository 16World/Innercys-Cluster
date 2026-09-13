# Innercys-Cluster

## Ansible Semaphore

Importa `playbooks/first-install.yaml` como tarea de Ansible Semaphore y usa un inventario con los nodos ARM64 de Debian. El playbook requiere privilegios de root mediante `become`.

Define `tailscale_auth_key` como extra variable secreta de Semaphore. No la guardes en el repositorio. Puedes sobrescribir `moosefs_master`, `moosefs_mount` y `root_authorized_keys` con variables del inventario o del template.

El playbook conserva la instalación de Tailscale y Docker mediante sus instaladores oficiales, configura el repositorio MooseFS 5, instala cliente y chunkserver, y monta `/mnt/mfs`.

La tarea existente `playbooks/docker-prune.yaml` puede importarse como un template separado para la limpieza periódica de Docker.