package unirate;

import haxe.Json;
import unirate.Errors;
import unirate.Models;
import unirate.Transport;

/**
	Client for the [UniRate API](https://unirateapi.com).

	Construct it with an API key, then call any of the nine public methods.
	It depends only on the Haxe standard library (`haxe.Http` for HTTP and
	`haxe.Json` for decoding) — zero third-party dependencies.

	```haxe
	var client = new unirate.UniRateClient("your-api-key");
	var rate = client.getRate("USD", "EUR");        // 0.92
	var eur = client.convert(100, "USD", "EUR");    // 92.5
	var codes = client.getSupportedCurrencies();    // ["USD", "EUR", ...]
	```

	The HTTP layer is injectable (see `Transport`) so tests can run offline.
**/
class UniRateClient {
	/** Client version — kept in sync with `haxelib.json`. **/
	public static final VERSION = "0.1.0";

	/** Default base URL for the UniRate API. **/
	public static final DEFAULT_BASE_URL = "https://api.unirateapi.com";

	/** Default request timeout, in seconds. **/
	public static final DEFAULT_TIMEOUT:Float = 30;

	final apiKey:String;
	final baseUrl:String;
	final timeout:Float;
	final userAgent:String;
	final transport:Transport;

	/**
		Create a client.

		@param apiKey    API key from [unirateapi.com](https://unirateapi.com)
		@param baseUrl   base URL; defaults to `DEFAULT_BASE_URL`
		@param timeout   request timeout in seconds; defaults to 30
		@param transport HTTP transport; defaults to `defaultTransport`
	**/
	public function new(apiKey:String, ?baseUrl:String, ?timeout:Float, ?transport:Transport) {
		if (apiKey == null)
			throw new UniRateError("apiKey is required");
		this.apiKey = apiKey;
		this.baseUrl = stripTrailingSlash(baseUrl == null ? DEFAULT_BASE_URL : baseUrl);
		this.timeout = timeout == null ? DEFAULT_TIMEOUT : timeout;
		this.userAgent = "unirate-haxe/" + VERSION;
		this.transport = transport == null ? defaultTransport : transport;
	}

	// ---------------------------------------------------------------
	// Current rates and conversion
	// ---------------------------------------------------------------

	/**
		Current exchange rate from `from` to `to` (how many `to` one `from`
		buys). Pass `null` for `from` to default to `"USD"`.
	**/
	public function getRate(from:String, to:String):Float {
		if (to == null)
			throw new UniRateError("to is required");
		final j = requestJson("/api/rates", [
			param("from", upper(from == null ? "USD" : from)),
			param("to", upper(to))
		]);
		return parseNumber(Reflect.field(j, "rate"), "rate");
	}

	/**
		All current exchange rates for a base currency, as a map of currency
		code to rate. Pass `null` for `from` to default to `"USD"`.
	**/
	public function getAllRates(?from:String):Map<String, Float> {
		final j = requestJson("/api/rates", [param("from", upper(from == null ? "USD" : from))]);
		return parseNumberMap(Reflect.field(j, "rates"), "rates");
	}

	/**
		Convert `amount` from `from` to `to` at the current rate. Pass `null`
		for `from` to default to `"USD"`.
	**/
	public function convert(amount:Float, from:String, to:String):Float {
		if (to == null)
			throw new UniRateError("to is required");
		final j = requestJson("/api/convert", [
			param("from", upper(from == null ? "USD" : from)),
			param("to", upper(to)),
			param("amount", formatAmount(amount))
		]);
		return parseNumber(Reflect.field(j, "result"), "result");
	}

	/** The list of supported currency codes. **/
	public function getSupportedCurrencies():Array<String> {
		final j = requestJson("/api/currencies", []);
		final arr:Array<Dynamic> = Reflect.field(j, "currencies");
		if (arr == null)
			throw new UniRateError("Malformed response: missing 'currencies' array");
		return [for (x in arr) Std.string(x)];
	}

	// ---------------------------------------------------------------
	// Historical data (Pro-gated: 403 on the free tier)
	// ---------------------------------------------------------------

	/**
		Historical exchange rate from `from` to `to` on `date` (`YYYY-MM-DD`).
		Pass `null` for `from` to default to `"USD"`. Pro-gated.
	**/
	public function getHistoricalRate(date:String, from:String, to:String):Float {
		if (date == null)
			throw new UniRateError("date is required");
		if (to == null)
			throw new UniRateError("to is required");
		final j = requestJson("/api/historical/rates", [
			param("date", date),
			param("amount", "1"),
			param("from", upper(from == null ? "USD" : from)),
			param("to", upper(to))
		]);
		return parseNumber(Reflect.field(j, "rate"), "rate");
	}

