package ufront.handler;

import haxe.PosInfos;
import ufront.log.Message;
import ufront.web.DispatchController;
import ufront.web.Dispatch;
import ufront.web.HttpError;
import ufront.app.UFInitRequired;
import ufront.app.UFRequestHandler;
import haxe.web.Dispatch.DispatchConfig;
import haxe.web.Dispatch.DispatchError;
#if macro
	import haxe.macro.Expr;
#else
	import ufront.app.HttpApplication;
	import tink.CoreApi;
	import ufront.web.context.*;
	import ufront.web.session.UFHttpSession;
	import ufront.auth.*;
	import minject.Injector;
	import ufront.web.result.*;
	import ufront.web.context.*;
	import ufront.core.*;
#end

/**
	Uses `ufront.web.Dispatch` to match the URL to a controller action and it's parameters.

	@author Jason O'Neil
**/
class DispatchHandler implements UFRequestHandler implements UFInitRequired
{
	/** The Object (API, Routes or Controller) that Dispatch will check requests against. */
	public var dispatchConfig(default, null):DispatchConfig;

	/** The Dispatch object used **/
	public var dispatch(default, null):Dispatch;

	#if macro
		/**
			Set the routes to use for dispatching.

			This is a macro that takes the object (eg `new Routes()`) and compiles the dispatch information, and calls `loadRoutesConfig()`.
		**/
		macro public function loadRoutes( ethis:Expr, obj:ExprOf<{}> ):ExprOf<DispatchHandler> {
			var dispatchConf:Expr = ufront.web.Dispatch.makeConfig( obj );
			return macro $ethis.loadRoutesConfig( $dispatchConf );
		}
	#else
		/**
			An injector for things that should be available to DispatchHandler, your controllers, actions and results.

			This extends `HttpApplication.injector`, so all mappings available in the application injector will be available here.

			UfrontApplication also adds the following mappings by default:

			- A mapClass rule for every class that extends `ufront.web.Controller`
			- A mapSingleton rule for every class that extends `ufront.api.UFApi`

			We will create a child injector for each dispatch request that also maps a `ufront.web.context.HttpContext` instance and related auth, session, request and response values.
		**/
		public var injector(default,null):Injector;


		/**
			Set the routes to use for dispatching.

			This is a macro that takes the object (eg `new Routes()`) and compiles the dispatch information, and sets the `dispatchConfig` field on this DispatchHandler.
		**/
		public function loadRoutesConfig( dispatchConfig:DispatchConfig ) {
			this.dispatchConfig = dispatchConfig;
			return this;
		}

		/**
			Constructor

			Example usage:

			```
			var routes = new MyRoutes();
			var dispatchConfig = ufront.web.Dispatch.make( routes );
			var dispatchHandler = new DispatchHandler();
			dispatchHandler.loadRoutesConfig( dispatchConfig );
			```
		**/
		public function new() {
			injector = new Injector();
			injector.mapValue( Injector, injector );
		}

		public function init( application:HttpApplication ):Surprise<Noise,Error> {
			injector.parentInjector = application.injector;
			return Sync.success();
		}

		/** Disposes of the resources (other than memory) that are used by the module. */
		public function dispose( app:HttpApplication ):Surprise<Noise,Error> {
			dispatchConfig = null;
			dispatch = null;
			injector = null;
			return Sync.success();
		}

		/** Initializes a module and prepares it to handle requests. */
		public function handleRequest( ctx:HttpContext ):Surprise<Noise,Error> {
			if ( dispatchConfig==null )
				dispatchConfig = Dispatch.make( new DefaultRoutes() );

			switch processRequest( ctx ) {
				case Success(_):
					return
						executeAction( ctx ) >>
						function (r:Noise) return executeResult( ctx );
				case Failure(e):
					return Future.sync( Failure(e) );
			}
		}

