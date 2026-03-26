import Foundation


extension PodcastModel {
    @MainActor var suggestedSats: Int { Int(round(suggestedBTC * Double(Constants.satoshisInBTC))) }
}