	/**
		All historical exchange rates for a base currency on `date`
		(`YYYY-MM-DD`). Pass `null` for `base` to default to `"USD"`.
		Pro-gated.
	**/
	public function getHistoricalRates(date:String, ?base:String):Map<String, Float> {
		if (date == null)
			throw new UniRateError("date is required");
		final j = requestJson("/api/historical/rates", [
			param("date", date),
			param("amount", "1"),
			param("from", upper(base == null ? "USD" : base))
		]);
		return parseNumberMap(Reflect.field(j, "rates"), "rates");
	}

	/**
		Convert `amount` from `from` to `to` using the rate on `date`
		(`YYYY-MM-DD`). Pro-gated.
	**/
	public function convertHistorical(amount:Float, from:String, to:String, date:String):Float {
		if (from == null || to == null || date == null)
			throw new UniRateError("from, to and date are required");
		final j = requestJson("/api/historical/rates", [
			param("date", date),
			param("amount", formatAmount(amount)),
			param("from", upper(from)),
			param("to", upper(to))
		]);
		return parseNumber(Reflect.field(j, "result"), "result");
	}

	/**
		Time series of exchange rates between `startDate` and `endDate`
		(`YYYY-MM-DD`, up to a 5-year span). Returns a nested map
		`{date -> {currency -> rate}}`.

		Pass `null` for `base` to default to `"USD"`, `null`/empty for
		`currencies` to get every currency, and `null` for `amount` to default
		to `1`. Pro-gated.
	**/
	public function getTimeSeries(startDate:String, endDate:String, ?base:String, ?currencies:Array<String>, ?amount:Float):Map<String, Map<String, Float>> {
		if (startDate == null || endDate == null)
			throw new UniRateError("startDate and endDate are required");
		final query = [
			param("start_date", startDate),
			param("end_date", endDate),
			param("amount", formatAmount(amount == null ? 1 : amount)),
			param("base", upper(base == null ? "USD" : base))
		];
		if (currencies != null && currencies.length > 0)
			query.push(param("currencies", [for (c in currencies) upper(c)].join(",")));
		final j = requestJson("/api/historical/timeseries", query);
		final data = Reflect.field(j, "data");
		if (data == null)
			throw new UniRateError("Malformed response: missing 'data'");
		final out = new Map<String, Map<String, Float>>();
		for (dateKey in Reflect.fields(data))
			out.set(dateKey, parseNumberMap(Reflect.field(data, dateKey), dateKey));
		return out;
	}

	/** Per-currency historical-data coverage. Pro-gated. **/
	public function getHistoricalLimits():HistoricalLimitsResponse {
		final j = requestJson("/api/historical/limits", []);
		final currencies = new Map<String, HistoricalLimit>();
		final cobj = Reflect.field(j, "currencies");
		if (cobj != null) {
			for (code in Reflect.fields(cobj)) {
				final e = Reflect.field(cobj, code);
				currencies.set(code, {
					earliestDate: strField(e, "earliest_date"),
					latestDate: strField(e, "latest_date"),
					totalDays: intField(e, "total_days"),
					description: strField(e, "description")
				});
			}
		}
		return {
			totalCurrencies: intField(j, "total_currencies"),
			dataSource: strField(j, "data_source"),
			currencies: currencies
		};
	}

	// ---------------------------------------------------------------
	// VAT
	// ---------------------------------------------------------------

	/** VAT rates for every supported country. **/
	public function getVatRates():VatRatesResponse {
		final j = requestJson("/api/vat/rates", []);
		final rates = new Map<String, VatRate>();
		final robj = Reflect.field(j, "vat_rates");
		if (robj != null) {
			for (code in Reflect.fields(robj))
				rates.set(code, parseVatRate(Reflect.field(robj, code)));
		}
		return {
			totalCountries: intField(j, "total_countries"),
			date: strField(j, "date"),
			vatRates: rates
		};
	}

	/** VAT data for a single ISO-3166 alpha-2 country code (e.g. `"DE"`). **/
	public function getVatRate(country:String):VatCountryResponse {
		if (country == null)
			throw new UniRateError("country is required");
		final j = requestJson("/api/vat/rates", [param("country", upper(country))]);
		return {
			country: strField(j, "country"),
			vatData: parseVatRate(Reflect.field(j, "vat_data"))
		};
	}

	// ---------------------------------------------------------------
	// Default transport
	// ---------------------------------------------------------------

