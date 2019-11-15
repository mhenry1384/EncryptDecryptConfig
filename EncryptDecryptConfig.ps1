# This script checked into $\Shared Tools\PowerShell in the deployment branch.

# Script to encrypt and decrypt sections in web.config and app.configs.
# This works even for partial config files.
# If you don't specify a configsection, the default is the connectionStrings section.
# You can specify encrypt or decrypt.  If you don't specify either, it will tell you if the sections are encrypted or decrypted.
#Requires -RunAsAdministrator
# Need to be an admin to open the RSA key container

param (
    [string]$filepath = $(throw "-filepath is required; if filepath is a folder, it will operate on all config files in the folder."),
    [string]$configsection = "connectionStrings", # If it's a partial config file, this is ignored and we just encrypt/decrypt the root node.
    [switch]$encrypt = $false,
	[switch]$decrypt = $false
)
$ErrorActionPreference = "Stop"

function Save($section, $configuration)
{
	$section.SectionInformation.ForceSave = [System.Boolean]::True
	$configuration.Save([System.Configuration.ConfigurationSaveMode]::Modified)
	Write-Host "Succeeded!"
}

function GetConfiguration($filepath)
{
	$configurationFileMap = New-Object -TypeName System.Configuration.ExeConfigurationFileMap
	$configurationFileMap.ExeConfigFilename = $filepath
	return [System.Configuration.ConfigurationManager]::OpenMappedExeConfiguration($configurationFileMap, [System.Configuration.ConfigurationUserLevel]"None")
}

function UnwrapFileWithRootConfiguration($filepath)
{
	$text = (Get-Content $filepath -Raw)
	$text -match "(?si)(.*)<configuration>(.*?)[`r`n ]*</configuration>" | Out-Null
	$filepath = $filepath -replace ".wrapped", ""
	$text = "$($matches[1])$($matches[2])" -replace "               </", "</"
	$text | Out-File -FilePath $filepath -Encoding UTF8
}

function WrapXmlWithRootConfiguration($filepath)
{
	$filepathWrapped = "$filepath.wrapped"
	$text = (Get-Content $filepath -Raw)
	$text -match "(?si)(<\?[^?]*\?>`r?`n?)?(.+)" | Out-Null
	"$($matches[1])<configuration>$($matches[2])</configuration>" | Out-File -FilePath "$filepath.wrapped" -Encoding UTF8
	return $filepathWrapped
}

function BackupFile($filepath)
{
	$increment = 1
	while ($true)
	{
		$backupPath = "$filepath.bak$increment"
		if (Test-Path $backupPath)
		{
			$increment++
			if ($increment -gt 1000)
			{
				throw "Unable to backup file $filepath"
			}
		}
		else
		{
			Copy-Item $filepath -Destination $backupPath
			return
		}
	}
}
function GetRootNodeOfPartialConfigFile($filepath)
{
	$text = (Get-Content $filepath -Raw)
	$text -match "(?si)(<\?[^?]*\?>`r?`n?)?<(.+?)(\s|>)" | Out-Null
	return $matches[2]
}

function EncryptDecryptSectionOfFile($filepath)
{
	echo $filepath
	# https://lookonmyworks.co.uk/2011/06/30/encrypting-external-config-sections-using-powershell/
	#The System.Configuration assembly must be loaded
	$configurationAssembly = "System.Configuration, Version=2.0.0.0, Culture=Neutral, PublicKeyToken=b03f5f7f11d50a3a"
	[void] [Reflection.Assembly]::Load($configurationAssembly)
	$filepathWrapped = $null
	$configuration = $null
	# We ignore the config section for partial configs and just look at the root.
	$configSectionThisFile = $configsection
	try
	{
		$configuration = GetConfiguration $filepath
	}
	catch
	{
		if ($_.Exception.Message -Match "does not have root <configuration> tag")
		{
			$filepathWrapped = WrapXmlWithRootConfiguration $filepath
			$configuration = GetConfiguration $filepathWrapped
			$configSectionThisFile = (GetRootNodeOfPartialConfigFile $filepath)
		}
		else
		{
			throw
		}
	}
	$section = $configuration.GetSection($configSectionThisFile)

	if ($encrypt) 
	{
		if ($section.SectionInformation.IsProtected)
		{
			echo "Section $configSectionThisFile already encrypted in $filepath. Nothing to do."
		}
		else
		{
			Write-Host "Encrypting $configSectionThisFile in $filepath..."
			$section.SectionInformation.ProtectSection("RsaProtectedConfigurationProvider")
			BackupFile $filepath
			Save $section $configuration
		}
	}
	elseif ($decrypt)
	{
		if ($section.SectionInformation.IsProtected)
		{
			Write-Host "Decrypting $configSectionThisFile in $filepath..."
			$section.SectionInformation.UnprotectSection()
			BackupFile $filepath
			Save $section $configuration
		}
		else
		{
			echo "Section $configSectionThisFile already decrypted in $filepath. Nothing to do."
		}
	}
	else
	{
		if ($section.SectionInformation.IsProtected) 
		{
			"Section $configSectionThisFile is encrypted in $filepath. Run this script with -decrypt to decrypt it."
		} 
		else {
			"Section $configSectionThisFile is decrypted in $filepath. Run this script with -encrypt to decrypt it."
		}
	}

	if ($filepathWrapped)
	{
		UnwrapFileWithRootConfiguration $filepathWrapped
		Remove-Item $filepathWrapped
	}
}

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
if (Test-Path $filepath -pathType leaf)
{
	EncryptDecryptSectionOfFile Resolve-Path -Path $filepath
}
else
{
	Get-ChildItem -Path $filepath -Filter "*.config" | % {EncryptDecryptSectionOfFile $_.FullName}
}
