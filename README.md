# UniRate API — Haxe client

Official [Haxe](https://haxe.org) client for the [UniRate API](https://unirateapi.com) —
free currency exchange rates, historical data, and VAT rates.

- **Zero dependencies.** HTTP via `haxe.Http`, JSON via `haxe.Json` — both in the
  Haxe standard library. Nothing else is pulled in.
- **Injectable transport**, so your tests never touch the network.
- Works on the sys targets (eval, HashLink, Neko, C++, …).

## Install

```sh
haxelib install unirate-api
```

Then add `-lib unirate-api` to your build (`.hxml`).

## Quick start

```haxe
import unirate.UniRateClient;

class Main {
	static function main() {
		var client = new UniRateClient("your-api-key");

		// Current rate
		var rate = client.getRate("USD", "EUR");          // 0.92

		// Convert an amount
		var eur = client.convert(100, "USD", "EUR");      // 92.5

		// All rates for a base currency
		var all = client.getAllRates("USD");              // Map<String, Float>

		// Supported currency codes
		var codes = client.getSupportedCurrencies();      // ["USD", "EUR", ...]
	}
}
```

Get a free API key at [unirateapi.com](https://unirateapi.com).

## API

Construct a client with your API key (plus optional base URL, timeout in
seconds, and a custom `Transport`):

```haxe
new UniRateClient(apiKey, ?baseUrl, ?timeout, ?transport);
```

### Current rates & conversion (free tier)

| Method | Returns |
|---|---|
| `getRate(from, to)` | `Float` — rate from `from` to `to` |
| `getAllRates(?from)` | `Map<String, Float>` — every rate for a base (default `"USD"`) |
| `convert(amount, from, to)` | `Float` — converted amount |
| `getSupportedCurrencies()` | `Array<String>` — currency codes |

### VAT (free tier)

| Method | Returns |
|---|---|
| `getVatRates()` | `VatRatesResponse` |
| `getVatRate(country)` | `VatCountryResponse` (ISO-3166 alpha-2, e.g. `"DE"`) |

### Historical data (requires a Pro subscription)

These return `403` on the free tier (surfaced as an `ApiError` with
`status == 403`):

| Method | Returns |
|---|---|
| `getHistoricalRate(date, from, to)` | `Float` |
| `getHistoricalRates(date, ?base)` | `Map<String, Float>` |
| `convertHistorical(amount, from, to, date)` | `Float` |
| `getTimeSeries(startDate, endDate, ?base, ?currencies, ?amount)` | `Map<String, Map<String, Float>>` |
| `getHistoricalLimits()` | `HistoricalLimitsResponse` |

Currency and country codes are upper-cased before being sent.

## Error handling

All errors extend `unirate.UniRateError`. Catch the base type for everything,
or narrow to a specific case:

```haxe
import unirate.Errors;

try {
	var rate = client.getRate("USD", "EUR");
} catch (e:AuthenticationError) {
	// 401 — missing or invalid API key
} catch (e:RateLimitError) {
	// 429 — rate limit exceeded
} catch (e:ApiError) {
	// 403 (Pro-gated), 503, or any other non-2xx — inspect e.status / e.body
	trace(e.status);
} catch (e:UniRateError) {
	// InvalidCurrencyError (404), InvalidDateError (400), transport errors, ...
}
```

| Status | Error |
|---|---|
| 400 | `InvalidDateError` |
| 401 | `AuthenticationError` |
| 403 | `ApiError` (status 403) — "Endpoint requires a Pro subscription" |
| 404 | `InvalidCurrencyError` |
| 429 | `RateLimitError` |
| 503 | `ApiError` (status 503) — "Service unavailable" |
| other / network | `ApiError` / `UniRateError` |

## Rate limits

The free tier is rate-limited. On `429` the client throws `RateLimitError`;
back off and retry.

## Testing

Mock tests use an injected transport and never hit the network:

```sh
haxe -cp src -cp test -main TestClient --interp
```

Live tests (free-tier endpoints only) run when `UNIRATE_API_KEY` is set:

```sh
UNIRATE_API_KEY=... haxe -cp src -cp test -main LiveTest --interp
```

## Related clients

Official UniRate clients exist for Python, Node/TypeScript, Go, Rust, Java,
Ruby, PHP, Swift, Elixir, and more. See
[github.com/UniRate-API](https://github.com/UniRate-API).

## License

MIT © 2026 Unirate Team. Source: <https://github.com/UniRate-API/unirate-api-haxe>
