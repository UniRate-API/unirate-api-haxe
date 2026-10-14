package unirate;

/**
	A single HTTP response: the status code and the raw response body.
**/
typedef HttpResponse = {
	var status:Int;
	var body:String;
}

/**
	A transport performs one `GET` request and returns the response.

	Signature: `(url, headers, timeoutSeconds) -> HttpResponse`.

	The default implementation (`UniRateClient.defaultTransport`) uses
	`haxe.Http`; tests inject their own transport to run entirely offline.
	A transport should throw a `UniRateError` for genuine network/transport
	failures (connection refused, timeout) and otherwise return whatever
	status + body the server produced — error-status mapping is the client's
	job, not the transport's.
**/
typedef Transport = (url:String, headers:Map<String, String>, timeout:Float) -> HttpResponse;
