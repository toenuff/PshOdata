$schematemplate = @'
<?xml version="1.0" encoding="utf-8"?>
<ResourceMetadata xmlns="http://schemas.microsoft.com/powershell-web-services/2010/09">
  <SchemaNamespace>mosd</SchemaNamespace>
  <ContainerName>MyContainer</ContainerName>
  <Resources>
{0}
  </Resources>
  <ClassImplementations>
{1}
  </ClassImplementations>
</ResourceMetadata>
'@
$rbacconfigtemplate = @'
<?xml version="1.0" encoding="utf-8"?>
<RbacConfiguration>
<Groups><Group Name="UserGroup" MapIncomingUser="true"><Modules>
{0}</Modules></Group></Groups>
<Users DefaultGroup="UserGroup"></Users>
</RbacConfiguration>
'@

# Following is a list of parameternames to ignore when creating the parameterlist section in schema.xml
$paramignorelist = @('PipelineVariable','OutBuffer','OutVariable','WarningVariable','ErrorVariable','WarningAction',
                     'ErrorAction','Debug','Verbose')

function New-PshOdataClass {
	param(
		[Parameter(Mandatory=$true, Position=0)]
		[string] $Name,
		[Parameter(Mandatory=$true)]
		[string] $PK,
		[Parameter(Mandatory=$true)]
		[string[]] $Properties
	)
	$props = @()
	$props += $properties
	new-object psobject -property @{
		Name = $name
		PK = $PK
		Properties = $props
	}
}

function Set-PshOdataMethod {
	param(
		[Parameter(Mandatory=$true, ValueFromPipeline=$true)]
		[PSObject[]] $InputObject,
		[Parameter(Mandatory=$true)]
		[ValidateSet("GET","UPDATE","DELETE","CREATE")]
		[string] $Verb,
		[Parameter(Mandatory=$true)]
		[ValidateScript({(get-command $_).modulename})]
		[string] $Cmdlet,
		[Parameter(Mandatory=$false)]
		[alias("Params")]
		[string[]] $Parameters,
		[Parameter(Mandatory=$false)]
		[alias("FilterParams")]
		[string[]] $FilterParameters
	)
	PROCESS {
		$method = new-object psobject -Property @{
			Cmdlet = $cmdlet
			Module = 'c:\windows\system32\WindowsPowerShell\v1.0\Modules\{0}' -f (get-command $Cmdlet).Modulename
			Parameters = $Parameters
			FilterParameters = $FilterParameters
		}
		$InputObject |add-member -NotePropertyName $verb -NotePropertyValue $method -force
	}
}

function New-PshOdataEndpoint {
	param(
		[Parameter(Mandatory=$false, ValueFromPipeline=$true)]
		[PsObject[]] $OdataClasses,
		[Parameter(Mandatory=$false, position=0)]
		[string]$Path = "odata",
		[Switch]$Force
	)
	BEGIN {
		if ((Test-Path $Path) -and !$Force) {
			throw "Cannot create the endpoint because $Path already exists.  Either delete the contents or use the -Force parameter"
		}
        if (!(Test-Path $Path)) {
            mkdir $Path |out-null
        }
		$classes = @()
	}
	PROCESS {
		$classes += $OdataClasses
	}
	END {
		$mof = ""
        $modulestring = ""
        $resourcestring = ""
        $classstring = ""
		foreach ($class in $classes) {
			$mof += ConvertTo-MofText $class
            $resourcestring += ConvertTo-ResourceXML $class
            $classstring += ConvertTo-ClassXML $class
            $usedmodules = @()
            foreach ($verb in @('get','update','delete','create')) {
                if ($class.($verb)) {
                    if ($usedmodules -notcontains $class.($verb).module) {
                        $modules += "<Module>{0}</Module>`r`n" -f $class.($verb).module
                        $usedmodules += $class.($verb).module
                    }
                }
            }
		}
        $mof |out-file -Encoding ASCII (Join-Path $Path "schema.mof")
        $rbacconfigtemplate -f $modules |out-file -Encoding ASCII (Join-Path $Path "RbacConfiguration.xml")
        $schematemplate -f $resourcestring, $classstring |out-file -Encoding ASCII (Join-Path $path "schema.xml")
	}
}

# Helper functions - not exported
function ConvertTo-ResourceXML {
	param(
		[Parameter(Mandatory=$true, Position=0, ValueFromPipeline=$true)]
		[ValidateScript({$_.name})]
		[psobject] $class
	)
    $text = @'
        <Resource>
            <RelativeUrl>{0}</RelativeUrl>
            <Class>mosd_{0}</Class>
        </Resource>

'@
    $text -f $class.name
}

