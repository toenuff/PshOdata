$here = (Split-Path (Split-Path -Parent $MyInvocation.MyCommand.Path))

Invoke-Expression (gc "$here\odata.psm1" |out-String)

$class = New-OdataClass Process -PK ID -Properties 'Name','ID'

Describe "New-OdataClass" {
    It "Returns a psobject with the provided name" {
        $class.name | Should Be "Process"
    }
	It "Returns a psobject with the provided PK" {
		$class.pk | Should Be "ID"
	}
	It "Returns a psobject with two properties" {
		$class.properties.count |Should Be 2
	}
	It "New-OdataClass with only one property should return a list with one element in it" {
		(New-OdataClass TestClass -PK ID -Properties 'ID').properties.count |Should Be 1
	}
}

Describe "Add-OdataMethod" {
	It "Validate that optional parameters are optional" {
		{$class |set-odatamethod -verb get -cmdlet get-process} |should not Throw
	}
	It "Creates a GET method" {
		{$class |set-odatamethod -verb get -cmdlet get-process -Params Name, ID -FilterParams Name} |should not Throw
	}
	It "Sets the get property of the class" {
		$class.get |should not BeNullOrEmpty
	}
	It "Validates the get property's module property" {
		$class.get.module |Should be "c:\windows\system32\WindowsPowerShell\v1.0\Modules\Microsoft.PowerShell.Management"
	}
	It "Should not set the update property of the class when only the get method was added" {
		$class.update|should BeNullOrEmpty
	}
	It "Creates a DELETE method" {
		$class |set-odatamethod -verb delete -cmdlet stop-process -FilterParams ID -params ID
	}
	It "Fails if verb is not valid" {
		{$class |set-odatamethod -verb blah -cmdlet dir -pk ID -Params Name, ID -FilterParams Name} |should Throw
	}
	It "Fails if cmdlet is not valid" {
		{$class |set-odatamethod -verb get -cmdlet dir -pk ID -Params Name, ID -FilterParams Name} |should Throw
	}
}

Describe "ConvertTo-MofText" {
	It "Converts a class to the text required in a Mof file" {
		$class |ConvertTo-MofText |Should be @'
class mosd_Process
{
    [Key] String ID;
    String Name;
};

'@
	}
}

Describe "ConvertTo-ResourceXML" {
    It "Converts a class to the text needed in the resource section of the schema.xml" {
        $class |ConvertTo-ResourceXML |Should be @'
        <Resource>
            <RelativeUrl>Process</RelativeUrl>
            <Class>mosd_Process</Class>
        </Resource>

'@
    }
}

Describe "ConvertTo-ClassXML" {
    It "Converts a class to the text needed in the class section of the schema.xml" {
        $class |ConvertTo-ClassXML |Should be @'
    <Class>
      <Name>mosd_Process</Name>
      <CmdletImplementation>
        <Query>
          <Cmdlet>get-process</Cmdlet>
          <Options>
            <ParameterName>Name</ParameterName>
            <ParameterName>ID</ParameterName>
          </Options>
          <FieldParameterMap>
            <Field>
              <FieldName>Name</FieldName>
              <ParameterName>Name</ParameterName>
            </Field>
          </FieldParameterMap>
          <ParameterSets>
            <ParameterSet>
              <Name>Default</Name>
              <Parameter>
                <Name>Name</Name>
                <Type>System.String[], mscorlib, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089</Type>
              </Parameter>
              <Parameter>
                <Name>ID</Name>
                <Type>System.String[], mscorlib, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089</Type>
              </Parameter>
            </ParameterSet>
          </ParameterSets>
        </Query>
        <Delete>
          <Cmdlet>stop-process</Cmdlet>
          <Options>
            <ParameterName>ID</ParameterName>
          </Options>
          <FieldParameterMap>
            <Field>
              <FieldName>ID</FieldName>
              <ParameterName>ID</ParameterName>
            </Field>
          </FieldParameterMap>
          <ParameterSets>
            <ParameterSet>
              <Name>Default</Name>
              <Parameter>
                <Name>ID</Name>
                <Type>System.String[], mscorlib, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089</Type>
              </Parameter>
            </ParameterSet>
          </ParameterSets>
        </Delete>
      </CmdletImplementation>
    </Class>

'@
    }
}

Describe "New-OdataEndpoint" {
	It "New-OdataEndpoint succeeds if the folder exists and the -Force switch is used" {
		{$class |New-OdataEndpoint} |Should Not Throw
	}
	It "New-OdataEndpoint should fail if the folder exists" {
		{$class |New-OdataEndpoint} |Should Throw
	}
	It "New-OdataEndpoint succeeds if the folder exists and the -Force switch is used" {
		{$class |New-OdataEndpoint -Force} |Should Not Throw
	}
    It "Should create schema.mof" {
        join-path odata schema.mof |Should exist
    }
    It "Should create schema.xml" {
        join-path odata schema.xml |Should exist
    }
    It "Should create RbacConfiguration.xml" {
        join-path odata RbacConfiguration.xml |Should exist
    }
    It "Validate data in RbacConfiguration.xml" {
        [IO.file]::ReadAllText((join-path odata RbacConfiguration.xml)) |Should be @"
<?xml version="1.0" encoding="utf-8"?>
<RbacConfiguration>
<Groups><Group Name="UserGroup" MapIncomingUser="true"><Modules>
<Module>c:\windows\system32\WindowsPowerShell\v1.0\Modules\Microsoft.PowerShell.Management</Module>
</Modules></Group></Groups>
<Users DefaultGroup="UserGroup"></Users>
</RbacConfiguration>

"@
    }
}

# cleanup the directory created during the tests
rm (join-path $here odata) -recurse

#TODO consider moving validation text into validator files in the /tests directory
