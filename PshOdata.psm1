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
<#
 .Synopsis
 Creates a PowerShell representation of an Odata class

 .Description
 In order to create an odata endpoint, you must first create a class, add GET, UPDATE, CREATE, and/or DELETE
 methods for the class, and finally generate the odata files by creating the odata endpoint.

 New-PshOdataClass is used to create the odata class.  It specifies what properties are available.  This acts
 as a sort of Select-Object for the GET method that you will create for the class.

 .Parameter Name
 The name of the class.  This will be the name used in your odata url, e.g., http://server/odata/classname

 .Parameter PK
 Every odata endpoint must have a primary key.  This must be a unique identifier for the class.  If the cmdlet
 you are using does not have a unique value, you will need to wrap the cmdlet in another cmdlet that will add
 a primary key before you can create a get method for the class.

 .Parameter Properties
 This is the list of properties that will be available to the class.  This can be thought of as a Select-Object
 after your get- cmdlet.  Regardless of what your cmdlet returns, only the properties listed will be visible
 when viewing the objects for the class.

 .Inputs
 Strings

 .Outputs
 PSObject

 .Example
 The following is a class that can be used to represent a ProcessInfo object.  This class may be used with 
 a GET method that is returned by the Get-Process cmdlet.

 New-PshOdataClass Process -PK ID -Properties 'Name','ID'

 .LINK
 https://github.com/toenuff/PshOdata/

#>
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
<#
 .Synopsis
 This cmdlet adds a GET, DELETE, UPDATE, or CREATE method to the class

 .Description
 This cmdlet binds one of the HTTP verbs, i.e., GET, DELETE, UPDATE, or CREATE, to a cmdlet that is installed on the
 local system.  The cmdlet must be in a module in order for it to work.  The method will be added to a PshOdataClass
 PSObject that is created by New-PshOdataClass.

 .Parameter InputObject
 This is the class that you are setting the method for.  This is generally the object returned from New-PshOdataClass

 .Parameter Verb
 This is the HTTP verb for the method you are setting.  It must be either GET, DELETE, UPDATE, or CREATE. 
 
 Currently only GET and DELETE have been proven to work

 .Parameter Params
 This is only supported with the Get method.  It will allow you to pass a specific parameter to a cmdlet via the
 following syntax in the url:

 http://servername/odata/classname?paramname=value

 .Parameter FilterParams
 This is a special parameter that can be used with odata filters.  Filtering can be done with any property of the
 Odata class.  However, if you use a filter parameter, it will ensure that the filter is applied by calling the 
 associated cmdlet with the parametername specified.  This only works with the GET method.  
 
 This will allow you to use the following url:
 
 http://servername/odata/classname?$filter=(FilterParam eq 'value')
 This will call 
 cmdletname -FilterParam value

 Delete methods should have a FilterParam for the primary key specified in order for Delete to work.  If your
 cmdlet does not take the PK as a property, you will need to wrap the function in another cmdlet that will accept
 the PK.

 .Parameter Cmdlet
 This is the cmdlet that the method will invoke under the covers.  The cmdlet must be in a module in order for it to
 work.

 .Inputs
 PSObject

 .Outputs
 PSObject

 .Example
 The following will add a get method that uses get-process.  It will allow name and ID parameters, and it will
 allow Name to be used as a parameter if a filter is specified in the URL.

 $class |Set-PshOdataMethod -verb get -cmdlet get-process -Params Name, ID -FilterParams Name

 The above will allow the following urls:
 http://servername/odata/Process
 http://servername/odata/Process?Name=notepad
 http://servername/odata/Process?ID=3212

 .Example
 The following will create a delete method that runs stop-process:

 $class |Set-PshOdataMethod -verb delete -cmdlet stop-process -FilterParams ID

 The above will allow the delete verb to be passed to the following URL:
 http://servername/odata/Process('3333')

 .LINK
 https://github.com/toenuff/PshOdata/

