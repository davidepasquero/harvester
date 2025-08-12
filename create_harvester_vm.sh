#!/bin/bash
# =================================================================
# Script per la creazione di una Virtual Machine su Harvester
# tramite kubectl.
#
# ISTRUZIONI:
# 1. Personalizza le variabili nella sezione "CONFIGURAZIONE".
# 2. Assicurati di avere un `kubeconfig` valido e puntato
#    al cluster Harvester corretto.
# 3. Esegui lo script: ./create_harvester_vm.sh
# =================================================================

set -e

# --- CONFIGURAZIONE ---
# Modifica queste variabili per definire la tua VM

# --- Impostazioni Generali della VM ---
VM_NAME="k8sw05-enti-prod01"
NAMESPACE="k8s-enti-prod01"
GUEST_CLUSTER_NAME="k8s-enti-prod01" # Nome del cluster guest (usato per l'anti-affinità)
CPU_CORES=16
MEMORY="64Gi"
# ID dell'immagine Harvester da cui fare il boot.
# Puoi trovarlo nella UI di Harvester sotto "Images" o con `kubectl get vmimages -n default`.
IMAGE_ID="default/image-p6rcv"

# --- Dischi ---
# Il primo disco (disk-0) è il disco di boot e la sua dimensione è definita dall'immagine.
# Gli altri dischi sono aggiuntivi. Lo script di cloud-init fornito formatta
# /dev/vdb (disk-1) e /dev/vdc (disk-2) in LVM per /var/lib/rancher e /var/lib/kubelet.
DISK0_SIZE="50Gi"
DISK1_SIZE="150Gi" # Disco per /var/lib/rancher
DISK2_SIZE="50Gi"  # Disco per /var/lib/kubelet
STORAGE_CLASS_NAME="ontap-san-nvme" # StorageClass per i dischi

# --- Rete ---
# Definisci le network attachment definition (NAD) e gli IP per ogni interfaccia.
# Le NAD devono esistere nel cluster. Formato: <namespace>/<nad-name>
NIC1_NETWORK="k8s-enti-prod01/k8s-enti-prod01"
NIC1_IP="10.138.155.5/26" # IP e maschera in notazione CIDR
NIC1_GATEWAY="10.138.155.1"
# Inserisci i DNS server, uno per riga, con il corretto allineamento.
NIC1_DNS_SERVERS="
              - 10.103.48.1
              - 10.103.48.2"
NIC1_DNS_SEARCH="site01.nivolapiemonte.it"

NIC2_NETWORK="k8s-storage-podto1/k8s-storage-podto1"
NIC2_IP="10.138.151.68/25"

NIC3_NETWORK="k8s-storage-podt05/k8s-storage-podt05"
NIC3_IP="10.139.34.53/25"

# --- Cloud-Init ---
# Inserisci la tua chiave pubblica SSH.
# Puoi aggiungere più chiavi, una per riga, mantenendo l'indentazione.
SSH_AUTHORIZED_KEYS="
      - ssh-rsa AAAA... your-public-key"

# Impostazioni Proxy e NTP
HTTP_PROXY="http://proxy-nivola:3128"
NO_PROXY="127.0.0.0/8,10.0.0.0/8,cattle-system.svc,172.16.0.0/12,192.168.0.0/16,nivolapiemonte.it,csi.it"
NTP_SERVER="timehost.csi.it"

# --- FINE CONFIGURAZIONE ---


# --- LOGICA SCRIPT ---
# Funzione per generare una stringa random di 5 caratteri per i nomi delle risorse
rand_str() {
    head /dev/urandom | tr -dc a-z0-9 | head -c 5
}

# Genera nomi univoci per le risorse
CLOUD_INIT_SECRET_NAME="${VM_NAME}-cloud-init-$(rand_str)"
DISK0_PVC_NAME="${VM_NAME}-disk-0-$(rand_str)"
DISK1_PVC_NAME="${VM_NAME}-disk-1-$(rand_str)"
DISK2_PVC_NAME="${VM_NAME}-disk-2-$(rand_str)"

