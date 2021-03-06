package ufront.web;

import thx.core.error.NullArgument;

/**
	A class describing a Http Cookie.

	This does not actually set a cookie.  Use `setCookie()` on a `HttpResponse` object to set the cookie.

	TODO: document further.

	@author Franco Ponticelli
**/
class HttpCookie {
	/** The domain this cookie applies to. **/
	public var domain:String;
	
	/** The date this cookie will expire. If `null`, then the cookie will not include an expiry date. **/
	public var expires:Null<Date>;
	
	/** The name of the cookie, used to access it in future requests: `request.cookies[name]`. **/
	public var name:String;
	
	/** The path on the server this cookie applies to. **/
	public var path:String;
	
	/** Whether or not this cookie is marked as `secure`. Default is false. **/
	public var secure:Bool;
	
	/** Whether or not this cookie is for http only (not available on client JS etc). Default is false. **/
	public var httpOnly:Bool;
	
	/** The value to store in the cookie. **/
	public var value(default, set):String;
	
	/** The cookie string used to send to the client. **/
	public var description(get, never):String;

	public function new( name:String, value:String, ?expires:Date, ?domain:String, ?path:String, ?secure:Bool=false, ?httpOnly:Bool=false ) {
		this.name = name;
		this.value = value;
		this.expires = expires;
		this.domain = domain;
		this.path = path;
		this.secure = secure;
		this.httpOnly = httpOnly;
	}

	/** Cause the cookie to expire with this request, by setting the date to a time in the past. **/
	public function expireNow():Void {
		this.expires = Date.fromTime( 0 );
	}

	public function toString() {
		return '$name: $description';
	}

	function setName( v:String ) {
		NullArgument.throwIfNull( v );
		return name = v;
	}

	function set_value( v:String ) {
		NullArgument.throwIfNull( v );
		return value = v;
	}

	static var dayNames = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"];
	static var monthNames = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];
	static var tzOffset:Null<Float>;
	
	function get_description() {
		var buf = new StringBuf();
		buf.add(value);
		if ( expires!=null ) {
			// Figure out the timezone offset of the local server, our expiry date needs to be GMT.
			if ( tzOffset==null ) {
				tzOffset = 
					#if php untyped __php__("intval(date('Z', $this->expires->__t));");
					#else Date.fromString( "1970-01-01 00:00:00" ).getTime();
					#end
			}
			var gmtExpires = DateTools.delta( expires, tzOffset );
			
			// We need to pad out some ints in our date formatting.
			function zeroPad( i:Int ) {
				var str = '$i';
				while ( str.length < 2 )
					str = "0"+str;
				return str;
			}
			
			// Format is 'DAY, DD-MMM-YYYY HH:MM:SS GMT'. 
			// See http://msdn.microsoft.com/en-us/library/windows/desktop/aa384321%28v=vs.85%29.aspx
			var day = dayNames[gmtExpires.getDay()];
			var date = zeroPad( gmtExpires.getDate() );
			var month = monthNames[gmtExpires.getMonth()];
			var year = gmtExpires.getFullYear();
			var hour = zeroPad( gmtExpires.getHours() );
			var minute = zeroPad( gmtExpires.getMinutes() );
			var second = zeroPad( gmtExpires.getSeconds() );
			var dateStr = '$day, $date-$month-$year $hour:$minute:$second GMT';
			addPair( buf, "expires", dateStr );
		}
		addPair( buf, "domain", domain );
		addPair( buf, "path", path );
		if ( secure )
			addPair( buf, "secure", true );
		return buf.toString();
	}

	static function addPair( buf:StringBuf, name:String, ?value:String, ?allowNullValue:Bool=false ) {
		if ( !allowNullValue && null==value )
			return;
		buf.add( "; " );
		buf.add( name );
		if ( null==value )
			return;
		buf.add( "=" );
		buf.add( value );
	}
}
