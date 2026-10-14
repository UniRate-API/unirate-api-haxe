import unirate.UniRateClient;
import unirate.Transport;
import unirate.Errors;

/**
	Mock test suite. Injects a canned `Transport` so nothing touches the
	network. Hand-rolled runner (no third-party test library) — it prints a
	summary and exits non-zero if anything fails, so CI and the negative
	control can rely on the exit code.

	Set `UNIRATE_FORCE_FAIL=1` to inject one deliberate failure — used by the
	gate's negative control to prove a failing run actually exits non-zero.
**/
class TestClient {
	static var passed = 0;
	static var failed = 0;

	// Capture of the most recent request, for URL/header assertions.
	static var lastUrl:String;
	static var lastHeaders:Map<String, String>;

	static function ok(cond:Bool, name:String) {
		if (cond) {
			passed++;
		} else {
			failed++;
			Sys.println("FAIL: " + name);
		}
	}

	static function eqf(actual:Float, expected:Float, name:String) {
		ok(Math.abs(actual - expected) < 1e-9, name + " (expected " + expected + ", got " + actual + ")");
	}

	static function contains(haystack:String, needle:String, name:String) {
		ok(haystack != null && haystack.indexOf(needle) >= 0, name + " (missing '" + needle + "' in " + haystack + ")");
	}

	/** A transport that returns a fixed status + body and records the request. **/
	static function fixed(status:Int, body:String):Transport {
		return (url, headers, timeout) -> {
			lastUrl = url;
			lastHeaders = headers;
			return {status: status, body: body};
		};
	}

	static function client(status:Int, body:String):UniRateClient {
		return new UniRateClient("test-key", "https://api.example.com/", 5, fixed(status, body));
	}

	// ---- current rates --------------------------------------------------

	static function testGetRate() {
		final c = client(200, '{"rate":"0.92"}');
		eqf(c.getRate("usd", "eur"), 0.92, "getRate parses string rate");
		contains(lastUrl, "from=USD", "getRate upper-cases from");
		contains(lastUrl, "to=EUR", "getRate upper-cases to");
		contains(lastUrl, "api_key=test-key", "getRate appends api_key");
		ok(lastHeaders.get("Accept") == "application/json", "getRate sends Accept: application/json");
		contains(lastHeaders.get("User-Agent"), "unirate-haxe/", "getRate sends User-Agent");
		contains(lastUrl, "https://api.example.com/api/rates?", "base url trailing slash stripped");
	}

	static function testGetRateDefaultFrom() {
		final c = client(200, '{"rate":"1.0"}');
		c.getRate(null, "EUR");
		contains(lastUrl, "from=USD", "getRate null from defaults to USD");
	}

	static function testGetAllRates() {
		final c = client(200, '{"rates":{"EUR":"0.92","GBP":"0.79"}}');
		final m = c.getAllRates();
		eqf(m.get("EUR"), 0.92, "getAllRates EUR");
		eqf(m.get("GBP"), 0.79, "getAllRates GBP");
		contains(lastUrl, "from=USD", "getAllRates defaults base to USD");
	}

	static function testConvert() {
		final c = client(200, '{"result":"92.50"}');
		eqf(c.convert(100, "USD", "EUR"), 92.5, "convert parses result");
		contains(lastUrl, "amount=100", "convert formats whole amount without .0");
	}

	static function testConvertFractionalAmount() {
		final c = client(200, '{"result":"2.3"}');
		c.convert(2.5, "USD", "EUR");
		contains(lastUrl, "amount=2.5", "convert keeps fractional amount");
	}

	static function testSupportedCurrencies() {
		final c = client(200, '{"currencies":["USD","EUR","GBP"]}');
		final cs = c.getSupportedCurrencies();
		ok(cs.length == 3 && cs[0] == "USD" && cs.indexOf("EUR") >= 0, "getSupportedCurrencies returns codes");
	}

	// ---- historical -----------------------------------------------------

	static function testHistoricalRate() {
		final c = client(200, '{"rate":"0.88"}');
		eqf(c.getHistoricalRate("2024-01-01", "USD", "EUR"), 0.88, "getHistoricalRate parses rate");
		contains(lastUrl, "date=2024-01-01", "getHistoricalRate sends date");
		contains(lastUrl, "amount=1", "getHistoricalRate pins amount=1");
	}

	static function testHistoricalRates() {
		final c = client(200, '{"rates":{"EUR":"0.9"}}');
		eqf(c.getHistoricalRates("2024-01-01").get("EUR"), 0.9, "getHistoricalRates map");
	}

	static function testConvertHistorical() {
		final c = client(200, '{"result":"88.0"}');
		eqf(c.convertHistorical(100, "USD", "EUR", "2024-01-01"), 88.0, "convertHistorical parses result");
		contains(lastUrl, "amount=100", "convertHistorical formats amount");
	}

	static function testTimeSeries() {
		final c = client(200, '{"data":{"2024-01-01":{"EUR":0.92,"GBP":0.79},"2024-01-02":{"EUR":0.93}}}');
		final ts = c.getTimeSeries("2024-01-01", "2024-01-02", "USD", ["eur", "gbp"], 1);
		eqf(ts.get("2024-01-01").get("EUR"), 0.92, "timeseries nested EUR (numeric)");
		eqf(ts.get("2024-01-02").get("EUR"), 0.93, "timeseries second day");
		contains(lastUrl, "currencies=EUR%2CGBP", "timeseries joins + upper-cases currencies");
		contains(lastUrl, "start_date=2024-01-01", "timeseries sends start_date");
	}

