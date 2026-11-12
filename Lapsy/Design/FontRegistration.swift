import CoreText
import Foundation

/// Registers the bundled .ttf fonts (Plus Jakarta Sans, Geist Mono) at launch,
/// so no Info.plist font list is needed. Licenses are in the repo's Licenses folder.
enum FontRegistration {
    static func registerAll() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