#>
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
        if ($verb -eq 'delete') {
            # Delete only appears to work with the pk in the fieldparameterset.
            # It actually doesn't work with parameters at all
            if ($Parameters.count -gt 0 -or $FilterParameters.count -gt 1 -or $FilterParameters[0] -ne $InputObject.pk) {
                throw "DELETE methods can only use the primary key as a FieldParameter and they cannot use parameters.
                       Try Set-PshOdataMethod -verb DELETE -FilterParameters $($InputObject.pk)"
            }
        }
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
<#
 .Synopsis
 Creates an odata endpoint from a collection of defined Odata class objects with methods

 .Description
 This cmdlet is used in conjunction with New-PshOdataClass and Set-PshOdataMethod.  When New-PshOdataEndpoint is called,
 the following three files are created:

     Schema.mof - a document that describes the properties and PK for the classes in the endpoint.
     Schema.xml - a document that describes details about the methods and underlying PowerShell cmdlets that will be called through the endpoint.
     RbacConfiguration.xml - a document that describes which modules to load.  This set of cmdlets assumes that the underlying modules are
        located in c:\windows\system32\WindowsPowerShell\modules.

 These files need to be manually copied to the folder of an IIS server that is configured with an application that is using the Odata IIS extensions.
 An IISreset is also required.

 .Parameter Path
 The folder where you would like to save the schema.mof, schema.xml, and RbacConfiguration.xml files too. This defaults to an odata folder in
 the current working directory

 .Parameter PshOdataClasses
 A collection of PshOdata classes with methods that are set for the classes.  This generally comes from the output of New-PshOdataClass and
 Set-PshOdataMethod.

 .Parameter Force
 This is used to overwrite the output files if they already exist.
 
 .Inputs
 PSObject

 .Outputs
 Three files: Schema.mof, Schema.xml, and RbaConfiguration 

 .Example
 $class = New-PshOdataClass Process -PK ID -Properties 'Name','ID'
 $class |Set-PshOdataMethod -verb get -cmdlet get-process -Params Name, ID -FilterParams Name
 $class |Set-PshOdataMethod -verb delete -cmdlet stop-process -FilterParams ID
 $class | New-PshOdataEndpoint

 The above will create the files required to allow GET and SET http methods to a url like this:
  http://server/odata/Process
  http://server/odata/Process('3333') # 3333 is the ID of the process you would like to retrieve.  This is the only url that works for delete.
  http://server/odata/Process?name=notepad
  http://server/odata/Process?$filter=(name eq 'notepad')
  http://server/odata/Process?$format=application/json;odata=verbose #Used to render JSON instead of XML

 The endpoint will return Process objects that contain Name and ID Properties that are taken from Get-Process.  It will also allow the DELETE
 method to call Stop-Process when the PK is used.

 .Example
 The following creates the files required for an Odata Endpoint that serves Process and Service objects that are returned from Get-Process and Get-Service
 $classes = @()
 $classes += New-PshOdataClass Process -PK ID -Properties 'Name', 'ID' |Set-PshOdataMethod -verb get -cmdlet get-process -Params Name, ID -FilterParams Name
 $classes += New-PshOdataClass Service -PK Name -Properties 'Status', 'Name', 'Displayname' |Set-PshOdataMethod -verb get -cmdlet get-Service -Params Name -FilterParams Name
 $classes |New-PshOdataEndpoint

 .Example
 The following script will create the files required for an Odata endpoint directly into c:\inetpub\wwwroot\odata.  If the files exist already, 
 they will be overwritten.

 $class |New-PshOdataEndpoint -Path c:\inetpub\wwwroot\odata -Force

 .LINK
 https://github.com/toenuff/PshOdata/

#>
	param(
		[Parameter(Mandatory=$false, ValueFromPipeline=$true)]
		[PsObject[]] $PshOdataClasses,
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
		$classes += $PshOdataClasses
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
            
            $paramnames = (get-command $class.($verb).Cmdlet |select -ExpandProperty Parameters).keys
            # Add Filter parameters/FieldParameterMap section
            if ($class.($verb).FilterParameters) {
                $paramtext = " "*10 + "<FieldParameterMap>`r`n"
                foreach ($parameter in ($class.($verb).FilterParameters)) {
                    $targetparameter = $parameter
                    # FieldParameters are case sensitive on the target parameter
                    if ($paramnames -cnotcontains $parameter) {
                        if ($paramnames -contains $parameter) {
                            foreach ($name in $paramnames) {
                                if ($parameter -eq $name) {
                                    # Set it blank first otherwise it won't take the case change
                                    $targetparameter = $name
                                }
                            }
                        } else {
                            throw "{0} parameter does not exist in {1}" -f $parameter, $section, $class.($verb).Cmdlet
                        }
                    }
                    $paramtext += " "*12 + "<Field>`r`n"
                    $paramtext += " "*14 + "<FieldName>{0}</FieldName>`r`n" -f $parameter
                    $paramtext += " "*14 + "<ParameterName>{0}</ParameterName>`r`n" -f $targetparameter
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
