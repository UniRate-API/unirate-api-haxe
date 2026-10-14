import unirate.UniRateClient;

/**
	Runnable quick-start example.

	Reads the API key from the `UNIRATE_API_KEY` environment variable.

	Run with:
	  UNIRATE_API_KEY=... haxe -cp src -cp examples -main Quickstart --interp
**/
class Quickstart {
	static function main() {
		final key = Sys.getEnv("UNIRATE_API_KEY");
		if (key == null || key == "") {
			Sys.println("Set UNIRATE_API_KEY to run this example.");
			return;
		}

		final client = new UniRateClient(key);

		final rate = client.getRate("USD", "EUR");
		Sys.println("1 USD = " + rate + " EUR");

		final converted = client.convert(100, "USD", "EUR");
		Sys.println("100 USD = " + converted + " EUR");

		final currencies = client.getSupportedCurrencies();
		Sys.println(currencies.length + " currencies supported");
	}
}
