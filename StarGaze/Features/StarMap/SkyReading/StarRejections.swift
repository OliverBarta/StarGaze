/// How many candidate peaks each rule threw out (for tuning).
nonisolated struct StarRejections: Sendable, Equatable {
    var hotPixels = 0
    var tooLarge = 0
    var saturated = 0
    var elongated = 0
    var atEdge = 0

    var total: Int { hotPixels + tooLarge + saturated + elongated + atEdge }
}