	/**
		The default HTTP transport, backed by `haxe.Http`. Synchronous; works
		on the sys / eval / hashlink / neko / cpp targets. Returns the status
		and body for any HTTP response (including 4xx/5xx, whose body lives in
		`responseData`), and throws a `UniRateError` only for genuine
		transport failures (connection refused, timeout) where no status line
		was received.
	**/
	public static function defaultTransport(url:String, headers:Map<String, String>, timeout:Float):HttpResponse {
		var status = 0;
		var errMsg:Null<String> = null;
		final h = new haxe.Http(url);
		for (name => value in headers)
			h.setHeader(name, value);
		h.cnxTimeout = timeout;
		h.onStatus = s -> status = s;
		h.onError = e -> errMsg = e;
		h.onData = _ -> {};
		h.request(false);
		if (status == 0)
			throw new UniRateError(errMsg != null ? "Network error: " + errMsg : "Network error");
		return {status: status, body: h.responseData != null ? h.responseData : ""};
	}

	// ---------------------------------------------------------------
	// Internals
	// ---------------------------------------------------------------

	function requestJson(path:String, query:Array<{name:String, value:Null<String>}>):Dynamic {
		final url = buildUrl(path, query);
		final headers = ["Accept" => "application/json", "User-Agent" => userAgent];
		final resp = transport(url, headers, timeout);
		final body = resp.body == null ? "" : resp.body;
		if (resp.status >= 200 && resp.status < 300) {
			try {
				return Json.parse(body);
			} catch (e:Dynamic) {
				throw new UniRateError("Failed to parse response JSON: " + Std.string(e));
			}
		}
		switch resp.status {
			case 400:
				throw new InvalidDateError("Invalid request parameters");
			case 401:
				throw new AuthenticationError("Missing or invalid API key");
			case 404:
				throw new InvalidCurrencyError("Currency not found or no data available");
			case 429:
				throw new RateLimitError("Rate limit exceeded");
			case _:
				throw new ApiError(resp.status, body);
		}
	}

	function buildUrl(path:String, query:Array<{name:String, value:Null<String>}>):String {
		final parts = [];
		for (p in query)
			if (p.value != null)
				parts.push(StringTools.urlEncode(p.name) + "=" + StringTools.urlEncode(p.value));
		parts.push("api_key=" + StringTools.urlEncode(apiKey));
		return baseUrl + path + "?" + parts.join("&");
	}

	static inline function param(name:String, value:Null<String>):{name:String, value:Null<String>} {
		return {name: name, value: value};
	}

	static function upper(s:String):String {
		return s == null ? null : s.toUpperCase();
	}

	static function stripTrailingSlash(s:String):String {
		return StringTools.endsWith(s, "/") ? s.substr(0, s.length - 1) : s;
	}

	/** Render a number for a query string without a spurious trailing `.0`. **/
	static function formatAmount(v:Float):String {
		if (Math.isFinite(v) && v == Math.ffloor(v) && Math.abs(v) <= 2147483647)
			return Std.string(Std.int(v));
		var s = Std.string(v);
		if (StringTools.endsWith(s, ".0"))
			s = s.substr(0, s.length - 2);
		return s;
	}

	static function parseNumber(v:Dynamic, field:String):Float {
		if (v == null)
			throw new UniRateError("Malformed response: missing '" + field + "'");
		if (Std.isOfType(v, Int) || Std.isOfType(v, Float))
			return (v : Float);
		if (Std.isOfType(v, String)) {
			final f = Std.parseFloat(v);
			if (Math.isNaN(f))
				throw new UniRateError("Malformed response: '" + field + "' is not numeric: " + v);
			return f;
		}
		throw new UniRateError("Malformed response: '" + field + "' has unexpected type");
	}

	static function parseNumberMap(obj:Dynamic, field:String):Map<String, Float> {
		if (obj == null || !Reflect.isObject(obj))
			throw new UniRateError("Malformed response: missing or invalid '" + field + "' map");
		final out = new Map<String, Float>();
		for (f in Reflect.fields(obj))
			out.set(f, parseNumber(Reflect.field(obj, f), f));
		return out;
	}

	static function parseVatRate(o:Dynamic):VatRate {
		if (o == null)
			throw new UniRateError("Malformed response: missing VAT data");
		return {
			countryCode: strField(o, "country_code"),
			countryName: strField(o, "country_name"),
			vatRate: parseNumber(Reflect.field(o, "vat_rate"), "vat_rate")
		};
	}

	static function strField(o:Dynamic, f:String):String {
		final v = Reflect.field(o, f);
		return v == null ? null : Std.string(v);
	}

	static function intField(o:Dynamic, field:String):Int {
		final v = Reflect.field(o, field);
		if (v == null)
			return 0;
		return Std.int(parseNumber(v, field));
	}
}
