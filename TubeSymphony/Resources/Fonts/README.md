# Fonts

The website's mac skin faces (tube-symphony `fonts/`), converted from WOFF2 to TTF
with fontTools because iOS cannot load WOFF2. Registered in `project.yml` (UIAppFonts).

| File | Face | Licence |
| --- | --- | --- |
| ChicagoFLF.ttf | ChicagoFLF | Free Lunch Fonts release of Chicago, distributed as public domain |
| Fraunces-600.ttf | Fraunces SemiBold | SIL Open Font License 1.1 (Fraunces-OFL.txt) |
| RobotoMono-400.ttf, RobotoMono-700.ttf | Roboto Mono | Apache License 2.0 |

The website's fourth face, "Main" (Johnston100 W03), is not here: it is a Monotype
web-font licence, which does not cover embedding in an app. `MacType` uses it automatically if
Johnston100W03-Regular.ttf and -Medium.ttf are added here and to UIAppFonts; until then the system face stands in.
