# WeatherKit

Perry's `WeatherKit.framework`: `WeatherService`, the queries it answers
(`.current`, `.hourly`, `.daily`, `.minute`, `.alerts`, `.availability`,
and `daily(startDate:endDate:)`) and the weather types they return, for apps
that show the weather. WeatherKit is Swift only, so apps bind to its Swift
symbols; the declarations follow the iOS SDK's WeatherKit interface (frozen
enums and their cases) and the framework is built the way StoreKit is:
`Scripts/build-framework.sh WeatherKit` on a Mac, into the Swift runtime
directory (`PERRY_SWIFT_RUNTIME`), where the loader finds it.

The data comes from [Open-Meteo](https://open-meteo.com), which needs no
account or key. `WeatherService.attribution` names it, as its terms ask
(and as Apple's terms do for WeatherKit's own data). `PERRY_WEATHERKIT_OPEN_METEO_URL`
points the service at another server speaking its forecast API.

What Open-Meteo has no answer for is left as WeatherKit leaves what it
doesn't have: no minute forecast or alerts (`.minute` and `.alerts` are
nil, and `availability` says they are unsupported); twilight times and
moonrise and moonset are nil; the moon's phase is worked out; the parts of
a day are made from the hours.

The weather symbols (`symbolName`) are SF Symbols, which Perry draws from
what macOS renders into the app's copy: copy `SFSymbols.txt` here (the names,
and their `.fill` forms that apps build) into `<App>.app` before
`Scripts/extract-assets.sh`, since the app's own files don't name them.

Not here yet: statistics (`dailyStatistics`, `hourlyStatistics`,
`monthlyStatistics`, `dailySummary`), `.changes`, `.historicalComparisons`,
air quality, and Apple's own REST API with a signed token (a Service
Identifier and key from a developer account).