		function processRequest( context:HttpContext ):Outcome<Noise,Error> {

			// Process the dispatch request
			try {
				var actionContext = context.actionContext;
				var filteredUri = context.getRequestUri();
				var params = context.request.params;
				dispatch = new Dispatch( filteredUri, params, context.request.httpMethod );

				// Listen for when the controller, action and args have been decided so we can set our "context" object up...
				dispatch.onProcessDispatchRequest.handle(function() {
					// Update the actionContext
					actionContext.handler = this;
					actionContext.controller = dispatch.controller;
					actionContext.action = dispatch.action;
					actionContext.args = dispatch.arguments;

					// Inject into our controller (if it already has been injected, no matter...)
					switch Type.typeof( dispatch.controller ) {
						case TClass( cl ):
							if ( Std.is(dispatch.controller, DispatchController) ) {
								// Set "context", which will do injection on the controller as well
								var c:DispatchController = cast dispatch.controller;
								if ( c.context==null )
									c.context = actionContext;
							}
							else {
								// Do normal injection
								context.injector.injectInto( dispatch.controller );
							}
						default:
					}
				});

				// Duplicate routes for each request, in case the object is cached.
				var newDispatchConfig = { obj:null, rules: dispatchConfig.rules };
				switch Type.typeof( dispatchConfig.obj ) {
					case TClass( cl ):
						newDispatchConfig.obj = context.injector.instantiate( cl );
					default:
				}

				dispatch.processDispatchRequest( newDispatchConfig );
				return Success( null );
			}
			catch ( e:DispatchError ) return Failure( dispatchErrorToHttpError(e) );
		}

		function executeAction( context:HttpContext ):Surprise<Noise,Error> {
			var t:FutureTrigger<Outcome<Noise,Error>> = Future.trigger();

			// Update the Dispatch details (in case a module/middleware changed them)
			dispatch.controller = context.actionContext.controller;
			dispatch.action = context.actionContext.action;
			dispatch.arguments = context.actionContext.args;

			// Execute the result
			try {
				// TODO - make this async...
				var result = dispatch.executeDispatchRequest();
				context.actionContext.actionResult = createActionResult( result );
				t.trigger( Success(Noise) );
			}
			catch ( e:DispatchError ) {
				var p = HttpError.fakePosition( context.actionContext.controller, context.actionContext.action, context.actionContext.args );
				#if debug context.ufError( 'Caught dispatch error in DispatchHandler.executeAction while executing ${p.className}.${p.methodName}(${p.customParams.join(",")})' ); #end
				t.trigger( Failure(dispatchErrorToHttpError(e,p)) );
			}
			catch ( e:Dynamic ) {
				// Fake the position the error came from...
				var p = HttpError.fakePosition( context.actionContext.controller, context.actionContext.action, context.actionContext.args );
				#if debug context.ufError( 'Caught unknown error in DispatchHandler.executeAction while executing ${p.className}.${p.methodName}(${p.customParams.join(",")})' ); #end
				t.trigger( Failure(HttpError.wrap(e,p)) );
			}

			return t.asFuture();
		}

		function executeResult( context:HttpContext ):Surprise<Noise,Error> {
			return
				try
					context.actionContext.actionResult.executeResult( context.actionContext )
				catch ( e:Dynamic ) {
					var p = HttpError.fakePosition( context.actionContext, "executeResult", ["actionContext"] );
					#if debug context.ufError( 'Caught error in DispatchHandler.executeAction while executing ${p.className}.${p.methodName}(${p.customParams.join(",")})' ); #end
					Future.sync( Failure(HttpError.wrap(e)) );
				}
		}

		function dispatchErrorToHttpError( e:DispatchError, ?p:PosInfos ):Error {
			return switch ( e ) {
				case DENotFound( part ): HttpError.pageNotFound( p );
				case DEInvalidValue: HttpError.badRequest( p );
				case DEMissing: HttpError.pageNotFound( p );
				case DEMissingParam( _ ): HttpError.badRequest( p );
				case DETooManyValues: HttpError.pageNotFound( p );
			}
		}

		public static function createActionResult( returnValue:Dynamic ):ActionResult {
			if ( returnValue==null ) {
				return new EmptyResult();
			}
			else {
				var actionReturnValue = Std.instance( returnValue, ActionResult );
				if ( actionReturnValue==null ) {
					actionReturnValue = new ContentResult( Std.string(returnValue), "text/html" );
				}
				return actionReturnValue;
			}
		}
	#end

	public function toString() return "ufront.handler.DispatchHandler";
}

class DefaultRoutes extends ufront.web.DispatchController {
	static var _emptyUfrontString = CompileTime.readFile( "ufront/web/DefaultPage.html" );
	function doDefault( d:Dispatch ) {
		ufTrace("Your Ufront App is almost ready.");
		return _emptyUfrontString;
	}
}
