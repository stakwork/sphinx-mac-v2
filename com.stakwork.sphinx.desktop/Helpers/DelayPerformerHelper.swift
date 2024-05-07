//
//  DelayPerformerHelper.swift
//  com.stakwork.sphinx.desktop
//
//  Created by Tomas Timinskas on 11/05/2020.
//  Copyright © 2020 Sphinx. All rights reserved.
//

import Foundation

class DelayPerformedHelper {
    
    public static func performAfterDelay(seconds: Double, completion: @escaping () -> ()) {
        let delayTime = DispatchTime.now() + Double(Int64(seconds * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
        DispatchQueue.main.asyncAfter(deadline: delayTime) {
            completion()
        }
    }
    
}