	static function testHistoricalLimits() {
		final c = client(200, '{"total_currencies":2,"data_source":"src","currencies":{"USD":{"earliest_date":"1999-01-01","latest_date":"2026-01-01","total_days":9000,"description":"US Dollar"}}}');
		final r = c.getHistoricalLimits();
		ok(r.totalCurrencies == 2, "limits totalCurrencies");
		ok(r.dataSource == "src", "limits dataSource");
		final usd = r.currencies.get("USD");
		ok(usd != null && usd.earliestDate == "1999-01-01" && usd.totalDays == 9000, "limits per-currency fields");
	}

	// ---- VAT ------------------------------------------------------------

	static function testVatRates() {
		final c = client(200, '{"total_countries":1,"date":"2026-01-01","vat_rates":{"DE":{"country_code":"DE","country_name":"Germany","vat_rate":19.0}}}');
		final r = c.getVatRates();
		ok(r.totalCountries == 1 && r.date == "2026-01-01", "vatRates top-level fields");
		final de = r.vatRates.get("DE");
		ok(de != null && de.countryCode == "DE" && de.countryName == "Germany", "vatRates DE fields");
		eqf(de.vatRate, 19.0, "vatRates DE rate");
	}

	static function testVatRate() {
		final c = client(200, '{"country":"DE","vat_data":{"country_code":"DE","country_name":"Germany","vat_rate":19.0}}');
		final r = c.getVatRate("de");
		contains(lastUrl, "country=DE", "getVatRate upper-cases country");
		ok(r.country == "DE" && r.vatData.countryCode == "DE", "getVatRate fields");
		eqf(r.vatData.vatRate, 19.0, "getVatRate rate");
	}

	// ---- error mapping --------------------------------------------------

	static function testAuthError() {
		final c = client(401, '{"error":"no key"}');
		try {
			c.getRate("USD", "EUR");
			ok(false, "401 should throw");
		} catch (e:AuthenticationError) {
			ok(e.message == "Missing or invalid API key", "401 -> AuthenticationError");
		} catch (e:Dynamic) {
			ok(false, "401 wrong type: " + Std.string(e));
		}
	}

	static function testInvalidCurrencyError() {
		final c = client(404, '{}');
		try {
			c.getRate("USD", "ZZZ");
			ok(false, "404 should throw");
		} catch (e:InvalidCurrencyError) {
			ok(e.message == "Currency not found or no data available", "404 -> InvalidCurrencyError");
		} catch (e:Dynamic) {
			ok(false, "404 wrong type: " + Std.string(e));
		}
	}

	static function testInvalidDateError() {
		final c = client(400, '{}');
		try {
			c.getHistoricalRate("not-a-date", "USD", "EUR");
			ok(false, "400 should throw");
		} catch (e:InvalidDateError) {
			ok(e.message == "Invalid request parameters", "400 -> InvalidDateError");
		} catch (e:Dynamic) {
			ok(false, "400 wrong type: " + Std.string(e));
		}
	}

	static function testRateLimitError() {
		final c = client(429, '{}');
		try {
			c.getRate("USD", "EUR");
			ok(false, "429 should throw");
		} catch (e:RateLimitError) {
			ok(e.message == "Rate limit exceeded", "429 -> RateLimitError");
		} catch (e:Dynamic) {
			ok(false, "429 wrong type: " + Std.string(e));
		}
	}

	static function testProGate403() {
		final c = client(403, '{"error":"pro only"}');
		try {
			c.getHistoricalRate("2024-01-01", "USD", "EUR");
			ok(false, "403 should throw");
		} catch (e:ApiError) {
			ok(e.status == 403 && e.message == "Endpoint requires a Pro subscription", "403 -> ApiError Pro-gate");
		} catch (e:Dynamic) {
			ok(false, "403 wrong type: " + Std.string(e));
		}
	}

	static function testServiceUnavailable503() {
		final c = client(503, 'upstream down');
		try {
			c.getRate("USD", "EUR");
			ok(false, "503 should throw");
		} catch (e:ApiError) {
			ok(e.status == 503 && e.message == "Service unavailable", "503 -> ApiError service unavailable");
		} catch (e:Dynamic) {
			ok(false, "503 wrong type: " + Std.string(e));
		}
	}

	static function testGenericApiError() {
		final c = client(500, 'boom');
		try {
			c.getRate("USD", "EUR");
			ok(false, "500 should throw");
		} catch (e:ApiError) {
			ok(e.status == 500 && e.body == "boom", "500 -> ApiError keeps status + body");
		} catch (e:Dynamic) {
			ok(false, "500 wrong type: " + Std.string(e));
		}
	}

	static function testBaseErrorCatchesAll() {
		final c = client(401, '{}');
		try {
			c.getRate("USD", "EUR");
			ok(false, "should throw");
		} catch (e:UniRateError) {
			ok(true, "subclass caught by base UniRateError");
		} catch (e:Dynamic) {
			ok(false, "not caught by base: " + Std.string(e));
		}
	}

	static function main() {
		testGetRate();
		testGetRateDefaultFrom();
		testGetAllRates();
		testConvert();
		testConvertFractionalAmount();
		testSupportedCurrencies();
		testHistoricalRate();
		testHistoricalRates();
		testConvertHistorical();
		testTimeSeries();
		testHistoricalLimits();
		testVatRates();
		testVatRate();
		testAuthError();
		testInvalidCurrencyError();
		testInvalidDateError();
		testRateLimitError();
		testProGate403();
		testServiceUnavailable503();
		testGenericApiError();
		testBaseErrorCatchesAll();

		// Negative control: prove a failing run exits non-zero.
		if (Sys.getEnv("UNIRATE_FORCE_FAIL") != null)
			ok(false, "forced failure (negative control)");

		Sys.println("");
		Sys.println(passed + " passed, " + failed + " failed");
		Sys.exit(failed == 0 ? 0 : 1);
	}
}
