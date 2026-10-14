import unirate.UniRateClient;

/**
	Live test suite — hits the real UniRate API.

	Runs only when `UNIRATE_API_KEY` is set, and exercises FREE-TIER endpoints
	only (rates, convert, currencies, VAT). Historical/timeseries/limits are
	Pro-gated (they 403 on the free tier) and are intentionally excluded.

	Run with:  UNIRATE_API_KEY=... haxe -cp src -cp test -main LiveTest --interp
**/
class LiveTest {
	static var passed = 0;
	static var failed = 0;

	static function ok(cond:Bool, name:String) {
		if (cond) {
			passed++;
			Sys.println("ok   - " + name);
		} else {
			failed++;
			Sys.println("FAIL - " + name);
		}
	}

	static function main() {
		final key = Sys.getEnv("UNIRATE_API_KEY");
		if (key == null || key == "") {
			Sys.println("UNIRATE_API_KEY not set — skipping live tests.");
			return;
		}

		final c = new UniRateClient(key);

		try {
			final r = c.getRate("USD", "EUR");
			ok(r > 0, "live: getRate USD->EUR is positive (" + r + ")");

			final all = c.getAllRates("USD");
			ok(Lambda.count(all) > 10 && all.exists("EUR"), "live: getAllRates returns a populated map");

			final v = c.convert(100, "USD", "EUR");
			ok(v > 0, "live: convert 100 USD->EUR is positive (" + v + ")");

			final cs = c.getSupportedCurrencies();
			ok(cs.length > 10 && cs.indexOf("USD") >= 0 && cs.indexOf("EUR") >= 0, "live: getSupportedCurrencies includes common codes (" + cs.length + ")");

			final vat = c.getVatRates();
			ok(Lambda.count(vat.vatRates) > 0, "live: getVatRates returns country data");

			final de = c.getVatRate("DE");
			ok(de.vatData.countryCode == "DE" && de.vatData.vatRate > 0, "live: getVatRate DE returns a VAT rate (" + de.vatData.vatRate + ")");
		} catch (e:Dynamic) {
			ok(false, "live: unexpected error: " + Std.string(e));
		}

		Sys.println("");
		Sys.println(passed + " passed, " + failed + " failed");
		Sys.exit(failed == 0 ? 0 : 1);
	}
}