echo ">>> Preparazione dei manifest per la VM: ${VM_NAME}"

# --- 1. Generazione del Secret per Cloud-Init ---

# Heredoc per il networkData
NETWORK_DATA=$(cat <<EOF
#cloud-config
network:
  version: 2
  ethernets:
    enp1s0:
      dhcp4: false
      addresses:
        - ${NIC1_IP}
      nameservers:
        addresses: ${NIC1_DNS_SERVERS}
        search:
          - ${NIC1_DNS_SEARCH}
      routes:
        - to: 0.0.0.0/0
          via: ${NIC1_GATEWAY}
          on-link: true
    enp2s0:
      dhcp4: false
      addresses:
        - ${NIC2_IP}
      routes:
        - to: $(echo ${NIC2_IP} | cut -d'/' -f1 | cut -d'.' -f1-3).0/$(echo ${NIC2_IP} | cut -d'/' -f2)
          on-link: true
      mtu: 9000
      optional: true
    enp3s0:
      optional: true
      addresses:
       - "${NIC3_IP}"
      dhcp4: false
      mtu: 9000
      routes:
       - scope: "link"
         on-link: true
         to: $(echo ${NIC3_IP} | cut -d'/' -f1 | cut -d'.' -f1-3).0/$(echo ${NIC3_IP} | cut -d'/' -f2)
EOF
)

