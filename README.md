[![Build status](https://ci.appveyor.com/api/projects/status/72ohweyiaogj34po/branch/master?svg=true)](https://ci.appveyor.com/project/toenuff/pshodata)

# PshOdata Module

2008R2 and 2012 versions of Windows contain a feature called IIS Odata Extensions.  An IIS application that uses the extensions can be configured to create a RESTful web service that will run PowerShell cmdlets and return the objects as either JSON or XML.  The PshOdata Module makes it easy to generate the files used to create these endpoints.

## Example Usage
````
$class = New-PshOdataClass Process -PK ID -Properties 'Name','ID'
$class |Add-PshOdataMethod -verb get -cmdlet get-process -Params Name, ID -FilterParams Name
$class |Add-PshOdataMethod -verb delete -cmdlet stop-process -FilterParams ID
$class |New-PshOdataEndpoint
````

The above will create the files required to allow GET and SET http methods to a url like this:
* http://server/odata/Process
* http://server/odata/Process('3333') # 3333 is the ID of the process you would like to retrieve.  This is the only url that works for delete.
* http://server/odata/Process?name=notepad
* http://server/odata/Process?$filter=(name eq 'notepad')
* http://server/odata/Process?$format=application/json;odata=verbose #Used to render JSON instead of XML

The endpoint will return Process objects that contain Name and ID Properties that are taken from Get-Process.  It will also allow the DELETE
method to call Stop-Process when the PK is used.

## Files Generated

The New-PshOdataEndpoint function will create a set of files in an odata folder within the current working directory by default.

The following files are generated:
* Schema.mof - a document that describes the properties and PK for the classes in the endpoint.
* Schema.xml - a document that describes details about the methods and underlying PowerShell cmdlets that will be called through the endpoint.
* RbacConfiguration.xml - a document that describes which modules to load.  This set of cmdlets assumes that the underlying modules are located in c:\windows\system32\WindowsPowerShell\modules.

## Installation of the files

Currently, we do not have a method to create the IIS portion of the Odata extensions.  We plan on solving this with a function soon.  However, in the meantime, you can use the OdataSchemaDesigner in order to have your first endpoint created, and then you can use these cmdlets to generate the files you need for your Odata service.

The following steps must be performed on Windows Server 2012 box that does NOT have R2.

1. Add-WindowsFeature ManagementOdata # Install the odata extensions
1. Install Visual Studio Isolated Shell - http://www.microsoft.com/en-us/download/details.aspx?id=1366
1. Install the odata extension isolated installer - http://archive.msdn.microsoft.com/mgmtODataWebServ/Release/ProjectReleases.aspx?ReleaseId=5877
1. Launch the Management Odata Schema Designer from the start screen
   1. File-> New File -> Management Odata Model
   1. Right-Click and select Import Cmdlets
   1. Local Computer -> Next
   1. Installed Windows PowerShell Modules -> Microsoft.PowerShell.Management
   1. Choose Service -> Next
   1. Uncheck CREATE and UPDATE.  Only Get should be selected. Next.
   1. Next
   1. Choose any key and click Next.
   1. Next
   1. Finish
   1. Right click in the designer and choose Publish Odata Endpoint
   1. Select the local computername and fill out a username and password.  Choose a name for the site (odata is a good choice).  Finally select a port number and then click Publish.

Once the IIS server has the site created.  You can use the cmdlets in this module to generate the schema.xml, schema.mof, and rbacconfiguration.xml files.  Copy these files into the application you created (c:\inetpub\wwwroot\odata).  Perform an IISReset.  Enjoy your web service.

## Notes

* Currently only GET and DELETE is supported
* Use *Get-Command -Module PshOdata* in order to see the cmdlets in the module
* Use *Get-Help cmdletname -full* in order to see the full set of documenation along with examples you can try
* Odata classes require a primary key.  This needs to be a unique value for each object returned.  If one does not exist for the data you are retrieving from PowerShell, you will need to create a wrapper function in a new module that calls your function and creates a primary key.  You can then create a method based on this new cmdlet.
* When creating a DELETE method, you may only use the PK as a parameter.  Your delete cmdlet must support this.
