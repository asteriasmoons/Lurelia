//
//  LureliaIconLibrary.swift
//  Lurelia
//

import SwiftUI
import UIKit

// MARK: - Icon Source

enum LureliaIconSource: String, Codable, CaseIterable {
    case asset
    case sfSymbol
}

// MARK: - Icon Item

struct LureliaIconItem: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let source: LureliaIconSource
    let category: String

    init(
        name: String,
        source: LureliaIconSource,
        category: String
    ) {
        self.id = "\(source.rawValue)-\(name)"
        self.name = name
        self.source = source
        self.category = category
    }

    @ViewBuilder
    var image: some View {
        switch source {
        case .asset:
            Image(name)
                .resizable()
                .scaledToFit()

        case .sfSymbol:
            Image(systemName: name)
                .symbolRenderingMode(.hierarchical)
        }
    }
}

// MARK: - Icon Library

enum LureliaIconLibrary {

    // MARK: - Custom Asset Icons

    static let assetIcons: [LureliaIconItem] = [
        // Actions
        .init(name: "addwavy", source: .asset, category: "Actions"),
        .init(name: "checkwavy", source: .asset, category: "Actions"),
        .init(name: "copy", source: .asset, category: "Actions"),
        .init(name: "minuswavy", source: .asset, category: "Actions"),
        .init(name: "pausewavy", source: .asset, category: "Actions"),
        .init(name: "pin", source: .asset, category: "Actions"),
        .init(name: "play", source: .asset, category: "Actions"),
        .init(name: "playwavy", source: .asset, category: "Actions"),
        .init(name: "prohibitedwavy", source: .asset, category: "Actions"),
        .init(name: "skipbackwavy", source: .asset, category: "Actions"),
        .init(name: "skipwavy", source: .asset, category: "Actions"),
        .init(name: "stopwavy", source: .asset, category: "Actions"),
        .init(name: "trash", source: .asset, category: "Actions"),
        .init(name: "upload", source: .asset, category: "Actions"),
        .init(name: "xmarkwavy", source: .asset, category: "Actions"),

        // Audio
        .init(name: "micfill", source: .asset, category: "Audio"),

        // Bags
        .init(name: "backpack", source: .asset, category: "Bags"),
        .init(name: "bookbag", source: .asset, category: "Bags"),
        .init(name: "totebag", source: .asset, category: "Bags"),

        // Bathroom
        .init(name: "shower", source: .asset, category: "Bathroom"),
        .init(name: "showercurtain", source: .asset, category: "Bathroom"),
        .init(name: "stool", source: .asset, category: "Bathroom"),
        .init(name: "toilet", source: .asset, category: "Bathroom"),
        .init(name: "toiletpaper", source: .asset, category: "Bathroom"),
        .init(name: "tproll", source: .asset, category: "Bathroom"),

        // Beauty
        .init(name: "beautystation", source: .asset, category: "Beauty"),
        .init(name: "blowdryer", source: .asset, category: "Beauty"),
        .init(name: "bottlecream", source: .asset, category: "Beauty"),
        .init(name: "creambottle", source: .asset, category: "Beauty"),
        .init(name: "creamjar", source: .asset, category: "Beauty"),
        .init(name: "daycream", source: .asset, category: "Beauty"),
        .init(name: "dropper", source: .asset, category: "Beauty"),
        .init(name: "fingernail", source: .asset, category: "Beauty"),
        .init(name: "flatiron", source: .asset, category: "Beauty"),
        .init(name: "hairbrush", source: .asset, category: "Beauty"),
        .init(name: "lovedeodorant", source: .asset, category: "Beauty"),
        .init(name: "lovedropper", source: .asset, category: "Beauty"),
        .init(name: "loveeye", source: .asset, category: "Beauty"),
        .init(name: "loveiron", source: .asset, category: "Beauty"),
        .init(name: "lovemakeup", source: .asset, category: "Beauty"),
        .init(name: "mirrorbottle", source: .asset, category: "Beauty"),
        .init(name: "mooncream", source: .asset, category: "Beauty"),
        .init(name: "nailfiling", source: .asset, category: "Beauty"),
        .init(name: "nailpolish", source: .asset, category: "Beauty"),
        .init(name: "nailsparkle", source: .asset, category: "Beauty"),
        .init(name: "nightcream", source: .asset, category: "Beauty"),
        .init(name: "perfume", source: .asset, category: "Beauty"),
        .init(name: "pumpbottle", source: .asset, category: "Beauty"),
        .init(name: "razor", source: .asset, category: "Beauty"),
        .init(name: "rollondeodorant", source: .asset, category: "Beauty"),
        .init(name: "shampoo", source: .asset, category: "Beauty"),
        .init(name: "shaverazor", source: .asset, category: "Beauty"),
        .init(name: "specialcream", source: .asset, category: "Beauty"),
        .init(name: "stickscara", source: .asset, category: "Beauty"),

        // Bedroom
        .init(name: "bed", source: .asset, category: "Bedroom"),
        .init(name: "bedpillow", source: .asset, category: "Bedroom"),
        .init(name: "bedroomtvstand", source: .asset, category: "Bedroom"),
        .init(name: "bedtable", source: .asset, category: "Bedroom"),
        .init(name: "drawers", source: .asset, category: "Bedroom"),
        .init(name: "mirrordresser", source: .asset, category: "Bedroom"),
        .init(name: "nightstandtable", source: .asset, category: "Bedroom"),
        .init(name: "pillows", source: .asset, category: "Bedroom"),
        .init(name: "starrypillow", source: .asset, category: "Bedroom"),

        // Bulbs
        .init(name: "brightbulb", source: .asset, category: "Bulbs"),
        .init(name: "bulbxoxo", source: .asset, category: "Bulbs"),
        .init(name: "devbulb", source: .asset, category: "Bulbs"),
        .init(name: "handbulb", source: .asset, category: "Bulbs"),
        .init(name: "starbulb", source: .asset, category: "Bulbs"),
        .init(name: "xoxobulb", source: .asset, category: "Bulbs"),

        // Care
        .init(name: "fingersheart", source: .asset, category: "Care"),
        .init(name: "halfheart", source: .asset, category: "Care"),
        .init(name: "heartbox", source: .asset, category: "Care"),
        .init(name: "heartcircle", source: .asset, category: "Care"),
        .init(name: "heartfill", source: .asset, category: "Care"),
        .init(name: "hearthand", source: .asset, category: "Care"),
        .init(name: "heartoutline", source: .asset, category: "Care"),
        .init(name: "heartpopbox", source: .asset, category: "Care"),
        .init(name: "heartsparkle", source: .asset, category: "Care"),
        .init(name: "heartsum", source: .asset, category: "Care"),
        .init(name: "heartwavy", source: .asset, category: "Care"),
        .init(name: "lovebox", source: .asset, category: "Care"),
        .init(name: "lovecards", source: .asset, category: "Care"),
        .init(name: "plusheart", source: .asset, category: "Care"),
        .init(name: "recovery", source: .asset, category: "Care"),
        .init(name: "starhand", source: .asset, category: "Care"),
        .init(name: "starshand", source: .asset, category: "Care"),
        .init(name: "twinhearts", source: .asset, category: "Care"),

        // Celebration
        .init(name: "bdaycake", source: .asset, category: "Celebration"),
        .init(name: "bowegg", source: .asset, category: "Celebration"),
        .init(name: "cake", source: .asset, category: "Celebration"),
        .init(name: "candlecake", source: .asset, category: "Celebration"),
        .init(name: "confetticake", source: .asset, category: "Celebration"),
        .init(name: "dotcake", source: .asset, category: "Celebration"),
        .init(name: "dotlovering", source: .asset, category: "Celebration"),
        .init(name: "eggs", source: .asset, category: "Celebration"),
        .init(name: "flowersegg", source: .asset, category: "Celebration"),
        .init(name: "heartsegg", source: .asset, category: "Celebration"),
        .init(name: "lovecake", source: .asset, category: "Celebration"),
        .init(name: "partinvite", source: .asset, category: "Celebration"),
        .init(name: "partycandlecake", source: .asset, category: "Celebration"),
        .init(name: "partyinvite", source: .asset, category: "Celebration"),
        .init(name: "spacemanbday", source: .asset, category: "Celebration"),
        .init(name: "sprinklecake", source: .asset, category: "Celebration"),

        // Cleaning
        .init(name: "broompan", source: .asset, category: "Cleaning"),
        .init(name: "bubbles", source: .asset, category: "Cleaning"),
        .init(name: "bucket", source: .asset, category: "Cleaning"),
        .init(name: "dishwasher", source: .asset, category: "Cleaning"),
        .init(name: "dusterwand", source: .asset, category: "Cleaning"),
        .init(name: "laundry", source: .asset, category: "Cleaning"),
        .init(name: "lovedryer", source: .asset, category: "Cleaning"),
        .init(name: "mopbucket", source: .asset, category: "Cleaning"),
        .init(name: "spraybottle", source: .asset, category: "Cleaning"),
        .init(name: "spraybottlefilled", source: .asset, category: "Cleaning"),
        .init(name: "towel", source: .asset, category: "Cleaning"),
        .init(name: "vacuumcleaner", source: .asset, category: "Cleaning"),
        .init(name: "washer", source: .asset, category: "Cleaning"),
        .init(name: "washmachine", source: .asset, category: "Cleaning"),

        // Clothing
        .init(name: "cuteslippers", source: .asset, category: "Clothing"),
        .init(name: "dressshirt", source: .asset, category: "Clothing"),
        .init(name: "hanger", source: .asset, category: "Clothing"),
        .init(name: "heartshirt", source: .asset, category: "Clothing"),
        .init(name: "lovehoodie", source: .asset, category: "Clothing"),
        .init(name: "loveshirt", source: .asset, category: "Clothing"),
        .init(name: "slippers", source: .asset, category: "Clothing"),
        .init(name: "starsocks", source: .asset, category: "Clothing"),

        // Communication
        .init(name: "chatlinesfill", source: .asset, category: "Communication"),
        .init(name: "chatsparkle", source: .asset, category: "Communication"),
        .init(name: "heartlovechat", source: .asset, category: "Communication"),
        .init(name: "heartphone", source: .asset, category: "Communication"),
        .init(name: "lovebboard", source: .asset, category: "Communication"),
        .init(name: "lovechatbubbles", source: .asset, category: "Communication"),
        .init(name: "loveletter", source: .asset, category: "Communication"),
        .init(name: "lovemail", source: .asset, category: "Communication"),
        .init(name: "lovephone", source: .asset, category: "Communication"),
        .init(name: "luvemail", source: .asset, category: "Communication"),
        .init(name: "luvmail", source: .asset, category: "Communication"),
        .init(name: "luvmailfill", source: .asset, category: "Communication"),
        .init(name: "mailbox", source: .asset, category: "Communication"),
        .init(name: "megaphone", source: .asset, category: "Communication"),
        .init(name: "phone", source: .asset, category: "Communication"),
        .init(name: "sendbutton", source: .asset, category: "Communication"),
        .init(name: "starchat", source: .asset, category: "Communication"),
        .init(name: "starmailing", source: .asset, category: "Communication"),
        .init(name: "starphone", source: .asset, category: "Communication"),

        // Creative
        .init(name: "artboard", source: .asset, category: "Creative"),
        .init(name: "colorpencils", source: .asset, category: "Creative"),
        .init(name: "colorpicker", source: .asset, category: "Creative"),
        .init(name: "paintbrush", source: .asset, category: "Creative"),
        .init(name: "paintdrop", source: .asset, category: "Creative"),
        .init(name: "pbrush", source: .asset, category: "Creative"),
        .init(name: "sparklebrush", source: .asset, category: "Creative"),

        // Developer
        .init(name: "buggy", source: .asset, category: "Developer"),
        .init(name: "codewindow", source: .asset, category: "Developer"),
        .init(name: "devwavy", source: .asset, category: "Developer"),
        .init(name: "github", source: .asset, category: "Developer"),

        // Documents
        .init(name: "blankpages", source: .asset, category: "Documents"),
        .init(name: "cardlines", source: .asset, category: "Documents"),
        .init(name: "contract", source: .asset, category: "Documents"),
        .init(name: "doclineslove", source: .asset, category: "Documents"),
        .init(name: "document", source: .asset, category: "Documents"),
        .init(name: "folderfillpapers", source: .asset, category: "Documents"),
        .init(name: "foldertree", source: .asset, category: "Documents"),
        .init(name: "imagesign", source: .asset, category: "Documents"),
        .init(name: "linedpages", source: .asset, category: "Documents"),
        .init(name: "lineimagepage", source: .asset, category: "Documents"),
        .init(name: "linescard", source: .asset, category: "Documents"),
        .init(name: "lovedocs", source: .asset, category: "Documents"),
        .init(name: "lovedocslines", source: .asset, category: "Documents"),
        .init(name: "lovelinepage", source: .asset, category: "Documents"),
        .init(name: "openedfolder", source: .asset, category: "Documents"),
        .init(name: "pagefold", source: .asset, category: "Documents"),
        .init(name: "stardoc", source: .asset, category: "Documents"),
        .init(name: "starlinesdoc", source: .asset, category: "Documents"),
        .init(name: "stikydoc", source: .asset, category: "Documents"),

        // Energy
        .init(name: "bolt", source: .asset, category: "Energy"),
        .init(name: "boltsparkle", source: .asset, category: "Energy"),
        .init(name: "energydrink", source: .asset, category: "Energy"),
        .init(name: "flame", source: .asset, category: "Energy"),
        .init(name: "loveflame", source: .asset, category: "Energy"),
        .init(name: "sparkbolt", source: .asset, category: "Energy"),

        // Events
        .init(name: "lovetickets", source: .asset, category: "Events"),
        .init(name: "movietix", source: .asset, category: "Events"),
        .init(name: "partyballoons", source: .asset, category: "Events"),
        .init(name: "partycal", source: .asset, category: "Events"),
        .init(name: "partyfavorbag", source: .asset, category: "Events"),
        .init(name: "popper", source: .asset, category: "Events"),

        // Favorites
        .init(name: "linesstar", source: .asset, category: "Favorites"),
        .init(name: "starbadge", source: .asset, category: "Favorites"),
        .init(name: "starbars", source: .asset, category: "Favorites"),
        .init(name: "starcard", source: .asset, category: "Favorites"),
        .init(name: "starcircle", source: .asset, category: "Favorites"),
        .init(name: "starfill", source: .asset, category: "Favorites"),
        .init(name: "starmark", source: .asset, category: "Favorites"),
        .init(name: "staroutline", source: .asset, category: "Favorites"),
        .init(name: "starwavy", source: .asset, category: "Favorites"),

        // Goals
        .init(name: "goalsparkle", source: .asset, category: "Goals"),
        .init(name: "loveflag", source: .asset, category: "Goals"),
        .init(name: "sparklesstarflag", source: .asset, category: "Goals"),
        .init(name: "starladder", source: .asset, category: "Goals"),
        .init(name: "startarget", source: .asset, category: "Goals"),

        // Halloween
        .init(name: "bat", source: .asset, category: "Halloween"),
        .init(name: "batcake", source: .asset, category: "Halloween"),
        .init(name: "batcal", source: .asset, category: "Halloween"),
        .init(name: "blackcat", source: .asset, category: "Halloween"),
        .init(name: "bones", source: .asset, category: "Halloween"),
        .init(name: "candybag", source: .asset, category: "Halloween"),
        .init(name: "cauldron", source: .asset, category: "Halloween"),
        .init(name: "coffin", source: .asset, category: "Halloween"),
        .init(name: "ghost", source: .asset, category: "Halloween"),
        .init(name: "ghostcal", source: .asset, category: "Halloween"),
        .init(name: "halloweeninvite", source: .asset, category: "Halloween"),
        .init(name: "hauntedhouse", source: .asset, category: "Halloween"),
        .init(name: "jackolantern", source: .asset, category: "Halloween"),
        .init(name: "lovepotion", source: .asset, category: "Halloween"),
        .init(name: "potion", source: .asset, category: "Halloween"),
        .init(name: "potionsign", source: .asset, category: "Halloween"),
        .init(name: "potionsparkle", source: .asset, category: "Halloween"),
        .init(name: "skullpotion", source: .asset, category: "Halloween"),
        .init(name: "tombstone", source: .asset, category: "Halloween"),
        .init(name: "witchhat", source: .asset, category: "Halloween"),

        // Health
        .init(name: "bandaidheart", source: .asset, category: "Health"),
        .init(name: "doublepills", source: .asset, category: "Health"),
        .init(name: "health", source: .asset, category: "Health"),
        .init(name: "healthoutline", source: .asset, category: "Health"),
        .init(name: "heartbaid", source: .asset, category: "Health"),
        .init(name: "heartoscope", source: .asset, category: "Health"),
        .init(name: "heartpulse", source: .asset, category: "Health"),
        .init(name: "kingtooth", source: .asset, category: "Health"),
        .init(name: "lovebandage", source: .asset, category: "Health"),
        .init(name: "lovebandaid", source: .asset, category: "Health"),
        .init(name: "loveoscope", source: .asset, category: "Health"),
        .init(name: "lovepills", source: .asset, category: "Health"),
        .init(name: "medhand", source: .asset, category: "Health"),
        .init(name: "medhouse", source: .asset, category: "Health"),
        .init(name: "medical", source: .asset, category: "Health"),
        .init(name: "medicalcross", source: .asset, category: "Health"),
        .init(name: "medication", source: .asset, category: "Health"),
        .init(name: "medsymbol", source: .asset, category: "Health"),
        .init(name: "mouthwash", source: .asset, category: "Health"),
        .init(name: "pillcapsules", source: .asset, category: "Health"),
        .init(name: "pilldrop", source: .asset, category: "Health"),
        .init(name: "pillhand", source: .asset, category: "Health"),
        .init(name: "pillorganizer", source: .asset, category: "Health"),
        .init(name: "pillpacket", source: .asset, category: "Health"),
        .init(name: "pillshand", source: .asset, category: "Health"),
        .init(name: "pillshands", source: .asset, category: "Health"),
        .init(name: "pillsleeve", source: .asset, category: "Health"),
        .init(name: "rxbottle", source: .asset, category: "Health"),
        .init(name: "sparkledrophands", source: .asset, category: "Health"),
        .init(name: "stethoscope", source: .asset, category: "Health"),
        .init(name: "tabletpill", source: .asset, category: "Health"),
        .init(name: "tabpill", source: .asset, category: "Health"),
        .init(name: "tabpillshand", source: .asset, category: "Health"),
        .init(name: "tooth", source: .asset, category: "Health"),
        .init(name: "toothburst", source: .asset, category: "Health"),
        .init(name: "toothhand", source: .asset, category: "Health"),
        .init(name: "toothhands", source: .asset, category: "Health"),
        .init(name: "toothset", source: .asset, category: "Health"),
        .init(name: "toothsparklehands", source: .asset, category: "Health"),
        .init(name: "toothypaste", source: .asset, category: "Health"),
        .init(name: "tpaste", source: .asset, category: "Health"),
        .init(name: "tubetoothpaste", source: .asset, category: "Health"),
        .init(name: "twopills", source: .asset, category: "Health"),
        .init(name: "weight", source: .asset, category: "Health"),

        // Home
        .init(name: "blackwindow", source: .asset, category: "Home"),
        .init(name: "dooropen", source: .asset, category: "Home"),
        .init(name: "exitdoor", source: .asset, category: "Home"),
        .init(name: "fireplace", source: .asset, category: "Home"),
        .init(name: "frontdoor", source: .asset, category: "Home"),
        .init(name: "garage", source: .asset, category: "Home"),
        .init(name: "houseoutline", source: .asset, category: "Home"),
        .init(name: "lamp", source: .asset, category: "Home"),
        .init(name: "lovehouse", source: .asset, category: "Home"),
        .init(name: "window", source: .asset, category: "Home"),
        .init(name: "windowheart", source: .asset, category: "Home"),

        // Hydration
        .init(name: "bottle", source: .asset, category: "Hydration"),
        .init(name: "bottlewater", source: .asset, category: "Hydration"),
        .init(name: "cutebottle", source: .asset, category: "Hydration"),
        .init(name: "dropfill", source: .asset, category: "Hydration"),
        .init(name: "glass", source: .asset, category: "Hydration"),
        .init(name: "jug", source: .asset, category: "Hydration"),
        .init(name: "lovebottle", source: .asset, category: "Hydration"),
        .init(name: "milkglass", source: .asset, category: "Hydration"),
        .init(name: "waterbottle", source: .asset, category: "Hydration"),

        // Info
        .init(name: "infowavy", source: .asset, category: "Info"),
        .init(name: "questionwavy", source: .asset, category: "Info"),
        .init(name: "warnwavy", source: .asset, category: "Info"),

        // Journal
        .init(name: "lockheartjournal", source: .asset, category: "Journal"),
        .init(name: "lovejournal", source: .asset, category: "Journal"),

        // Kids
        .init(name: "babyblock", source: .asset, category: "Kids"),
        .init(name: "bbypiano", source: .asset, category: "Kids"),
        .init(name: "childsrack", source: .asset, category: "Kids"),

        // Kitchen
        .init(name: "breadoven", source: .asset, category: "Kitchen"),
        .init(name: "cabinetshelf", source: .asset, category: "Kitchen"),
        .init(name: "coffeemaker", source: .asset, category: "Kitchen"),
        .init(name: "coffeemakermachine", source: .asset, category: "Kitchen"),
        .init(name: "diningdinnertable", source: .asset, category: "Kitchen"),
        .init(name: "diningtable", source: .asset, category: "Kitchen"),
        .init(name: "electricblender", source: .asset, category: "Kitchen"),
        .init(name: "expressomachine", source: .asset, category: "Kitchen"),
        .init(name: "foodrack", source: .asset, category: "Kitchen"),
        .init(name: "fridgefilled", source: .asset, category: "Kitchen"),
        .init(name: "kitchentable", source: .asset, category: "Kitchen"),
        .init(name: "lovemug", source: .asset, category: "Kitchen"),
        .init(name: "oven", source: .asset, category: "Kitchen"),
        .init(name: "popcorn", source: .asset, category: "Kitchen"),
        .init(name: "rainbowmug", source: .asset, category: "Kitchen"),
        .init(name: "refrigerator", source: .asset, category: "Kitchen"),
        .init(name: "silverware", source: .asset, category: "Kitchen"),
        .init(name: "singleblender", source: .asset, category: "Kitchen"),
        .init(name: "teacup", source: .asset, category: "Kitchen"),
        .init(name: "teapot", source: .asset, category: "Kitchen"),
        .init(name: "travelcoffee", source: .asset, category: "Kitchen"),
        .init(name: "whisk", source: .asset, category: "Kitchen"),

        // Links
        .init(name: "link", source: .asset, category: "Links"),
        .init(name: "linkcircle", source: .asset, category: "Links"),

        // Living Room
        .init(name: "armchair", source: .asset, category: "Living Room"),
        .init(name: "coffeetablefill", source: .asset, category: "Living Room"),
        .init(name: "endtablefill", source: .asset, category: "Living Room"),
        .init(name: "flatscreen", source: .asset, category: "Living Room"),
        .init(name: "flattv", source: .asset, category: "Living Room"),
        .init(name: "livingroomtvstand", source: .asset, category: "Living Room"),
        .init(name: "lovetv", source: .asset, category: "Living Room"),
        .init(name: "ottoman", source: .asset, category: "Living Room"),
        .init(name: "sidetable", source: .asset, category: "Living Room"),
        .init(name: "sofa", source: .asset, category: "Living Room"),
        .init(name: "television", source: .asset, category: "Living Room"),

        // Location
        .init(name: "lovelocation", source: .asset, category: "Location"),
        .init(name: "starlocation", source: .asset, category: "Location"),
        .init(name: "starpinlocation", source: .asset, category: "Location"),

        // Magic
        .init(name: "casemagic", source: .asset, category: "Magic"),

        // Mind
        .init(name: "cloudmind", source: .asset, category: "Mind"),
        .init(name: "lovemind", source: .asset, category: "Mind"),
        .init(name: "siwrlmind", source: .asset, category: "Mind"),

        // Misc
        .init(name: "deadcat", source: .asset, category: "Misc"),

        // Money
        .init(name: "coinpurse", source: .asset, category: "Money"),
        .init(name: "coinssparkle", source: .asset, category: "Money"),
        .init(name: "lovemoney", source: .asset, category: "Money"),
        .init(name: "moneybaghands", source: .asset, category: "Money"),
        .init(name: "moneybills", source: .asset, category: "Money"),
        .init(name: "monies", source: .asset, category: "Money"),
        .init(name: "pigbank", source: .asset, category: "Money"),
        .init(name: "threecoins", source: .asset, category: "Money"),
        .init(name: "visacard", source: .asset, category: "Money"),
        .init(name: "walletfill", source: .asset, category: "Money"),

        // Mood
        .init(name: "xsmile", source: .asset, category: "Mood"),

        // Movement
        .init(name: "feetprints", source: .asset, category: "Movement"),
        .init(name: "foot", source: .asset, category: "Movement"),
        .init(name: "shoe", source: .asset, category: "Movement"),
        .init(name: "workout", source: .asset, category: "Movement"),

        // Music
        .init(name: "lovemusicnote", source: .asset, category: "Music"),

        // Nature
        .init(name: "basketflowers", source: .asset, category: "Nature"),
        .init(name: "bug", source: .asset, category: "Nature"),
        .init(name: "caterpillar", source: .asset, category: "Nature"),
        .init(name: "cloudfill", source: .asset, category: "Nature"),
        .init(name: "cloudie", source: .asset, category: "Nature"),
        .init(name: "flower", source: .asset, category: "Nature"),
        .init(name: "flowerfilled", source: .asset, category: "Nature"),
        .init(name: "flowersheart", source: .asset, category: "Nature"),
        .init(name: "seedling", source: .asset, category: "Nature"),
        .init(name: "sun", source: .asset, category: "Nature"),
        .init(name: "sunflower", source: .asset, category: "Nature"),
        .init(name: "treeoutside", source: .asset, category: "Nature"),
        .init(name: "worldlove", source: .asset, category: "Nature"),
        .init(name: "yard", source: .asset, category: "Nature"),

        // Navigation
        .init(name: "arrowin", source: .asset, category: "Navigation"),
        .init(name: "arrowscircle", source: .asset, category: "Navigation"),
        .init(name: "backwavy", source: .asset, category: "Navigation"),
        .init(name: "chevdown", source: .asset, category: "Navigation"),
        .init(name: "chevleft", source: .asset, category: "Navigation"),
        .init(name: "chevright", source: .asset, category: "Navigation"),
        .init(name: "chevup", source: .asset, category: "Navigation"),
        .init(name: "crossroads", source: .asset, category: "Navigation"),
        .init(name: "dotswavy", source: .asset, category: "Navigation"),
        .init(name: "downwavy", source: .asset, category: "Navigation"),
        .init(name: "journey", source: .asset, category: "Navigation"),
        .init(name: "leftarrow", source: .asset, category: "Navigation"),
        .init(name: "leftwavy", source: .asset, category: "Navigation"),
        .init(name: "rightarrow", source: .asset, category: "Navigation"),
        .init(name: "rightwavy", source: .asset, category: "Navigation"),
        .init(name: "upwavy", source: .asset, category: "Navigation"),

        // Notes
        .init(name: "flipnotebook", source: .asset, category: "Notes"),
        .init(name: "linenotepage", source: .asset, category: "Notes"),
        .init(name: "notespen", source: .asset, category: "Notes"),
        .init(name: "pinnednote", source: .asset, category: "Notes"),
        .init(name: "starnote", source: .asset, category: "Notes"),
        .init(name: "sticknote", source: .asset, category: "Notes"),

        // Numbers
        .init(name: "0wavy", source: .asset, category: "Numbers"),
        .init(name: "1wavy", source: .asset, category: "Numbers"),
        .init(name: "2wavy", source: .asset, category: "Numbers"),
        .init(name: "3wavy", source: .asset, category: "Numbers"),
        .init(name: "4wavy", source: .asset, category: "Numbers"),
        .init(name: "5wavy", source: .asset, category: "Numbers"),
        .init(name: "6wavy", source: .asset, category: "Numbers"),
        .init(name: "7wavy", source: .asset, category: "Numbers"),
        .init(name: "8wavy", source: .asset, category: "Numbers"),
        .init(name: "9wavy", source: .asset, category: "Numbers"),

        // Objects
        .init(name: "bblocks", source: .asset, category: "Objects"),
        .init(name: "bbuildingblocks", source: .asset, category: "Objects"),
        .init(name: "blocks", source: .asset, category: "Objects"),
        .init(name: "blocksfill", source: .asset, category: "Objects"),
        .init(name: "buttons", source: .asset, category: "Objects"),
        .init(name: "objects", source: .asset, category: "Objects"),
        .init(name: "packagefill", source: .asset, category: "Objects"),
        .init(name: "puzzlehand", source: .asset, category: "Objects"),
        .init(name: "puzzlepiece", source: .asset, category: "Objects"),
        .init(name: "sign", source: .asset, category: "Objects"),
        .init(name: "starboxhand", source: .asset, category: "Objects"),
        .init(name: "starcirclecase", source: .asset, category: "Objects"),
        .init(name: "starrybox", source: .asset, category: "Objects"),
        .init(name: "starscase", source: .asset, category: "Objects"),
        .init(name: "starsparklesbox", source: .asset, category: "Objects"),
        .init(name: "threeboxes", source: .asset, category: "Objects"),
        .init(name: "trinket", source: .asset, category: "Objects"),

        // Organization
        .init(name: "inbox", source: .asset, category: "Organization"),

        // People
        .init(name: "groupfill", source: .asset, category: "People"),

        // Pets
        .init(name: "catface", source: .asset, category: "Pets"),
        .init(name: "catsleep", source: .asset, category: "Pets"),
        .init(name: "catstretch", source: .asset, category: "Pets"),
        .init(name: "circlepaw", source: .asset, category: "Pets"),
        .init(name: "dogface", source: .asset, category: "Pets"),
        .init(name: "dogstore", source: .asset, category: "Pets"),
        .init(name: "kennel", source: .asset, category: "Pets"),
        .init(name: "paw", source: .asset, category: "Pets"),
        .init(name: "petalarm", source: .asset, category: "Pets"),
        .init(name: "petbox", source: .asset, category: "Pets"),
        .init(name: "petfood", source: .asset, category: "Pets"),
        .init(name: "petmeddrops", source: .asset, category: "Pets"),
        .init(name: "petmeds", source: .asset, category: "Pets"),
        .init(name: "petpaw", source: .asset, category: "Pets"),
        .init(name: "petpills", source: .asset, category: "Pets"),
        .init(name: "petshampoo", source: .asset, category: "Pets"),
        .init(name: "petsoap", source: .asset, category: "Pets"),
        .init(name: "pettreat", source: .asset, category: "Pets"),
        .init(name: "vet", source: .asset, category: "Pets"),

        // Priority
        .init(name: "good", source: .asset, category: "Priority"),
        .init(name: "high", source: .asset, category: "Priority"),
        .init(name: "low", source: .asset, category: "Priority"),
        .init(name: "moderate", source: .asset, category: "Priority"),
        .init(name: "verylow", source: .asset, category: "Priority"),

        // Profile
        .init(name: "arrowsprofile", source: .asset, category: "Profile"),
        .init(name: "profileuser", source: .asset, category: "Profile"),
        .init(name: "profilewavy", source: .asset, category: "Profile"),
        .init(name: "usercircle", source: .asset, category: "Profile"),

        // Protection
        .init(name: "starshield", source: .asset, category: "Protection"),

        // Reading
        .init(name: "bookmark", source: .asset, category: "Reading"),
        .init(name: "bookstand", source: .asset, category: "Reading"),
        .init(name: "flatbook", source: .asset, category: "Reading"),
        .init(name: "handbook", source: .asset, category: "Reading"),
        .init(name: "linesbmark", source: .asset, category: "Reading"),
        .init(name: "linespiralbook", source: .asset, category: "Reading"),
        .init(name: "lovespiralbook", source: .asset, category: "Reading"),
        .init(name: "openbook", source: .asset, category: "Reading"),
        .init(name: "openlovebook", source: .asset, category: "Reading"),
        .init(name: "sparklesbook", source: .asset, category: "Reading"),
        .init(name: "starmarkbook", source: .asset, category: "Reading"),

        // Reminders
        .init(name: "arrowinfinity", source: .asset, category: "Reminders"),
        .init(name: "bellfill", source: .asset, category: "Reminders"),
        .init(name: "bells", source: .asset, category: "Reminders"),
        .init(name: "nonotifs", source: .asset, category: "Reminders"),
        .init(name: "repeat", source: .asset, category: "Reminders"),
        .init(name: "repeatarrows", source: .asset, category: "Reminders"),
        .init(name: "repeatfill", source: .asset, category: "Reminders"),

        // Rest
        .init(name: "moonzs", source: .asset, category: "Rest"),
        .init(name: "snooze", source: .asset, category: "Rest"),

        // Rewards
        .init(name: "handstrophy", source: .asset, category: "Rewards"),
        .init(name: "handtrophy", source: .asset, category: "Rewards"),
        .init(name: "levelup", source: .asset, category: "Rewards"),
        .init(name: "rewardscard", source: .asset, category: "Rewards"),
        .init(name: "stargift", source: .asset, category: "Rewards"),
        .init(name: "starhandtrophy", source: .asset, category: "Rewards"),
        .init(name: "starpopgift", source: .asset, category: "Rewards"),
        .init(name: "starsparklegift", source: .asset, category: "Rewards"),
        .init(name: "startickets", source: .asset, category: "Rewards"),
        .init(name: "startrophy", source: .asset, category: "Rewards"),
        .init(name: "startrophyfill", source: .asset, category: "Rewards"),
        .init(name: "startrophyhand", source: .asset, category: "Rewards"),
        .init(name: "startrophyhands", source: .asset, category: "Rewards"),
        .init(name: "trophycircle", source: .asset, category: "Rewards"),
        .init(name: "trophystar", source: .asset, category: "Rewards"),

        // Schedule
        .init(name: "blackcal", source: .asset, category: "Schedule"),
        .init(name: "calheart", source: .asset, category: "Schedule"),
        .init(name: "calhearts", source: .asset, category: "Schedule"),
        .init(name: "circlescal", source: .asset, category: "Schedule"),
        .init(name: "dotscal", source: .asset, category: "Schedule"),
        .init(name: "heartboxcal", source: .asset, category: "Schedule"),
        .init(name: "heartlinescal", source: .asset, category: "Schedule"),
        .init(name: "lovecalendar", source: .asset, category: "Schedule"),
        .init(name: "lovedate", source: .asset, category: "Schedule"),
        .init(name: "loveflipcal", source: .asset, category: "Schedule"),
        .init(name: "lovelycal", source: .asset, category: "Schedule"),
        .init(name: "numcal", source: .asset, category: "Schedule"),
        .init(name: "ringstarcal", source: .asset, category: "Schedule"),
        .init(name: "starcal", source: .asset, category: "Schedule"),
        .init(name: "starringcal", source: .asset, category: "Schedule"),
        .init(name: "xoxocal", source: .asset, category: "Schedule"),

        // Search
        .init(name: "lovesearch", source: .asset, category: "Search"),
        .init(name: "searchwavy", source: .asset, category: "Search"),
        .init(name: "sparklesearch", source: .asset, category: "Search"),

        // Security
        .init(name: "bearlockpassword", source: .asset, category: "Security"),
        .init(name: "circlefingerprint", source: .asset, category: "Security"),
        .init(name: "eye", source: .asset, category: "Security"),
        .init(name: "eyecircle", source: .asset, category: "Security"),
        .init(name: "eyeslash", source: .asset, category: "Security"),
        .init(name: "eyeslashcircle", source: .asset, category: "Security"),
        .init(name: "eyex", source: .asset, category: "Security"),
        .init(name: "fingerprint", source: .asset, category: "Security"),
        .init(name: "handkey", source: .asset, category: "Security"),
        .init(name: "heartlock", source: .asset, category: "Security"),
        .init(name: "heartunlock", source: .asset, category: "Security"),
        .init(name: "lockhearts", source: .asset, category: "Security"),
        .init(name: "lockpassword", source: .asset, category: "Security"),
        .init(name: "lockwavy", source: .asset, category: "Security"),
        .init(name: "password", source: .asset, category: "Security"),
        .init(name: "starskey", source: .asset, category: "Security"),

        // Self Care
        .init(name: "footcream", source: .asset, category: "Self Care"),
        .init(name: "footspa", source: .asset, category: "Self Care"),
        .init(name: "vanity", source: .asset, category: "Self Care"),

        // Settings
        .init(name: "cogwavy", source: .asset, category: "Settings"),
        .init(name: "settings", source: .asset, category: "Settings"),

        // Shopping
        .init(name: "corncrate", source: .asset, category: "Shopping"),
        .init(name: "foodbox", source: .asset, category: "Shopping"),
        .init(name: "groceries", source: .asset, category: "Shopping"),
        .init(name: "handbuggy", source: .asset, category: "Shopping"),
        .init(name: "loveshopbags", source: .asset, category: "Shopping"),
        .init(name: "market", source: .asset, category: "Shopping"),
        .init(name: "shopbasket", source: .asset, category: "Shopping"),
        .init(name: "starringtags", source: .asset, category: "Shopping"),
        .init(name: "starshopbags", source: .asset, category: "Shopping"),
        .init(name: "store", source: .asset, category: "Shopping"),

        // Social
        .init(name: "discord", source: .asset, category: "Social"),
        .init(name: "facebook", source: .asset, category: "Social"),
        .init(name: "instagram", source: .asset, category: "Social"),
        .init(name: "socialchat", source: .asset, category: "Social"),
        .init(name: "socialphone", source: .asset, category: "Social"),
        .init(name: "threads", source: .asset, category: "Social"),

        // Spirituality
        .init(name: "bearpoppet", source: .asset, category: "Spirituality"),
        .init(name: "candlebra", source: .asset, category: "Spirituality"),
        .init(name: "candleslit", source: .asset, category: "Spirituality"),
        .init(name: "celestialbook", source: .asset, category: "Spirituality"),
        .init(name: "cloudsparkleball", source: .asset, category: "Spirituality"),
        .init(name: "crystalball", source: .asset, category: "Spirituality"),
        .init(name: "grimoire", source: .asset, category: "Spirituality"),
        .init(name: "lovedeck", source: .asset, category: "Spirituality"),
        .init(name: "planet", source: .asset, category: "Spirituality"),
        .init(name: "starchalice", source: .asset, category: "Spirituality"),
        .init(name: "tarot", source: .asset, category: "Spirituality"),
        .init(name: "tarotcards", source: .asset, category: "Spirituality"),
        .init(name: "wand", source: .asset, category: "Spirituality"),

        // Stats
        .init(name: "boltprogress", source: .asset, category: "Stats"),
        .init(name: "boltprogressbar", source: .asset, category: "Stats"),
        .init(name: "chartcircle", source: .asset, category: "Stats"),
        .init(name: "chartdown", source: .asset, category: "Stats"),
        .init(name: "chartup", source: .asset, category: "Stats"),
        .init(name: "loveprogressbar", source: .asset, category: "Stats"),
        .init(name: "percentwavy", source: .asset, category: "Stats"),
        .init(name: "sparklearrowprogress", source: .asset, category: "Stats"),
        .init(name: "sparkleprogress", source: .asset, category: "Stats"),
        .init(name: "starchart", source: .asset, category: "Stats"),
        .init(name: "starprogress", source: .asset, category: "Stats"),
        .init(name: "starprogressbar", source: .asset, category: "Stats"),

        // Tags
        .init(name: "circledothashtag", source: .asset, category: "Tags"),
        .init(name: "hashtag", source: .asset, category: "Tags"),
        .init(name: "hashtagwavy", source: .asset, category: "Tags"),
        .init(name: "hearttag", source: .asset, category: "Tags"),
        .init(name: "lovetag", source: .asset, category: "Tags"),
        .init(name: "tagsparkle", source: .asset, category: "Tags"),
        .init(name: "tagstar", source: .asset, category: "Tags"),

        // Tasks
        .init(name: "blovelist", source: .asset, category: "Tasks"),
        .init(name: "bulletheartlist", source: .asset, category: "Tasks"),
        .init(name: "heartblist", source: .asset, category: "Tasks"),
        .init(name: "listcircle", source: .asset, category: "Tasks"),
        .init(name: "lovelist", source: .asset, category: "Tasks"),
        .init(name: "markcircle", source: .asset, category: "Tasks"),
        .init(name: "starblist", source: .asset, category: "Tasks"),

        // Tech
        .init(name: "appsphone", source: .asset, category: "Tech"),
        .init(name: "cellphone", source: .asset, category: "Tech"),
        .init(name: "cloudsync", source: .asset, category: "Tech"),
        .init(name: "device", source: .asset, category: "Tech"),
        .init(name: "lovebrowser", source: .asset, category: "Tech"),
        .init(name: "lovelaptop", source: .asset, category: "Tech"),
        .init(name: "mediaphone", source: .asset, category: "Tech"),
        .init(name: "nophones", source: .asset, category: "Tech"),
        .init(name: "photocam", source: .asset, category: "Tech"),
        .init(name: "sparkledevice", source: .asset, category: "Tech"),
        .init(name: "videocam", source: .asset, category: "Tech"),
        .init(name: "webcircle", source: .asset, category: "Tech"),

        // Time
        .init(name: "5mins", source: .asset, category: "Time"),
        .init(name: "15mins", source: .asset, category: "Time"),
        .init(name: "30mins", source: .asset, category: "Time"),
        .init(name: "clockfill", source: .asset, category: "Time"),
        .init(name: "clockwavy", source: .asset, category: "Time"),
        .init(name: "hourglassfill", source: .asset, category: "Time"),
        .init(name: "hourormore", source: .asset, category: "Time"),
        .init(name: "sparkletimeglass", source: .asset, category: "Time"),
        .init(name: "timebook", source: .asset, category: "Time"),
        .init(name: "timehand", source: .asset, category: "Time"),

        // Tools
        .init(name: "tools", source: .asset, category: "Tools"),
        .init(name: "toolsfilled", source: .asset, category: "Tools"),

        // Wedding
        .init(name: "wedcard", source: .asset, category: "Wedding"),
        .init(name: "wedinvite", source: .asset, category: "Wedding"),

        // Wellness
        .init(name: "balancewavy", source: .asset, category: "Wellness"),
        .init(name: "lovesmokes", source: .asset, category: "Wellness"),
        .init(name: "meditate", source: .asset, category: "Wellness"),
        .init(name: "zenrocks", source: .asset, category: "Wellness"),

        // Whimsy
        .init(name: "floatlove", source: .asset, category: "Whimsy"),
        .init(name: "heartballoon", source: .asset, category: "Whimsy"),
        .init(name: "loveairballoon", source: .asset, category: "Whimsy"),
        .init(name: "rainbow", source: .asset, category: "Whimsy"),
        .init(name: "rainbowclouds", source: .asset, category: "Whimsy"),
        .init(name: "sparkle", source: .asset, category: "Whimsy"),
        .init(name: "sparklecircle", source: .asset, category: "Whimsy"),
        .init(name: "starry", source: .asset, category: "Whimsy"),
        .init(name: "starwindow", source: .asset, category: "Whimsy"),

        // Work
        .init(name: "lovecase", source: .asset, category: "Work"),
        .init(name: "office", source: .asset, category: "Work"),

        // Writing
        .init(name: "linespencil", source: .asset, category: "Writing"),
        .init(name: "pencil", source: .asset, category: "Writing"),
        .init(name: "pencilcircle", source: .asset, category: "Writing"),
        .init(name: "pencilinlines", source: .asset, category: "Writing"),
        .init(name: "pencilsoverlap", source: .asset, category: "Writing"),
        .init(name: "plainpencil", source: .asset, category: "Writing"),
        .init(name: "qwill", source: .asset, category: "Writing"),
        .init(name: "quote", source: .asset, category: "Writing"),
        .init(name: "sigpencil", source: .asset, category: "Writing"),
        .init(name: "sparklespencil", source: .asset, category: "Writing"),
        .init(name: "twopencils", source: .asset, category: "Writing"),
        .init(name: "writefeather", source: .asset, category: "Writing"),
        .init(name: "writenote", source: .asset, category: "Writing"),
        .init(name: "writepen", source: .asset, category: "Writing"),
        .init(name: "writepencil", source: .asset, category: "Writing"),
        .init(name: "writingpencil", source: .asset, category: "Writing"),

        // Zodiac
        .init(name: "aquarius", source: .asset, category: "Zodiac"),
        .init(name: "aries", source: .asset, category: "Zodiac"),
        .init(name: "cancer", source: .asset, category: "Zodiac"),
        .init(name: "capricorn", source: .asset, category: "Zodiac"),
        .init(name: "gemini", source: .asset, category: "Zodiac"),
        .init(name: "leo", source: .asset, category: "Zodiac"),
        .init(name: "libra", source: .asset, category: "Zodiac"),
        .init(name: "pisces", source: .asset, category: "Zodiac"),
        .init(name: "sagittarius", source: .asset, category: "Zodiac"),
        .init(name: "scorpio", source: .asset, category: "Zodiac"),
        .init(name: "taurus", source: .asset, category: "Zodiac"),
        .init(name: "virgo", source: .asset, category: "Zodiac"),
    ]

