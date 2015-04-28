param(
    [string][Parameter(Mandatory=$true)]$ConnectedServiceName, 
    [string][Parameter(Mandatory=$true)]$location,
    [string][Parameter(Mandatory=$true)]$resourceGroupName,
    [string][Parameter(Mandatory=$true)]$csmFile, 
    [string]$csmParametersFile,
    [string]$dscDeployment,
    [string]$moduleUrlParameterName,
    [string]$sasTokenParameterName
)

. ./AzureResourceManagerHelper.ps1
. ./DtlServiceHelper.ps1
. ./Utilities.ps1

$ErrorActionPreference = "Stop"

Write-Host "******************************************************************************"
Write-Host "Starting Azure Resource Group Deployment Task"

Write-Verbose -Verbose "SubscriptionId = $ConnectedServiceName"
Write-Verbose -Verbose "environmentName = $resourceGroupName"
Write-Verbose -Verbose "location = $location"
Write-Verbose -Verbose "deplyomentDefinitionFile = $csmFile"
Write-Verbose -Verbose "deploymentDefinitionParametersFile = $csmParametersFile"
Write-Verbose -Verbose "moduleUrlParameterName = $moduleUrlParameterName"
Write-Verbose -Verbose "sasTokenParamterName = $sasTokenParameterName"

import-module Microsoft.TeamFoundation.DistributedTask.Task.DevTestLabs
import-module Microsoft.TeamFoundation.DistributedTask.Task.Common

Validate-DeploymentFileAndParameters -csmFile $csmFile -csmParametersFile $csmParametersFile

$csmFileName = [System.IO.Path]::GetFileNameWithoutExtension($csmFile)
$csmFileContent = [System.IO.File]::ReadAllText($csmFile)

if(Test-Path -Path $csmParametersFile -PathType Leaf)
{
    $csmParametersFileContent = [System.IO.File]::ReadAllText($csmParametersFile)
}

Check-EnvironmentNameAvailability -environmentName $resourceGroupName

$parametersObject = Get-CsmParameterObject -csmParameterFileContent $csmParametersFileContent
$parametersObject = Refresh-SASToken -moduleUrlParameterName $moduleUrlParameterName -sasTokenParameterName $sasTokenParameterName -csmParametersObject $parametersObject -subscriptionId $ConnectedServiceName -dscDeployment $dscDeployment

Switch-AzureMode AzureResourceManager

$subscription = Get-SubscriptionInformation -subscriptionId $ConnectedServiceName

$resourceGroupDeployment = Create-AzureResourceGroup -csmFile $csmFile -csmParametersObject $parametersObject -resourceGroupName $resourceGroupName -location $location

Initialize-DTLServiceHelper

$provider = Create-Provider -providerName "AzureResourceGroupManagerV2" -providerType "Microsoft Azure Compute Resource Provider"

$providerData = Create-ProviderData -providerName $provider.Name -providerDataName $subscription.SubscriptionName -providerDataType $subscription.Environment -subscriptionId $subscription.SubscriptionId

$environmentDefinitionName = [System.String]::Format("{0}_{1}", $csmFileName, $env:BUILD_BUILDNUMBER)

$environmentDefinition = Create-EnvironmentDefinition -environmentDefinitionName $environmentDefinitionName -providerName $provider.Name

$providerDataNames = New-Object System.Collections.Generic.List[string]
$providerDataNames.Add($providerData.Name)

$environmentResources = Get-Resources -resourceGroupName $resourceGroupName

$environment = Create-Environment -environmentName $resourceGroupName -environmentType "Azure CSM V2" -environmentStatus $resourceGroupDeployment.ProvisioningState -providerName $provider.Name -providerDataNames $providerDataNames -environmentDefinitionName $environmentDefinition.Name -resources $environmentResources

$environmentOperationId = Create-EnvironmentOperation -environment $environment

if($deploymentError)
{
    Throw "Deploy Azure Resource Group Task failed. View logs for details"
}

Write-Host "Completing Azure Resource Group Deployment Task"
Write-Host "******************************************************************************"
