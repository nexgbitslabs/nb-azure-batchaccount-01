
## Image gallery creation

Prerequisite: 
-	VM is created 
-	VM is deallocated
-	VM is generalized
Note: when creating VMs for generalization, [Standard Security Type] is the best and recommended option.

### What we are going to do 
Quick summary of the order:

    Create VM

    Install and configure all apps, dependencies, updates, etc.

    Test everything works as expected

    Run sudo waagent -deprovision+user -force (Linux) or sysprep (Windows)

    Deallocate and generalize the VM (az vm deallocate + az vm generalize)

    Capture the image or create the Shared Image Gallery version

### initiate the image creation process
1.	Run either locally or in azure cli
sudo waagent -deprovision+user


2.	Run these commands in Azure
### Deallocate the VM
```az vm deallocate --name <vm-name> --resource-group <rg>```

### Generalize the VM
```az vm generalize --name <vm-name> --resource-group <rg>```

### Create an image
az image create \
  --resource-group BatchAcc-RG01 \
  --name BatchAcc_IMG01 \
  --source NBTestBachAcc-VM01 \
 --location eastus \
 --hyper-v-generation V2

### Create an resource-group
az group create \
--name MyResourceGroup \
--location eastus

### Create an image-gallery
az sig create \
  --resource-group <your-resource-group> \
  --gallery-name <your-gallery-name> \
  --location <azure-region>	

### Create an image-gallery-definition
az sig image-definition create \
   --resource-group myGalleryRG \
   --gallery-name myGallery \
   --gallery-image-definition myImageDefinition \
   --publisher myPublisher \
   --offer myOffer \
   --sku mySKU \
   --os-type Linux \
   --os-state generalized

### create the image-gallery-image-version
az sig image-version create \
--resource-group $RGName \
--gallery-name $ImgGalleryName \
--gallery-image-definition $ImgGalleryDefinition \
--gallery-image-version 1.0.0 \
--target-regions "eastus=1=standard_zrs" \
--replica-count 1 \
--virtual-machine "/subscriptions/$subscription/resourceGroups/$resourcegroup$/providers/Microsoft.Compute/virtualMachines/$VM"


## Creating the Batch Account.
- Prerequisite: 
    * Register the subscription with the compute batch by running the command
        ```az provider register --namespace Microsoft.Batch```
    
    * Monitor using ```az provider show -n Microsoft.Batch```

#### Execute Terraform to create the Batch 
```terraform init --upgrade```

#### run Terrafomr plan
```terraform plan -out main.tfplan```

#### Apply the plan if all is good
```terraform apply main.tfplan```
