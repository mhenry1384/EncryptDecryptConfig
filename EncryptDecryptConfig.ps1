# Script to encrypt and decrypt sections in web.config and app.configs.
# If you don't specify a configsection, the default is the connectionStrings section.
# You can specify encrypt or decrypt.  If you don't specify either, it will tell you if the sections are encrypted or decrypted.
#Requires -RunAsAdministrator
# Need to be an admin to open the RSA key container

param (
    [string]$filepath = $(throw "-filepath is required."),
    [string]$configsection = "connectionStrings",    
    [switch]$encrypt = $false,
	[switch]$decrypt = $false
)
$ErrorActionPreference = "Stop"

if ($encrypt -and $decrypt) 
{
	echo "Cannot specify both encrypt and decrypt"
	exit -1
}

if (!(Test-Path $filepath))
{
	echo "File $filepath does not exist"
	exit -1
}
if (!(Test-Path $filepath -pathType leaf))
{
	echo "$filepath is not a file"
	exit -1
}
$filepath = Resolve-Path -Path $filepath

function Save($section, $configuration)
{
	$section.SectionInformation.ForceSave = [System.Boolean]::True
	$configuration.Save([System.Configuration.ConfigurationSaveMode]::Modified)
	Write-Host "Succeeded!"
}

# https://lookonmyworks.co.uk/2011/06/30/encrypting-external-config-sections-using-powershell/
#The System.Configuration assembly must be loaded
$configurationAssembly = "System.Configuration, Version=2.0.0.0, Culture=Neutral, PublicKeyToken=b03f5f7f11d50a3a"
[void] [Reflection.Assembly]::Load($configurationAssembly)
  
$configurationFileMap = New-Object -TypeName System.Configuration.ExeConfigurationFileMap
$configurationFileMap.ExeConfigFilename = $filepath
$configuration = [System.Configuration.ConfigurationManager]::OpenMappedExeConfiguration($configurationFileMap, [System.Configuration.ConfigurationUserLevel]"None")
$section = $configuration.GetSection($configsection)

if ($encrypt) 
{
	if ($section.SectionInformation.IsProtected)
	{
		echo "Section $configsection already encrypted in $filepath. Nothing to do."
	}
	else
	{
		Write-Host "Encrypting $configsection in $filepath..."
		$section.SectionInformation.ProtectSection("RsaProtectedConfigurationProvider")
		Save $section $configuration
	}
}
elseif ($decrypt)
{
	if ($section.SectionInformation.IsProtected)
	{
		Write-Host "Decrypting $configsection in $filepath..."
		$section.SectionInformation.UnprotectSection()
		Save $section $configuration
	}
	else
	{
		echo "Section $configsection already decrypted in $filepath. Nothing to do."
	}
}
else
{
	if ($section.SectionInformation.IsProtected) 
	{
		"Section $configsection is encrypted in $filepath. Run this script with -decrypt to decrypt it."
	} 
	else {
		"Section $configsection is decrypted in $filepath. Run this script with -encrypt to decrypt it."
	}
}