function ConvertTo-ClassXML{
	param(
		[Parameter(Mandatory=$true, Position=0, ValueFromPipeline=$true)]
		[ValidateScript({$_.name})]
		[psobject] $class
	)
    $text = @"
    <Class>
      <Name>mosd_$($class.name)</Name>
      <CmdletImplementation>

"@
    foreach ($verb in @('Get','Update','Delete','Create')) {
        if ($class.($verb)) {
            # odata uses <query> for the get section
            if ($verb -eq 'Get') {
                $section = 'Query'
            } else {
                $section = $verb
            }
            $text += " "*8 + "<{0}>`r`n" -f  $section
            $text += " "*10 + "<Cmdlet>{0}</Cmdlet>`r`n" -f  $class.($verb).Cmdlet
            $text += $verbtext -f $section, $class.($verb).Cmdlet

            # Add Parameters/Options section
            if ($class.($verb).Parameters) {
                $paramtext = " "*10 + "<Options>`r`n"
                foreach ($parameter in ($class.($verb).Parameters)) {
                    $paramtext += " "*12 + "<ParameterName>{0}</ParameterName>`r`n" -f $parameter
                }
                $text += $paramtext + " "*10 + "</Options>`r`n"
            }
            
            # Add Filter parameters/FieldParameterMap section
            if ($class.($verb).FilterParameters) {
                $paramtext = " "*10 + "<FieldParameterMap>`r`n"
                foreach ($parameter in ($class.($verb).FilterParameters)) {
                    $paramtext += " "*12 + "<Field>`r`n"
                    $paramtext += " "*14 + "<FieldName>{0}</FieldName>`r`n" -f $parameter
                    $paramtext += " "*14 + "<ParameterName>{0}</ParameterName>`r`n" -f $parameter
                    $paramtext += " "*12 + "</Field>`r`n"
                }
                $paramtext += " "*10 + "</FieldParameterMap>`r`n"
                $text += $paramtext
            }
            $allparams = $class.($verb).Parameters + $class.($verb).FilterParameters |select -Unique
            $text += Get-ParameterSetXML $class.($verb).cmdlet
            $text += " "*8 + "</$section>`r`n"
        }
    }
    $text += @"
      </CmdletImplementation>
    </Class>

"@
    $text
}

function ConvertTo-MofText {
	param(
		[Parameter(Mandatory=$true, Position=0, ValueFromPipeline=$true)]
		[ValidateScript({$_.name -and $_.pk -and $_.properties})]
		[psobject] $class
	)
	# We need to support a pk that may or may not be in the list of properties
	$text = @'
class mosd_{0}
{{
    [Key] String {1};

'@
	$text = $text -f $class.name, $class.pk
	foreach ($property in $class.properties) {
		if ($property -ne $class.pk) {
			$text += "    String $property;`r`n"
		}
	}
	$text += "};`r`n"
	$text
}

function Get-ParameterSetXML {
    param(
          [Parameter(Mandatory=$true, Position=0, ValueFromPipeline=$true)]
          [ValidateScript({get-command $_})]
          [String] $Cmdlet
    )
    $text = " "*10 + "<ParameterSets>`r`n"
    foreach ($parameterset in (get-command $cmdlet |select -ExpandProperty parametersets)) {
        $text += " "*12 + "<ParameterSet>`r`n"
        $text += " "*14 + "<Name>{0}</Name>`r`n" -f $parameterset.name
        foreach ($parameter in ($parameterset.Parameters)) {
            if ($paramignorelist -notcontains $parameter.name) {
                $text += " "*14 + "<Parameter>`r`n"
                $text += " "*16 + "<Name>{0}</Name>`r`n" -f $parameter.name
                if ($parameter.ParameterType.ToString() -eq 'System.Management.Automation.SwitchParameter') {
                    $text += " "*16 + "<Type>System.Management.Automation.SwitchParameter, System.Management.Automation, Version=3.0.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35</Type>`r`n"
                    $text += " "*16 + "<IsSwitch>True</IsSwitch>`r`n"
                } else {
                    $text += " "*16 + "<Type>System.String[], mscorlib, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089</Type>`r`n"
                }
                if ($parameter.IsMandatory) {
                    $text += " "*16 + "<IsMandatory>True</IsMandatory>`r`n"
                }
                $text += " "*14 + "</Parameter>`r`n"
            }
        }
        $text += " "*12 + "</ParameterSet>`r`n"
    }
    $text += " "*10 + "</ParameterSets>`r`n"
    $text
}