# Heredoc per lo userData
USER_DATA=$(cat <<EOF
#cloud-config
users:
  - name: root
    ssh_authorized_keys: ${SSH_AUTHORIZED_KEYS}
disable_root: false
ssh_pwauth: false
keyboard: {layout: it, model: pc105, variant: nodeadkeys, options: 'compose:rwin'}
apt:
  http_proxy: ${HTTP_PROXY}
  https_proxy: ${HTTP_PROXY}
package_update: true
package_upgrade: true
packages:
  - qemu-guest-agent
  - iptables
  - iptables-persistent
  - nfs-common
  - systemd-timesyncd
  - lvm2
write_files:
  - path: /etc/crictl.yaml
    permissions: "0644"
    content: |
      runtime-endpoint: unix:///run/k3s/containerd/containerd.sock
  - path: /etc/environment
    permissions: "0644"
    content: |
      NO_PROXY=${NO_PROXY}
      HTTPS_PROXY=${HTTP_PROXY}
      HTTP_PROXY=${HTTP_PROXY}
      http_proxy=${HTTP_PROXY}
      https_proxy=${HTTP_PROXY}
  - path: /etc/apt/apt.conf.d/00-proxy
    permissions: "0640"
    content: |
      Acquire::http { Proxy "${HTTP_PROXY}"; };
      Acquire::https { Proxy "${HTTP_PROXY}"; };
  - path: /etc/modules-load.d/iptables.conf
    permissions: "0644"
    content: |
      ip_tables iptable_nat ip6_tables iptable_filter nf_conntrack nf_conntrack_ipv4 nf_conntrack_ipv6 xt_mark
  - path: /etc/systemd/timesyncd.conf
    permissions: "0644"
    content: |
      [Time]
      NTP=${NTP_SERVER}
      FallbackNTP=ntp.ubuntu.com
  - path: /usr/local/bin/setup-lvm.sh
    permissions: "0755"
    content: |
      #!/bin/bash
      LOG="/var/log/lvm-setup.log"
      echo "--- Avvio setup LVM --- \$(date)" >> \$LOG
      for dev in /dev/vdb /dev/vdc; do
        for i in {1..10}; do
          if [ -b "\$dev" ]; then echo "Dispositivo \$dev trovato" >> \$LOG; break; fi
          echo "Attendo \$dev..." >> \$LOG; sleep 3;
        done
      done
      pvcreate /dev/vdb >> \$LOG 2>&1 && vgcreate vg_rancher /dev/vdb >> \$LOG 2>&1 && lvcreate -l 100%FREE -n lv_rancher vg_rancher >> \$LOG 2>&1 && mkfs.ext4 /dev/vg_rancher/lv_rancher >> \$LOG 2>&1
      pvcreate /dev/vdc >> \$LOG 2>&1 && vgcreate vg_kubelet /dev/vdc >> \$LOG 2>&1 && lvcreate -l 100%FREE -n lv_kubelet vg_kubelet >> \$LOG 2>&1 && mkfs.ext4 /dev/vg_kubelet/lv_kubelet >> \$LOG 2>&1
      mkdir -p /var/lib/rancher /var/lib/kubelet
      echo "/dev/vg_rancher/lv_rancher /var/lib/rancher ext4 defaults,nofail 0 2" >> /etc/fstab
      echo "/dev/vg_kubelet/lv_kubelet /var/lib/kubelet ext4 defaults,nofail 0 2" >> /etc/fstab
      mount -a >> \$LOG 2>&1
      echo "--- Fine setup LVM --- \$(date)" >> \$LOG
  - path: /etc/systemd/system/setup-lvm.service
    permissions: "0644"
    content: |
      [Unit]
      Description=Setup LVM volumes for rancher and kubelet
      Before=rancher-system-agent.service
      After=network.target local-fs.target
      ConditionPathExists=!/var/lib/rancher/lvm.setup.done
      [Service]
      Type=oneshot
      ExecStart=/usr/local/bin/setup-lvm.sh
      RemainAfterExit=true
      [Install]
      WantedBy=multi-user.target
  - path: /usr/local/bin/link_crictl.sh
    permissions: "0755"
    content: |
      #!/bin/bash
      LOG_FILE="/var/log/link_crictl.log"
      echo "Script link_crictl.sh avviato alle \$(date)" >> \$LOG_FILE
      while true; do
        if [ -f /var/lib/rancher/rke2/bin/crictl ]; then
          ln -sf /var/lib/rancher/rke2/bin/crictl /usr/bin/crictl
          echo "\$(date): Link simbolico creato" >> \$LOG_FILE
          touch /var/lib/rancher/lvm.setup.done
          exit 0
        else
          echo "\$(date): File crictl non trovato, riprovo tra 20 secondi..." >> \$LOG_FILE
          sleep 20
        fi
      done
  - path: /etc/systemd/system/link_crictl.service
    permissions: "0644"
    content: |
      [Unit]
      Description=Link Symbolyc for crictl
      After=network.target
      [Service]
      Type=simple
      ExecStart=/usr/local/bin/link_crictl.sh
      Restart=on-failure
      [Install]
      WantedBy=multi-user.target
runcmd:
  - systemctl daemon-reload
  - systemctl enable --now systemd-timesyncd.service
  - systemctl enable --now qemu-guest-agent.service
  - systemctl enable --now setup-lvm.service
  - systemctl enable --now link_crictl.service
  - sed -i '/ swap / s/^/#/' /etc/fstab
  - swapoff -a
  - sysctl -w net.ipv4.ip_forward=1
  - sysctl -w net.ipv6.conf.all.forwarding=1
  - sh -c "echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf"
  - sh -c "echo 'net.ipv6.conf.all.forwarding=1' >> /etc/sysctl.conf"
  - systemctl stop ufw && systemctl disable ufw
  - modprobe macvlan && modprobe xt_mark && modprobe nf_tables
  - iptables-save
  - ip6tables-save
EOF
)

# Creazione del manifest del Secret
SECRET_MANIFEST=$(cat <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${CLOUD_INIT_SECRET_NAME}
  namespace: ${NAMESPACE}
stringData:
  networkData: |
$(echo "${NETWORK_DATA}" | sed 's/^/    /')
  userData: |
$(echo "${USER_DATA}" | sed 's/^/    /')
EOF
)

echo "---"
echo "1. Creazione del Secret per cloud-init: ${CLOUD_INIT_SECRET_NAME}"
echo "${SECRET_MANIFEST}" | kubectl apply -f -

# --- 2. Generazione del manifest della Virtual Machine ---

