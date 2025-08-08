#!/bin/bash

# Imposta lo script per uscire immediatamente se un comando fallisce.
set -e

# --- IMPOSTAZIONI ---
SCRIPT_DIR="$(dirname "$0")"
OUTPUT_DIR="$SCRIPT_DIR/output-yaml"

# Crea la directory di output se non esiste
mkdir -p "$OUTPUT_DIR"
echo "I file YAML generati verranno salvati in '$OUTPUT_DIR'"
echo ""

echo "--- Script di Clonazione VM Harvester/KubeVirt (Interattivo) ---"
echo ""

# --- RACCOLTA INPUT UTENTE (ORIGINE) ---
read -p "Inserisci il namespace della VM di origine: " SOURCE_NS
if [ -z "$SOURCE_NS" ]; then
    echo "Errore: Il namespace di origine non può essere vuoto."
    exit 1
fi

read -p "Inserisci il nome della VM di origine: " SOURCE_VM
if [ -z "$SOURCE_VM" ]; then
    echo "Errore: Il nome della VM di origine non può essere vuoto."
    exit 1
fi

echo ""
echo "VM di origine: $SOURCE_VM nel namespace $SOURCE_NS"
echo ""

# --- RACCOLTA INPUT UTENTE (DESTINAZIONE) ---
read -p "Inserisci il namespace di destinazione per la nuova VM: " DEST_NS
if [ -z "$DEST_NS" ]; then
    echo "Errore: Il namespace di destinazione non può essere vuoto."
    exit 1
fi

# Il nome della nuova VM sarà uguale al namespace di destinazione.
NEW_VM_NAME=$DEST_NS

echo ""
echo "La nuova VM si chiamerà: $NEW_VM_NAME"
echo ""

# --- VERIFICA E CREAZIONE NAMESPACE ---
echo "Verifico se il namespace '$DEST_NS' esiste..."
if ! kubectl get namespace "$DEST_NS" > /dev/null 2>&1; then
    echo "Il namespace '$DEST_NS' non esiste. Lo creo..."
    kubectl create namespace "$DEST_NS"
    echo "Namespace '$DEST_NS' creato con successo."
else
    echo "Il namespace '$DEST_NS' esiste già."
fi
echo ""

# --- ESTRAZIONE E MODIFICA DELLA CONFIGURAZIONE DI RETE ---
echo "Recupero la configurazione di rete dalla VM di origine..."

SECRET_NAME=$(kubectl get vm "$SOURCE_VM" -n "$SOURCE_NS" -o jsonpath='{.spec.template.spec.volumes[?(@.cloudInitNoCloud)].cloudInitNoCloud.secretRef.name}')
if [ -z "$SECRET_NAME" ]; then
    echo "Errore: Impossibile trovare il secret cloud-init per la VM $SOURCE_VM."
    exit 1
fi
echo "Trovato secret di rete: $SECRET_NAME"

NETWORK_DATA_BASE64=$(kubectl get secret "$SECRET_NAME" -n "$SOURCE_NS" -o jsonpath='{.data.networkdata}')
NETWORK_DATA_DECODED=$(echo "$NETWORK_DATA_BASE64" | base64 --decode)

# Estrai i valori attuali per mostrarli all'utente
OLD_IP_1=$(echo "$NETWORK_DATA_DECODED" | grep -A 2 'enp1s0' | grep 'addresses:' | awk '{print $2}')
OLD_GW_1=$(echo "$NETWORK_DATA_DECODED" | grep -A 5 'enp1s0' | grep 'via:' | awk '{print $2}')
OLD_IP_2=$(echo "$NETWORK_DATA_DECODED" | grep -A 2 'enp2s0' | grep 'addresses:' | awk '{print $2}')
OLD_SITE_PREFIX=$(echo "$NETWORK_DATA_DECODED" | grep 'search:' -A 1 | grep -v 'search:' | awk '{print $2}' | cut -d. -f1)

