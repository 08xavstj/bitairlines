import Testing
import UIKit
import CoreCatalog
import CoreWorld
@testable import BitAirlines

@Suite struct ArtTests {
    @Test func everySpriteFamilyHasADrawing() {
        for family in SpriteFamily.allCases {
            let rows = AircraftSpriteData.rows[family.rawValue]
            #expect(rows != nil, "\(family.rawValue) has no drawing")
            #expect(Livery.image(family: family, branding: .starter) != nil, "\(family.rawValue) did not render")
        }
    }

    @Test func spritesAreRectanglesOfKnownRoles() {
        let known = Set(".kfucgtmlwvnd")
        for (name, rows) in AircraftSpriteData.rows {
            let width = rows[0].count
            for row in rows {
                #expect(row.count == width, "\(name) has a ragged row")
                #expect(row.allSatisfy { known.contains($0) }, "\(name) has an unknown role character")
            }
        }
    }

    @Test func everyFamilyIsUsedByAnAircraftAndEveryAircraftHasASprite() {
        let used = Set(AircraftCatalog.all.map(\.family))
        #expect(used == Set(SpriteFamily.allCases), "unused or missing families")
    }

    @Test func mapIconsExistForEverySizeClass() {
        for size in ["small", "medium", "large", "heavy"] { #expect(Livery.mapIcon(sizeClass: size, branding: .starter) != nil, size) }
        #expect(Livery.sizeClass(seats: 9) == "small" && Livery.sizeClass(seats: 19) == "medium" && Livery.sizeClass(seats: 180) == "large" && Livery.sizeClass(seats: 500) == "heavy")
    }

    @Test func theLogoShowsOnTheTail() {
        var plain = Branding.starter
        plain.logo = Branding.blankLogo()
        var marked = plain
        for y in 0..<Branding.logoSize { for x in 0..<Branding.logoSize { marked.setLogoPixel(x: x, y: y, colour: 8) } }
        let a = Livery.image(family: .narrowbody, branding: plain)?.pngData()
        let b = Livery.image(family: .narrowbody, branding: marked)?.pngData()
        #expect(a != nil && b != nil && a != b, "a painted logo must change the picture")
    }

    @Test func colourAndStyleChangeThePicture() {
        var a = Branding.starter
        var b = a
        b.primary = 8
        #expect(Livery.image(family: .utilitySingle, branding: a)?.pngData() != Livery.image(family: .utilitySingle, branding: b)?.pngData())
        a.style = .fullBody
        #expect(Livery.image(family: .utilitySingle, branding: a)?.pngData() != Livery.image(family: .utilitySingle, branding: .starter)?.pngData())
    }

    @Test func logoTemplatesFitTheGrid() {
        for template in LogoTemplates.all {
            #expect(template.rows.count <= Branding.logoSize && template.rows.allSatisfy { $0.count <= Branding.logoSize }, template.name)
            #expect(template.logo(for: .starter).contains { $0 != 0 }, "\(template.name) draws nothing")
        }
    }
}
