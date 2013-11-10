package ufront.view;

import haxe.ds.StringMap;

/**
	A type representing a template that is ready to render a template with the given TemplateData.
	
	This is an abstract, and at runtime it will simply use the callback directly.

	It was designed this way to be flexible and integrate easily with existing templating systems.  

	For example, to use haxe's templating engine:
	
	```
	var tpl:UFTemplate = function (data) new haxe.Template( myTemplate ).execute( data.toObject() );
	tpl.execute([ 'name'=>'Jason', 'age'=>26, helper=>someHelper ]);
	```
**/
abstract UFTemplate( TemplateData->String ) from TemplateData->String to TemplateData->String {
	/** 
		Execute the template with the given data. 

		Notice that `data:TemplateData` is a trampoline type and can accept `haxe.ds.StringMap`, a `Dynamic` Object, or an `Iterable` combination of these.
	**/
	public inline function execute( data:TemplateData ):String return this(data);
}