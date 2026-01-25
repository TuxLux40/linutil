@secure()
param extensions_enablevmaccess_username string

@secure()
param extensions_enablevmaccess_password string

@secure()
param extensions_enablevmaccess_ssh_key string

@secure()
param extensions_enablevmaccess_reset_ssh string

@secure()
param extensions_enablevmaccess_remove_user string

@secure()
param extensions_enablevmaccess_expiration string
param virtualMachines_LX_U1_name string = 'LX-U1'
param disks_LX_U1_OsDisk_1_50c0b0f09b94456eac7ce7f0ea8c1ec2_externalid string = '/subscriptions/122d2226-7d88-4450-a24a-6e3699e18f7e/resourceGroups/RG1/providers/Microsoft.Compute/disks/LX-U1_OsDisk_1_50c0b0f09b94456eac7ce7f0ea8c1ec2'
param networkInterfaces_lx_u1179_externalid string = '/subscriptions/122d2226-7d88-4450-a24a-6e3699e18f7e/resourceGroups/RG1/providers/Microsoft.Network/networkInterfaces/lx-u1179'

resource virtualMachines_LX_U1_name_resource 'Microsoft.Compute/virtualMachines@2024-11-01' = {
  name: virtualMachines_LX_U1_name
  location: 'germanywestcentral'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_D2ps_v5'
    }
    additionalCapabilities: {
      hibernationEnabled: false
    }
    storageProfile: {
      imageReference: {
        publisher: 'canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'ubuntu-pro-arm64'
        version: 'latest'
      }
      osDisk: {
        osType: 'Linux'
        name: '${virtualMachines_LX_U1_name}_OsDisk_1_50c0b0f09b94456eac7ce7f0ea8c1ec2'
        createOption: 'FromImage'
        caching: 'ReadWrite'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
          id: disks_LX_U1_OsDisk_1_50c0b0f09b94456eac7ce7f0ea8c1ec2_externalid
        }
        deleteOption: 'Delete'
        diskSizeGB: 32
      }
      dataDisks: []
      diskControllerType: 'SCSI'
    }
    osProfile: {
      computerName: virtualMachines_LX_U1_name
      adminUsername: 'azureuser'
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/azureuser/.ssh/authorized_keys'
              keyData: 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDPp4NjUpVS1VYqcECQrHO/aKMbQMd5/7GEubBTzRWts41fJzECh3e6UbKtK0mL1s+xy/+RCnneZ/FtgsVJJEGquz+ef1JPx2HdvCs7YzOKXwHU/gokey4g7QMIgap15rLgZ1mn9QFjTz0iK8AFM8sgWfWvPMeiOLW0efhdfjRXRuYV7jFWbC8rZS7Fb1fKbftfNRkfpPCZ8wuNE58trietj6rN5nDL3OTP6UdSVpQ64oZFTh9ux3B7qG89MJndQoRkoXceUz5h1ShoBLIzz6Ye1rQlvFOPUfWs+J38K0jJszvh4ErZfbEG4Mndpv0SA8hxXNN3N7AW/Ro2AfRUPQJZ openpgp:0x2F1170E8'
            }
          ]
        }
        provisionVMAgent: true
        patchSettings: {
          patchMode: 'ImageDefault'
          assessmentMode: 'ImageDefault'
        }
      }
      secrets: []
      allowExtensionOperations: true
      requireGuestProvisionSignal: true
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: networkInterfaces_lx_u1179_externalid
          properties: {
            deleteOption: 'Detach'
          }
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
    priority: 'Spot'
    evictionPolicy: 'Deallocate'
    billingProfile: {
      maxPrice: json('-1')
    }
  }
}

resource virtualMachines_LX_U1_name_enablevmaccess 'Microsoft.Compute/virtualMachines/extensions@2024-11-01' = {
  parent: virtualMachines_LX_U1_name_resource
  name: 'enablevmaccess'
  location: 'germanywestcentral'
  properties: {
    autoUpgradeMinorVersion: true
    publisher: 'Microsoft.OSTCExtensions'
    type: 'VMAccessForLinux'
    typeHandlerVersion: '1.5'
    settings: {}
    protectedSettings: {
      username: extensions_enablevmaccess_username
      password: extensions_enablevmaccess_password
      ssh_key: extensions_enablevmaccess_ssh_key
      reset_ssh: extensions_enablevmaccess_reset_ssh
      remove_user: extensions_enablevmaccess_remove_user
      expiration: extensions_enablevmaccess_expiration
    }
  }
}
