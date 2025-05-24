#!/bin/bash
set -euo pipefail

# ==============================
# USER CONFIGURATION
# ==============================
RESOURCE_GROUP="myResourceGroup"
BATCH_ACCOUNT_NAME="myBatchAccount"
LOCATION="eastus"

POOL_ID="autoscaleReportPool"
JOB_ID="reportJob"
TASK_ID="generateReport"
VM_SIZE="Standard_D2_v3"

KEYVAULT_NAME="myKeyVault"
INPUT_CONTAINER_NAME="batch-inputs"
OUTPUT_CONTAINER_NAME="batch-outputs"
INPUT_FILE_PATH="input.txt"
OUTPUT_FILE_NAME="output.txt"
LOCAL_OUTPUT_FILE="downloaded_output.txt"

# ==============================
# LOGIN AND SET BATCH CONTEXT
# ==============================
echo "Logging in and setting Batch context..."
az login --only-show-errors
az batch account set --resource-group "$RESOURCE_GROUP" --name "$BATCH_ACCOUNT_NAME"

# ==============================
# RETRIEVE SECRETS FROM KEY VAULT
# (BatchSecrets must be a JSON blob)
# (Storage secrets stored separately)
# ==============================
echo "Retrieving secrets from Azure Key Vault..."
batch_secrets=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "BatchSecrets" --query value -o tsv)
acr_username=$(echo "$batch_secrets" | jq -r '.acrUsername')
acr_password=$(echo "$batch_secrets" | jq -r '.acrPassword')
acr_server=$(echo "$batch_secrets" | jq -r '.acrServer')

storage_account=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "StorageAccountName" --query value -o tsv)
storage_key=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "StorageAccountKey" --query value -o tsv)

# ==============================
# UPLOAD INPUT FILE TO BLOB
# ==============================
echo "Uploading input file to Azure Blob..."
az storage blob upload \
  --account-name "$storage_account" \
  --account-key "$storage_key" \
  --container-name "$INPUT_CONTAINER_NAME" \
  --name "$INPUT_FILE_PATH" \
  --file "$INPUT_FILE_PATH" \
  --overwrite

input_url=$(az storage blob url \
  --account-name "$storage_account" \
  --account-key "$storage_key" \
  --container-name "$INPUT_CONTAINER_NAME" \
  --name "$INPUT_FILE_PATH" -o tsv)

# ==============================
# CREATE BATCH POOL WITH AUTOSCALING
# ==============================
echo "Creating Batch pool (if not exists)..."
az batch pool create \
  --id "$POOL_ID" \
  --vm-size "$VM_SIZE" \
  --image canonical:ubuntu-20.04-lts \
  --node-agent-sku-id "batch.node.ubuntu 20.04" \
  --container-configuration type=DockerCompatible \
  --auto-scale-enabled true \
  --auto-scale-formula '$TargetDedicatedNodes = pendingTasks > 0 ? 1 : 0; $NodeDeallocationOption = taskcompletion;' \
  --container-registry server="$acr_server" username="$acr_username" password="$acr_password"

# ==============================
# CREATE JOB AND TASK
# ==============================
echo "Creating Batch job..."
az batch job create --id "$JOB_ID" --pool-id "$POOL_ID"

echo "Creating containerized task..."
az batch task create \
  --job-id "$JOB_ID" \
  --task-id "$TASK_ID" \
  --image "$acr_server/report-generator:latest" \
  --command-line "python generate_report.py --input input.txt --output $OUTPUT_FILE_NAME" \
  --container-run-options "--rm" \
  --resource-files "[{ \"blobSource\": \"$input_url\", \"filePath\": \"input.txt\" }]" \
  --output-files "[{ 
      \"filePattern\": \"$OUTPUT_FILE_NAME\", 
      \"destination\": {
        \"container\": {
          \"containerUrl\": \"https://${storage_account}.blob.core.windows.net/$OUTPUT_CONTAINER_NAME?${storage_key}\"
        }
      },
      \"uploadOptions\": { \"uploadCondition\": \"TaskSuccess\" }
    }]"

# ==============================
# WAIT FOR TASK COMPLETION
# ==============================
echo "Waiting for task to complete..."
while true; do
  TASK_STATE=$(az batch task show --job-id "$JOB_ID" --task-id "$TASK_ID" --query "state" -o tsv)
  echo "Current state: $TASK_STATE"
  if [[ "$TASK_STATE" == "completed" ]]; then
    break
  fi
  sleep 10
done

EXIT_CODE=$(az batch task show --job-id "$JOB_ID" --task-id "$TASK_ID" --query "executionInfo.exitCode" -o tsv)
echo "Task finished with exit code: $EXIT_CODE"

# ==============================
# DOWNLOAD OUTPUT FROM BLOB
# ==============================
echo "Downloading output file from Azure Blob..."
az storage blob download \
  --account-name "$storage_account" \
  --account-key "$storage_key" \
  --container-name "$OUTPUT_CONTAINER_NAME" \
  --name "$OUTPUT_FILE_NAME" \
  --file "$LOCAL_OUTPUT_FILE"

echo "Output file saved as: $LOCAL_OUTPUT_FILE"