# Costruzione del JSON per l'annotazione volumeClaimTemplates
VOLUME_CLAIM_TEMPLATES_JSON=$(cat <<EOT
[
  {
    "metadata": {
      "name": "${DISK0_PVC_NAME}",
      "annotations": { "harvesterhci.io/imageId": "${IMAGE_ID}" }
    },
    "spec": {
      "accessModes": ["ReadWriteMany"],
      "resources": { "requests": { "storage": "${DISK0_SIZE}" } },
      "volumeMode": "Block",
      "storageClassName": "${STORAGE_CLASS_NAME}"
    }
  },
  {
    "metadata": { "name": "${DISK1_PVC_NAME}" },
    "spec": {
      "accessModes": ["ReadWriteMany"],
      "resources": { "requests": { "storage": "${DISK1_SIZE}" } },
      "volumeMode": "Block",
      "storageClassName": "${STORAGE_CLASS_NAME}"
    }
  },
  {
    "metadata": { "name": "${DISK2_PVC_NAME}" },
    "spec": {
      "accessModes": ["ReadWriteMany"],
      "resources": { "requests": { "storage": "${DISK2_SIZE}" } },
      "volumeMode": "Block",
      "storageClassName": "${STORAGE_CLASS_NAME}"
    }
  }
]
EOT
)

# Creazione del manifest della VM
VM_MANIFEST=$(cat <<EOF
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: ${VM_NAME}
  namespace: ${NAMESPACE}
  annotations:
    harvesterhci.io/volumeClaimTemplates: |
$(echo "${VOLUME_CLAIM_TEMPLATES_JSON}" | sed 's/^/      /')
    network.harvesterhci.io/ips: '[]'
spec:
  runStrategy: RerunOnFailure
  template:
    metadata:
      labels:
        harvesterhci.io/vmName: ${VM_NAME}
        guestcluster.harvesterhci.io/name: ${GUEST_CLUSTER_NAME}
    spec:
      hostname: ${VM_NAME}
      terminationGracePeriodSeconds: 120
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 1
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: guestcluster.harvesterhci.io/name
                  operator: In
                  values:
                  - ${GUEST_CLUSTER_NAME}
              topologyKey: kubernetes.io/hostname
      domain:
        machine: {type: q35}
        cpu: {cores: ${CPU_CORES}, sockets: 1, threads: 1}
        resources:
          requests: {cpu: 1, memory: 2Gi} # Richieste minime
          limits: {cpu: '${CPU_CORES}', memory: ${MEMORY}}
        devices:
          inputs:
            - {bus: usb, name: tablet, type: tablet}
          interfaces:
            - {bridge: {}, model: virtio, name: nic-1}
            - {bridge: {}, model: virtio, name: nic-2}
            - {bridge: {}, model: virtio, name: nic-3}
          disks:
            - {name: disk-0, disk: {bus: virtio}, bootOrder: 1}
            - {name: disk-1, disk: {bus: virtio}}
            - {name: disk-2, disk: {bus: virtio}}
            - {name: cloudinitdisk, disk: {bus: virtio}}
      networks:
        - {name: nic-1, multus: {networkName: ${NIC1_NETWORK}}}
        - {name: nic-2, multus: {networkName: ${NIC2_NETWORK}}}
        - {name: nic-3, multus: {networkName: ${NIC3_NETWORK}}}
      volumes:
        - {name: disk-0, persistentVolumeClaim: {claimName: ${DISK0_PVC_NAME}}}
        - {name: disk-1, persistentVolumeClaim: {claimName: ${DISK1_PVC_NAME}}}
        - {name: disk-2, persistentVolumeClaim: {claimName: ${DISK2_PVC_NAME}}}
        - name: cloudinitdisk
          cloudInitNoCloud:
            secretRef: {name: ${CLOUD_INIT_SECRET_NAME}}
EOF
)

echo "---"
echo "2. Creazione della Virtual Machine: ${VM_NAME}"
echo "${VM_MANIFEST}" | kubectl apply -f -

echo "---"
echo "✅ Fatto!"
echo "La VM ${VM_NAME} è in fase di creazione nel namespace ${NAMESPACE}."
echo "Puoi monitorare lo stato con il comando:"
echo "kubectl get vm/${VM_NAME} -n ${NAMESPACE} -w"
