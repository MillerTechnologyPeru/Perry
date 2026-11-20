# Perry CloudKit provider

2026-11-20

Perry's CloudKit defaults to a local backend with no network, and uses [MistKit](https://github.com/brightdigit/MistKit) only when the user supplies a token in an environment variable.

## Backends

- **Default (local):** `CKContainer.accountStatus` reports no account, or records persist locally. Apps launch and degrade gracefully with no network.
- **Opt-in (MistKit):** if the API token variable is set at launch, `CKDatabase` operations route through MistKit to CloudKit Web Services.
- **Build-time:** MistKit pulls in swift-openapi-runtime, swift-openapi-urlsession, swift-crypto and swift-log. A `MistKit` SwiftPM trait on the Perry CloudKit target would keep those out of default builds.
- **Transport:** MistKit's URLSession transport runs on swift-corelibs-foundation, the same stack Perry's `NSURLSession` already sits on.

## Environment variables

These names are a proposal, not settled.

| Variable | Purpose | Required |
| --- | --- | --- |
| `PERRY_CLOUDKIT_API_TOKEN` | Enables the MistKit backend | Yes, to opt in |
| `PERRY_CLOUDKIT_WEB_AUTH_TOKEN` | Access to private and shared databases | No |
| `PERRY_CLOUDKIT_ENVIRONMENT` | Development or production | No |
| `PERRY_CLOUDKIT_CONTAINER` | Overrides the container identifier from the app's entitlements | No |

## Existing Swift clients

| Package | What it is | Fit for Perry |
| --- | --- | --- |
| [brightdigit/MistKit](https://github.com/brightdigit/MistKit) | CloudKit Web Services client generated from an OpenAPI spec; 1.0.0-beta.5, Swift 6.1+, Linux listed | Chosen transport: records, zones, subscriptions and change fetching; API token, web auth token and server-to-server auth |
| [BennyKJohnson/OpenCloudKit](https://github.com/BennyKJohnson/OpenCloudKit) | Web Services wrapper modelled on Apple's `CKContainer`, `CKRecord` and `CKDatabase` | Reference for the `CK*` surface only; README still uses Swift 3-era package syntax |
| [coodly/TalkToCloud](https://github.com/coodly/TalkToCloud) | Small Web Services client | Nothing the other two lack |

## Limits and open items

- Web Services needs a per-container API token, and an App Store binary carries none. The MistKit backend is therefore usable only for containers where the user holds the token, in practice their own apps.
- The native framework is understood to use a private device-authenticated protocol that none of these packages implement. This is from memory, not verified.
- MistKit requires swift-crypto `from: "4.0.0"`, while PureSwift/HAP declares `from: "3.0.0"`. A build that includes both fails dependency resolution until HAP's range is widened.
- The storage format for the local backend is undecided.
- MistKit was read, not built or run.
