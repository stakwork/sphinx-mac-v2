//
//  Timezone.swift
//  sphinx
//
//  Created by Tomas Timinskas on 13/05/2025.
//  Copyright © 2025 Tomas Timinskas. All rights reserved.
//

import Foundation

extension TimeZone {
    func gmtOffsetAbbreviation() -> String {
        let totalMinutes = self.secondsFromGMT(for: Date()) / 60
        let hours = totalMinutes / 60
        let minutes = abs(totalMinutes % 60)
        
        let sign = hours >= 0 ? "+" : "-"
        let absHours = abs(hours)

        if minutes == 0 {
            return "GMT\(sign)\(absHours)"
        } else {
            return String(format: "GMT%@%d:%02d", sign, absHours, minutes)
        }
    }
}
