#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 4 ]; then
    echo "Usage: $0 <resource-group> <vm-name> <vhd-path> <storage-account> [container]"
    echo "Example: $0 my-rg my-vm ./my-vm.vhd mystorageacct vhds"
    exit 1
fi

RG=$1
VM=$2
VHD=$3
SA=$4
CONTAINER=${5:-vhds}

echo "Computing MD5 hash of $VHD to check for changes..."
HASH=$(md5sum "$VHD" | awk '{print $1}')
BLOB_NAME="${VM}-${HASH}.vhd"
NEW_DISK_NAME="${VM}-osdisk-${HASH}"

echo "Creating container $CONTAINER (if it doesn't exist)..."
az storage container create --name "$CONTAINER" --account-name "$SA" >/dev/null 2>&1 || true

BLOB_EXISTS=$(az storage blob exists --account-name "$SA" --container-name "$CONTAINER" --name "$BLOB_NAME" --query "exists" -o tsv 2>/dev/null || echo "false")

if [ "$BLOB_EXISTS" = "true" ]; then
    echo "Blob $BLOB_NAME already exists (hash matches). Skipping upload..."
else
    echo "Uploading $VHD to Storage Account '$SA' as page blob..."
    az storage blob upload \
        --account-name "$SA" \
        --container-name "$CONTAINER" \
        --name "$BLOB_NAME" \
        --file "$VHD" \
        --type page
fi

BLOB_URL="https://${SA}.blob.core.windows.net/${CONTAINER}/${BLOB_NAME}"

DISK_EXISTS=$(az disk show -g "$RG" -n "$NEW_DISK_NAME" --query "name" -o tsv 2>/dev/null || echo "")

if [ -n "$DISK_EXISTS" ]; then
    echo "Managed Disk $NEW_DISK_NAME already exists."
else
    echo "Creating Managed Disk ($NEW_DISK_NAME) from Blob..."
    az disk create \
        --resource-group "$RG" \
        --name "$NEW_DISK_NAME" \
        --source "$BLOB_URL" \
        --os-type Linux
fi

VM_EXISTS=$(az vm show -g "$RG" -n "$VM" --query "name" -o tsv 2>/dev/null || echo "")

if [ -n "$VM_EXISTS" ]; then
    OLD_DISK_ID=$(az vm show -g "$RG" -n "$VM" --query "storageProfile.osDisk.managedDisk.id" -o tsv || echo "")
    OLD_DISK_NAME=$(echo "$OLD_DISK_ID" | rev | cut -d'/' -f1 | rev)

    if [ "$OLD_DISK_NAME" = "$NEW_DISK_NAME" ]; then
        echo "VM $VM is already running the latest image ($NEW_DISK_NAME). Nothing to do!"
        exit 0
    fi

    echo "VM $VM exists but is running an old image."
    
    PROV_STATE=$(az vm show -g "$RG" -n "$VM" --query "provisioningState" -o tsv || echo "")
    if [ "$PROV_STATE" != "Succeeded" ] && [ -n "$PROV_STATE" ]; then
        echo "VM $VM is in state $PROV_STATE. Reapplying to fix state before update..."
        az vm reapply --resource-group "$RG" --name "$VM" || true
    fi

    echo "Stopping VM $VM..."
    az vm deallocate --resource-group "$RG" --name "$VM"

    echo "Swapping OS Disk for VM $VM..."
    if ! az vm update \
        --resource-group "$RG" \
        --name "$VM" \
        --os-disk "$NEW_DISK_NAME"; then
        
        echo "VM OS disk update failed (likely due to guest provisioning state). Attempting to recreate the VM..."
        
        NIC_ID=$(az vm show -g "$RG" -n "$VM" --query "networkProfile.networkInterfaces[0].id" -o tsv || echo "")
        VM_SIZE=$(az vm show -g "$RG" -n "$VM" --query "hardwareProfile.vmSize" -o tsv || echo "")
        
        if [ -z "$NIC_ID" ]; then
            echo "Error: Could not retrieve NIC ID for VM $VM. Cannot safely recreate."
            exit 1
        fi
        
        echo "Deleting VM $VM (preserving NIC)..."
        az vm delete --resource-group "$RG" --name "$VM" --yes
        
        echo "Recreating VM $VM with new OS disk..."
        az vm create \
            --resource-group "$RG" \
            --name "$VM" \
            --size "${VM_SIZE:-Standard_B2s}" \
            --attach-os-disk "$NEW_DISK_NAME" \
            --nics "$NIC_ID" \
            --os-type Linux
    else
        echo "Starting VM $VM..."
        az vm start --resource-group "$RG" --name "$VM"
    fi

    if [ -n "$OLD_DISK_ID" ]; then
        echo "Deleting old OS disk ($OLD_DISK_ID)..."
        az disk delete --ids "$OLD_DISK_ID" --yes || true
    fi
else
    echo "VM $VM does not exist. Creating new VM..."
    az vm create \
        --resource-group "$RG" \
        --name "$VM" \
        --attach-os-disk "$NEW_DISK_NAME" \
        --os-type Linux \
        --public-ip-sku Standard
fi

echo "Done! $VM has been deployed with the latest image."
