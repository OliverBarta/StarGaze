import SwiftUI

enum Hemisphere: String { case north, south }

struct Constellation: Identifiable, Hashable {
    let id: String          // IAU abbreviation, e.g. "Ori"
    let name: String
    let genitive: String
    let imageName: String   // asset in Constellations.xcassets
    let hemisphere: Hemisphere
    let accentHex: String
    let starCount: Int

    var accent: Color {
        let v = Int(accentHex.dropFirst(), radix: 16) ?? 0xFFFFFF
        return Color(red: Double((v >> 16) & 0xFF) / 255,
                     green: Double((v >> 8) & 0xFF) / 255,
                     blue: Double(v & 0xFF) / 255)
    }

    static let all: [Constellation] = [
        Constellation(id: "And", name: "Andromeda", genitive: "Andromedae", imageName: "constellation_andromeda", hemisphere: .north, accentHex: "#f26868", starCount: 17),
        Constellation(id: "Ant", name: "Antlia", genitive: "Antliae", imageName: "constellation_antlia", hemisphere: .south, accentHex: "#6890f2", starCount: 3),
        Constellation(id: "Aps", name: "Apus", genitive: "Apodis", imageName: "constellation_apus", hemisphere: .south, accentHex: "#b8f268", starCount: 4),
        Constellation(id: "Aqr", name: "Aquarius", genitive: "Aquarii", imageName: "constellation_aquarius", hemisphere: .south, accentHex: "#f268e1", starCount: 15),
        Constellation(id: "Aql", name: "Aquila", genitive: "Aquilae", imageName: "constellation_aquila", hemisphere: .north, accentHex: "#68f2db", starCount: 8),
        Constellation(id: "Ara", name: "Ara", genitive: "Arae", imageName: "constellation_ara", hemisphere: .south, accentHex: "#f2b368", starCount: 7),
        Constellation(id: "Ari", name: "Aries", genitive: "Arietis", imageName: "constellation_aries", hemisphere: .north, accentHex: "#8a68f2", starCount: 4),
        Constellation(id: "Aur", name: "Auriga", genitive: "Aurigae", imageName: "constellation_auriga", hemisphere: .north, accentHex: "#6df268", starCount: 9),
        Constellation(id: "Boo", name: "Boötes", genitive: "Boötis", imageName: "constellation_bootes", hemisphere: .north, accentHex: "#f26896", starCount: 12),
        Constellation(id: "Cae", name: "Caelum", genitive: "Caeli", imageName: "constellation_caelum", hemisphere: .south, accentHex: "#68bef2", starCount: 4),
        Constellation(id: "Cam", name: "Camelopardalis", genitive: "Camelopardalis", imageName: "constellation_camelopardalis", hemisphere: .north, accentHex: "#e7f268", starCount: 8),
        Constellation(id: "Cnc", name: "Cancer", genitive: "Cancri", imageName: "constellation_cancer", hemisphere: .north, accentHex: "#d568f2", starCount: 5),
        Constellation(id: "CVn", name: "Canes Venatici", genitive: "Canum Venaticorum", imageName: "constellation_canes_venatici", hemisphere: .north, accentHex: "#68f2ad", starCount: 2),
        Constellation(id: "CMa", name: "Canis Major", genitive: "Canis Majoris", imageName: "constellation_canis_major", hemisphere: .south, accentHex: "#f28468", starCount: 11),
        Constellation(id: "CMi", name: "Canis Minor", genitive: "Canis Minoris", imageName: "constellation_canis_minor", hemisphere: .north, accentHex: "#6873f2", starCount: 2),
        Constellation(id: "Cap", name: "Capricornus", genitive: "Capricorni", imageName: "constellation_capricornus", hemisphere: .south, accentHex: "#9cf268", starCount: 10),
        Constellation(id: "Car", name: "Carina", genitive: "Carinae", imageName: "constellation_carina", hemisphere: .south, accentHex: "#f268c4", starCount: 17),
        Constellation(id: "Cas", name: "Cassiopeia", genitive: "Cassiopeiae", imageName: "constellation_cassiopeia", hemisphere: .north, accentHex: "#68edf2", starCount: 5),
        Constellation(id: "Cen", name: "Centaurus", genitive: "Centauri", imageName: "constellation_centaurus", hemisphere: .south, accentHex: "#f2cf68", starCount: 16),
        Constellation(id: "Cep", name: "Cepheus", genitive: "Cephei", imageName: "constellation_cepheus", hemisphere: .north, accentHex: "#a768f2", starCount: 10),
        Constellation(id: "Cet", name: "Cetus", genitive: "Ceti", imageName: "constellation_cetus", hemisphere: .south, accentHex: "#68f27e", starCount: 14),
        Constellation(id: "Cha", name: "Chamaeleon", genitive: "Chamaeleontis", imageName: "constellation_chamaeleon", hemisphere: .south, accentHex: "#f26879", starCount: 5),
        Constellation(id: "Cir", name: "Circinus", genitive: "Circini", imageName: "constellation_circinus", hemisphere: .south, accentHex: "#68a2f2", starCount: 3),
        Constellation(id: "Col", name: "Columba", genitive: "Columbae", imageName: "constellation_columba", hemisphere: .south, accentHex: "#caf268", starCount: 5),
        Constellation(id: "Com", name: "Coma Berenices", genitive: "Comae Berenices", imageName: "constellation_coma_berenices", hemisphere: .north, accentHex: "#f268f2", starCount: 3),
        Constellation(id: "CrA", name: "Corona Austrina", genitive: "Coronae Austrini", imageName: "constellation_corona_austrina", hemisphere: .south, accentHex: "#68f2c9", starCount: 8),
        Constellation(id: "CrB", name: "Corona Borealis", genitive: "Coronae Borealis", imageName: "constellation_corona_borealis", hemisphere: .north, accentHex: "#f2a168", starCount: 7),
        Constellation(id: "Crv", name: "Corvus", genitive: "Corvi", imageName: "constellation_corvus", hemisphere: .south, accentHex: "#7868f2", starCount: 5),
        Constellation(id: "Crt", name: "Crater", genitive: "Crateris", imageName: "constellation_crater", hemisphere: .south, accentHex: "#7ff268", starCount: 9),
        Constellation(id: "Cru", name: "Crux", genitive: "Crux", imageName: "constellation_crux", hemisphere: .south, accentHex: "#f268a8", starCount: 4),
        Constellation(id: "Cyg", name: "Cygnus", genitive: "Cygni", imageName: "constellation_cygnus", hemisphere: .north, accentHex: "#68d0f2", starCount: 9),
        Constellation(id: "Del", name: "Delphinus", genitive: "Delphini", imageName: "constellation_delphinus", hemisphere: .north, accentHex: "#f2ec68", starCount: 5),
        Constellation(id: "Dor", name: "Dorado", genitive: "Doradus", imageName: "constellation_dorado", hemisphere: .south, accentHex: "#c368f2", starCount: 6),
        Constellation(id: "Dra", name: "Draco", genitive: "Draconis", imageName: "constellation_draco", hemisphere: .north, accentHex: "#68f29b", starCount: 15),
        Constellation(id: "Equ", name: "Equuleus", genitive: "Equulei", imageName: "constellation_equuleus", hemisphere: .north, accentHex: "#f27268", starCount: 3),
        Constellation(id: "Eri", name: "Eridanus", genitive: "Eridani", imageName: "constellation_eridanus", hemisphere: .south, accentHex: "#6885f2", starCount: 27),
        Constellation(id: "For", name: "Fornax", genitive: "Fornacis", imageName: "constellation_fornax", hemisphere: .south, accentHex: "#aef268", starCount: 3),
        Constellation(id: "Gem", name: "Gemini", genitive: "Geminorum", imageName: "constellation_gemini", hemisphere: .north, accentHex: "#f268d6", starCount: 12),
        Constellation(id: "Gru", name: "Grus", genitive: "Gruis", imageName: "constellation_grus", hemisphere: .south, accentHex: "#68f2e6", starCount: 9),
        Constellation(id: "Her", name: "Hercules", genitive: "Herculis", imageName: "constellation_hercules", hemisphere: .north, accentHex: "#f2be68", starCount: 17),
        Constellation(id: "Hor", name: "Horologium", genitive: "Horologii", imageName: "constellation_horologium", hemisphere: .south, accentHex: "#9568f2", starCount: 6),
        Constellation(id: "Hya", name: "Hydra", genitive: "Hydrae", imageName: "constellation_hydra", hemisphere: .south, accentHex: "#68f26d", starCount: 18),
        Constellation(id: "Hyi", name: "Hydrus", genitive: "Hydri", imageName: "constellation_hydrus", hemisphere: .south, accentHex: "#f2688b", starCount: 6),
        Constellation(id: "Ind", name: "Indus", genitive: "Indi", imageName: "constellation_indus", hemisphere: .south, accentHex: "#68b3f2", starCount: 5),
        Constellation(id: "Lac", name: "Lacerta", genitive: "Lacertae", imageName: "constellation_lacerta", hemisphere: .north, accentHex: "#dcf268", starCount: 9),
        Constellation(id: "Leo", name: "Leo", genitive: "Leonis", imageName: "constellation_leo", hemisphere: .north, accentHex: "#e068f2", starCount: 9),
        Constellation(id: "LMi", name: "Leo Minor", genitive: "Leonis Minoris", imageName: "constellation_leo_minor", hemisphere: .north, accentHex: "#68f2b8", starCount: 5),
        Constellation(id: "Lep", name: "Lepus", genitive: "Leporis", imageName: "constellation_lepus", hemisphere: .south, accentHex: "#f28f68", starCount: 11),
        Constellation(id: "Lib", name: "Libra", genitive: "Librae", imageName: "constellation_libra", hemisphere: .south, accentHex: "#6868f2", starCount: 6),
        Constellation(id: "Lup", name: "Lupus", genitive: "Lupi", imageName: "constellation_lupus", hemisphere: .south, accentHex: "#91f268", starCount: 12),
        Constellation(id: "Lyn", name: "Lynx", genitive: "Lyncis", imageName: "constellation_lynx", hemisphere: .north, accentHex: "#f268b9", starCount: 7),
        Constellation(id: "Lyr", name: "Lyra", genitive: "Lyrae", imageName: "constellation_lyra", hemisphere: .north, accentHex: "#68e2f2", starCount: 6),
        Constellation(id: "Men", name: "Mensa", genitive: "Mensae", imageName: "constellation_mensa", hemisphere: .south, accentHex: "#f2da68", starCount: 4),
        Constellation(id: "Mic", name: "Microscopium", genitive: "Microscopii", imageName: "constellation_microscopium", hemisphere: .south, accentHex: "#b268f2", starCount: 5),
        Constellation(id: "Mon", name: "Monoceros", genitive: "Monocerotis", imageName: "constellation_monoceros", hemisphere: .south, accentHex: "#68f289", starCount: 9),
        Constellation(id: "Mus", name: "Musca", genitive: "Muscae", imageName: "constellation_musca", hemisphere: .south, accentHex: "#f2686e", starCount: 6),
        Constellation(id: "Nor", name: "Norma", genitive: "Normae", imageName: "constellation_norma", hemisphere: .south, accentHex: "#6897f2", starCount: 4),
        Constellation(id: "Oct", name: "Octans", genitive: "Octantis", imageName: "constellation_octans", hemisphere: .south, accentHex: "#bff268", starCount: 3),
        Constellation(id: "Oph", name: "Ophiuchus", genitive: "Ophiuchi", imageName: "constellation_ophiuchus", hemisphere: .south, accentHex: "#f268e8", starCount: 16),
        Constellation(id: "Ori", name: "Orion", genitive: "Orionis", imageName: "constellation_orion", hemisphere: .north, accentHex: "#68f2d4", starCount: 23),
        Constellation(id: "Pav", name: "Pavo", genitive: "Pavonis", imageName: "constellation_pavo", hemisphere: .south, accentHex: "#f2ac68", starCount: 10),
        Constellation(id: "Peg", name: "Pegasus", genitive: "Pegasi", imageName: "constellation_pegasus", hemisphere: .north, accentHex: "#8368f2", starCount: 14),
        Constellation(id: "Per", name: "Perseus", genitive: "Persei", imageName: "constellation_perseus", hemisphere: .north, accentHex: "#74f268", starCount: 23),
        Constellation(id: "Phe", name: "Phoenix", genitive: "Phoenicis", imageName: "constellation_phoenix", hemisphere: .south, accentHex: "#f2689d", starCount: 6),
        Constellation(id: "Pic", name: "Pictor", genitive: "Pictoris", imageName: "constellation_pictor", hemisphere: .south, accentHex: "#68c5f2", starCount: 3),
        Constellation(id: "Psc", name: "Pisces", genitive: "Piscium", imageName: "constellation_pisces", hemisphere: .north, accentHex: "#eef268", starCount: 22),
        Constellation(id: "PsA", name: "Piscis Austrinus", genitive: "Piscis Austrini", imageName: "constellation_piscis_austrinus", hemisphere: .south, accentHex: "#ce68f2", starCount: 8),
        Constellation(id: "Pup", name: "Puppis", genitive: "Puppis", imageName: "constellation_puppis", hemisphere: .south, accentHex: "#68f2a6", starCount: 11),
        Constellation(id: "Pyx", name: "Pyxis", genitive: "Pyxidis", imageName: "constellation_pyxis", hemisphere: .south, accentHex: "#f27d68", starCount: 4),
        Constellation(id: "Ret", name: "Reticulum", genitive: "Reticuli", imageName: "constellation_reticulum", hemisphere: .south, accentHex: "#687af2", starCount: 4),
        Constellation(id: "Sge", name: "Sagitta", genitive: "Sagittae", imageName: "constellation_sagitta", hemisphere: .north, accentHex: "#a3f268", starCount: 4),
        Constellation(id: "Sgr", name: "Sagittarius", genitive: "Sagittarii", imageName: "constellation_sagittarius", hemisphere: .south, accentHex: "#f268cb", starCount: 25),
        Constellation(id: "Sco", name: "Scorpius", genitive: "Scorpii", imageName: "constellation_scorpius", hemisphere: .south, accentHex: "#68f2f1", starCount: 14),
        Constellation(id: "Scl", name: "Sculptor", genitive: "Sculptoris", imageName: "constellation_sculptor", hemisphere: .south, accentHex: "#f2c868", starCount: 4),
        Constellation(id: "Sct", name: "Scutum", genitive: "Scuti", imageName: "constellation_scutum", hemisphere: .south, accentHex: "#a068f2", starCount: 4),
        Constellation(id: "Ser", name: "Serpens Cauda", genitive: "Serpentis", imageName: "constellation_serpens_cauda", hemisphere: .north, accentHex: "#68f278", starCount: 14),
        Constellation(id: "Sex", name: "Sextans", genitive: "Sextantis", imageName: "constellation_sextans", hemisphere: .south, accentHex: "#f26880", starCount: 4),
        Constellation(id: "Tau", name: "Taurus", genitive: "Tauri", imageName: "constellation_taurus", hemisphere: .north, accentHex: "#68a9f2", starCount: 12),
        Constellation(id: "Tel", name: "Telescopium", genitive: "Telescopii", imageName: "constellation_telescopium", hemisphere: .south, accentHex: "#d1f268", starCount: 3),
        Constellation(id: "Tri", name: "Triangulum", genitive: "Trianguli", imageName: "constellation_triangulum", hemisphere: .north, accentHex: "#eb68f2", starCount: 3),
        Constellation(id: "TrA", name: "Triangulum Australe", genitive: "Trianguli Australis", imageName: "constellation_triangulum_australe", hemisphere: .south, accentHex: "#68f2c3", starCount: 3),
        Constellation(id: "Tuc", name: "Tucana", genitive: "Tucanae", imageName: "constellation_tucana", hemisphere: .south, accentHex: "#f29a68", starCount: 6),
        Constellation(id: "UMa", name: "Ursa Major", genitive: "Ursae Majoris", imageName: "constellation_ursa_major", hemisphere: .north, accentHex: "#7268f2", starCount: 20),
        Constellation(id: "UMi", name: "Ursa Minor", genitive: "Ursae Minoris", imageName: "constellation_ursa_minor", hemisphere: .north, accentHex: "#86f268", starCount: 7),
        Constellation(id: "Vel", name: "Vela", genitive: "Velorum", imageName: "constellation_vela", hemisphere: .south, accentHex: "#f268ae", starCount: 8),
        Constellation(id: "Vir", name: "Virgo", genitive: "Virginis", imageName: "constellation_virgo", hemisphere: .south, accentHex: "#68d7f2", starCount: 13),
        Constellation(id: "Vol", name: "Volans", genitive: "Volantis", imageName: "constellation_volans", hemisphere: .south, accentHex: "#f2e568", starCount: 5),
        Constellation(id: "Vul", name: "Vulpecula", genitive: "Vulpeculae", imageName: "constellation_vulpecula", hemisphere: .north, accentHex: "#bd68f2", starCount: 5)
    ]
}

/// Collection tile: full colour when collected, dimmed silhouette when locked.
struct ConstellationBadge: View {
    let constellation: Constellation
    var isCollected: Bool = true

    var body: some View {
        VStack(spacing: 8) {
            Image(constellation.imageName)
                .resizable()
                .scaledToFit()
                .grayscale(isCollected ? 0 : 1)
                .opacity(isCollected ? 1 : 0.25)
            Text(isCollected ? constellation.name : "???")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isCollected ? constellation.accent : .secondary)
        }
    }
}

struct ConstellationCollectionView: View {
    var collected: Set<String> = []
    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(Constellation.all) { c in
                    ConstellationBadge(constellation: c, isCollected: collected.contains(c.id))
                }
            }
            .padding()
        }
        .background(Color(red: 0.04, green: 0.06, blue: 0.13).ignoresSafeArea())
    }
}

#Preview { ConstellationCollectionView(collected: ["Ori", "UMa", "Cas", "Sco", "Cyg"]) }
