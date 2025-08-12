#!/bin/bash

# This script temporarily disables the Harvester network validation webhook
# to allow for changes to VlanConfigs that are in use by running VMs.

# --- Configuration ---
# Please verify these names. They are based on the error message provided.
WEBHOOK_NAME="harvester-network-webhook"
NAMESPACE="harvester-system"
BACKUP_FILE="webhook-backup.yaml"

echo "### Step 1: Backing up the webhook configuration..."
kubectl get validatingwebhookconfiguration "$WEBHOOK_NAME" -n "$NAMESPACE" -o yaml > "$BACKUP_FILE"

if [ $? -ne 0 ]; then
    echo "Error: Failed to get webhook configuration. Does it exist with the name '$WEBHOOK_NAME' in namespace '$NAMESPACE'?"
    exit 1
fi

echo "Backup created at $BACKUP_FILE"
echo ""

echo "### Step 2: Temporarily disabling the webhook..."
kubectl patch validatingwebhookconfiguration "$WEBHOOK_NAME" -n "$NAMESPACE" --type=merge -p '{"webhooks":[]}'

if [ $? -ne 0 ]; then
    echo "Error: Failed to patch the webhook. Please check your permissions."
    # Attempt to restore from backup on failure
    kubectl apply -f "$BACKUP_FILE"
    exit 1
fi

echo "Webhook disabled."
echo ""
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo "!!! IMPORTANT: The validation webhook is now disabled.                     !!!"
echo "!!! Please apply your VlanConfig changes in another terminal NOW.        !!!"
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo ""
read -p "Once you have finished applying your changes, press Enter to continue and restore the webhook..."

echo ""
echo "### Step 3: Restoring the webhook from backup..."
kubectl apply -f "$BACKUP_FILE"

if [ $? -ne 0 ]; then
    echo "Error: Failed to restore the webhook. Please restore it manually using: kubectl apply -f $BACKUP_FILE"
    exit 1
fi

echo "Webhook restored successfully."
echo ""

echo "### Step 4: Cleaning up..."
rm "$BACKUP_FILE"
echo "Backup file removed."
echo ""
echo "Process complete."
