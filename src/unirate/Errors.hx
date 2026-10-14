package unirate;

/**
	Base error for every failure raised by the UniRate client.

	Catch this to handle the whole family at once, or narrow to a specific
	subclass (`AuthenticationError`, `InvalidCurrencyError`, ...). All
	subclasses extend `haxe.Exception`, so `e.message` is always available.
**/
class UniRateError extends haxe.Exception {}

/** 401 — missing or invalid API key. **/
class AuthenticationError extends UniRateError {}

/** 404 — currency/country not found or no data available. **/
class InvalidCurrencyError extends UniRateError {}

/** 400 — invalid request parameters (bad date, etc.). **/
class InvalidDateError extends UniRateError {}

/** 429 — rate limit exceeded. **/
class RateLimitError extends UniRateError {}

/**
	403 / 503 / any other non-2xx status. Carries the HTTP `status` and the
	raw response `body`.

	403 is the Pro-gate signal on the free tier (historical / timeseries /
	limits endpoints); 503 is service unavailable; anything else keeps the
	server's body in the message.
**/
class ApiError extends UniRateError {
	public final status:Int;
	public final body:String;

	public function new(status:Int, body:String) {
		final msg = switch status {
			case 403: "Endpoint requires a Pro subscription";
			case 503: "Service unavailable";
			case _: 'API error (status $status): $body';
		};
		super(msg);
		this.status = status;
		this.body = body;
	}
}