echo ""
echo "--- Inserisci i nuovi valori di rete ---"
read -p "Nuovo IP per eth0 (attuale: ${OLD_IP_1:-non trovato}): " NEW_IP_1
read -p "Nuovo Gateway per eth0 (attuale: ${OLD_GW_1:-non trovato}): " NEW_GW_1
read -p "Nuovo IP per eth1 (attuale: ${OLD_IP_2:-non trovato}): " NEW_IP_2
read -p "Nuovo prefisso sito per dominio di ricerca (attuale: ${OLD_SITE_PREFIX:-non trovato}): " NEW_SITE_PREFIX
read -p "Nuovo Gateway per la rotta di eth1 (opzionale, lascia vuoto per non modificare): " NEW_GW_2

# Sostituisci i valori
MODIFIED_NETWORK_DATA=$NETWORK_DATA_DECODED
if [ -n "$OLD_IP_1" ]; then
    MODIFIED_NETWORK_DATA=$(echo "$MODIFIED_NETWORK_DATA" | sed "s|$OLD_IP_1|$NEW_IP_1|")
fi
if [ -n "$OLD_GW_1" ]; then
    MODIFIED_NETWORK_DATA=$(echo "$MODIFIED_NETWORK_DATA" | sed "s|$OLD_GW_1|$NEW_GW_1|")
fi
if [ -n "$OLD_IP_2" ]; then
    MODIFIED_NETWORK_DATA=$(echo "$MODIFIED_NETWORK_DATA" | sed "s|$OLD_IP_2|$NEW_IP_2|")
fi
if [ -n "$OLD_SITE_PREFIX" ] && [ -n "$NEW_SITE_PREFIX" ]; then
    MODIFIED_NETWORK_DATA=$(echo "$MODIFIED_NETWORK_DATA" | sed "s/$OLD_SITE_PREFIX/$NEW_SITE_PREFIX/g")
fi
if [ -n "$NEW_GW_2" ]; then
    MODIFIED_NETWORK_DATA=$(echo "$MODIFIED_NETWORK_DATA" | sed "/enp2s0:/,/^$/s/on-link: true/via: $NEW_GW_2/")
fi

MODIFIED_NETWORK_DATA_BASE64=$(echo -n "$MODIFIED_NETWORK_DATA" | base64 | tr -d '\n')

# --- CREAZIONE DEL NUOVO SECRET DI RETE ---
NEW_SECRET_NAME="$NEW_VM_NAME-network-config"
SECRET_YAML_PATH="$OUTPUT_DIR/${DEST_NS}-secret.yaml"
echo ""
echo "Creo il manifest per il nuovo secret di rete in '$SECRET_YAML_PATH'..."

cat <<EOF > "$SECRET_YAML_PATH"
apiVersion: v1
kind: Secret
metadata:
  name: $NEW_SECRET_NAME
  namespace: $DEST_NS
data:
  networkdata: $MODIFIED_NETWORK_DATA_BASE64
EOF

echo "Applico il manifest del secret..."
kubectl apply -f "$SECRET_YAML_PATH"
echo "Secret '$NEW_SECRET_NAME' creato."
echo ""

# --- CREAZIONE DELLA NUOVA VM ---
VM_YAML_PATH="$OUTPUT_DIR/${DEST_NS}-vm.yaml"
echo "Preparo il manifest per la nuova VM '$NEW_VM_NAME' in '$VM_YAML_PATH'..."

kubectl get vm "$SOURCE_VM" -n "$SOURCE_NS" -o yaml | \
  grep -v -e "creationTimestamp:" -e "resourceVersion:" -e "uid:" -e "selfLink:" -e "generation:" -e "status:" | \
  sed "s/namespace: $SOURCE_NS/namespace: $DEST_NS/" | \
  sed "s/name: $SECRET_NAME/name: $NEW_SECRET_NAME/" | \
  sed "s/$SOURCE_VM/$NEW_VM_NAME/g" > "$VM_YAML_PATH"

echo "Applico il manifest della VM..."
kubectl apply -f "$VM_YAML_PATH"

echo ""
echo "--- COMPLETATO ---"
echo "La nuova VM '$NEW_VM_NAME' è stata creata nel namespace '$DEST_NS'."
echo "I manifest YAML sono stati salvati in '$OUTPUT_DIR'."
echo "Per avviarla, esegui:"
echo "kubectl -n $DEST_NS patch vm $NEW_VM_NAME --type merge --patch '{\"spec\":{\"running\":true}}'"
