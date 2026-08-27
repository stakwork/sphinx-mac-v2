//
//  NSImageView.swift
//  Sphinx
//
//  Created by Tomas Timinskas on 17/02/2021.
//  Copyright © 2021 Tomas Timinskas. All rights reserved.
//

import Cocoa

extension NSImageView {
    func loadGifWith(name: String) {
        if let url = Bundle.main.url(forResource: name, withExtension: "gif") {
            do {
                let data = try Data(contentsOf: url)
                
                let bounds = self.bounds

                DispatchQueue.global(qos: .background).async { [weak self] in
                    if let animation = data.createGIFAnimation() {
                        DispatchQueue.main.async {
                            guard let self = self else {
                                return
                            }

                            let imageLayer = CAShapeLayer()
                            imageLayer.contentsGravity = .resizeAspectFill
                            imageLayer.frame = bounds
                            imageLayer.add(animation, forKey: "contents")

                            self.wantsLayer = true
                            self.layer?.masksToBounds = false
                            self.layer?.addSublayer(imageLayer)
                        }
                    }
                }
            } catch {
                print("Error")
            }
        }
    }
}