    // MARK: - Combined Library (assets only — no SF Symbols)

    static let allIcons: [LureliaIconItem] = uniqueRenderableIcons(assetIcons)

    private static let iconsByName: [String: LureliaIconItem] = {
        var result: [String: LureliaIconItem] = [:]

        for icon in allIcons where result[icon.name] == nil {
            result[icon.name] = icon
        }

        return result
    }()

    static var categories: [String] {
        Array(Set(allIcons.map(\.category))).sorted()
    }

    static func icons(in category: String) -> [LureliaIconItem] {
        allIcons.filter { $0.category == category }
    }

    static func icon(named name: String) -> LureliaIconItem? {
        iconsByName[name.trimmingCharacters(in: .whitespacesAndNewlines)]
    }

    static func search(_ query: String) -> [LureliaIconItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedQuery.isEmpty else {
            return allIcons
        }

        return allIcons.filter {
            $0.name.localizedCaseInsensitiveContains(trimmedQuery)
            || $0.category.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    private static func uniqueRenderableIcons(_ icons: [LureliaIconItem]) -> [LureliaIconItem] {
        var seenIDs = Set<String>()

        return icons.filter { icon in
            guard seenIDs.insert(icon.id).inserted else {
                return false
            }

            return isRenderable(icon)
        }
    }

    private static func isRenderable(_ icon: LureliaIconItem) -> Bool {
        switch icon.source {
        case .asset:
            return UIImage(named: icon.name) != nil
        case .sfSymbol:
            return UIImage(systemName: icon.name) != nil
        }
    }
}
