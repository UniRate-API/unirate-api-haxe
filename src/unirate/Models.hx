package unirate;

/**
	VAT data for a single country.
**/
typedef VatRate = {
	var countryCode:String;
	var countryName:String;
	var vatRate:Float;
}

/**
	Response from `getVatRates()` — VAT data for every supported country.
**/
typedef VatRatesResponse = {
	var totalCountries:Int;
	var date:String;
	var vatRates:Map<String, VatRate>;
}

/**
	Response from `getVatRate(country)` — VAT data for one country.
**/
typedef VatCountryResponse = {
	var country:String;
	var vatData:VatRate;
}

/**
	Historical-data coverage for a single currency.
**/
typedef HistoricalLimit = {
	var earliestDate:String;
	var latestDate:String;
	var totalDays:Int;
	var description:String;
}

/**
	Response from `getHistoricalLimits()` — per-currency coverage.
**/
typedef HistoricalLimitsResponse = {
	var totalCurrencies:Int;
	var dataSource:String;
	var currencies:Map<String, HistoricalLimit>;
}
