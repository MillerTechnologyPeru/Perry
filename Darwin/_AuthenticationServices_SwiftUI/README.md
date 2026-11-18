# _AuthenticationServices_SwiftUI

Perry's `_AuthenticationServices_SwiftUI.framework`: AuthenticationServices'
SwiftUI API, of which `WebAuthenticationSession` and
`EnvironmentValues.webAuthenticationSession` are here. Perry has no browser
sheet to show a sign-in page in, so a session's sign-in ends at once as
cancelled. `Scripts/build-authenticationservices-swiftui.sh` builds it on a
Mac, after `Scripts/build-swiftui.sh`, against Perry's SwiftUI.
