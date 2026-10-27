//
//  ImageView.swift
//  ChatUIKit
//
//  Created by 朱继超 on 2023/9/1.
//

import UIKit
import ImageIO
import Combine

/// A subclass of `UIImageView` that provides a method for loading an image from a URL.
@objc final public class ImageView: UIImageView {

    private var imageRequest: AnyCancellable?
    private var representedURL: URL?
    private var requestID = UUID()
    private var loadedImage: UIImage?
    private var isLoading = false
    private var completions: [(UIImage?) -> Void] = []

    public override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Rebinding the same URL keeps the loaded image or its in-flight request.
    @MainActor public func image(with url: String, placeHolder: UIImage?) {
        self.loadImage(url: url, placeholder: placeHolder, completion: nil)
    }

    @MainActor public func image(with url: String, placeHolder: UIImage?, loadFinished: @escaping (UIImage?) -> Void) {
        self.loadImage(url: url, placeholder: placeHolder, completion: loadFinished)
    }

    /// Stop callbacks while a cell is in the reuse pool, retaining its displayed/cached image.
    @MainActor func cancelPendingImageLoad() {
        self.requestID = UUID()
        self.imageRequest?.cancel()
        self.imageRequest = nil
        self.completions.removeAll()
        self.isLoading = false
    }

    private func loadImage(url: String, placeholder: UIImage?, completion: ((UIImage?) -> Void)?) {
        let imageURL = Self.remoteURL(from: url)
        if let imageURL = imageURL, imageURL == self.representedURL {
            if let image = self.loadedImage {
                self.display(image)
                completion?(image)
                return
            }
            if self.isLoading {
                if let completion = completion { self.completions.append(completion) }
                self.display(placeholder)
                return
            }
        }

        // Invalidate before cancelling: a reused view must never receive its previous image.
        self.cancelPendingImageLoad()
        self.loadedImage = nil
        self.representedURL = imageURL
        guard let imageURL = imageURL else {
            self.display(placeholder)
            completion?(nil)
            return
        }

        // Read the cache before touching the visible image, including disk cache hits.
        if let image = ImageCacheManager.shared.image(for: imageURL.absoluteString) {
            self.loadedImage = image
            self.display(image)
            completion?(image)
            return
        }
        self.display(placeholder)
        self.isLoading = true
        if let completion = completion { self.completions.append(completion) }
        let requestID = self.requestID
        self.imageRequest = ImageLoader.shared.loadImage(from: imageURL)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] image in
                guard let self = self, self.requestID == requestID else { return }
                self.imageRequest = nil
                self.isLoading = false
                if let image = image, image.size != .zero {
                    self.loadedImage = image
                    self.display(image)
                }
                // Failure keeps this view's own placeholder; it must not adopt a global avatar.
                let completions = self.completions
                self.completions.removeAll()
                completions.forEach { $0(image) }
            }
    }

    private func display(_ image: UIImage?) {
        if self.image !== image { self.image = image }
    }

    private static func remoteURL(from value: String) -> URL? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let address = value.contains("://") ? value : "https://" + value
        guard var components = URLComponents(string: address),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty else { return nil }
        // Preserve path/query case, particularly object-storage signatures and expiring URLs.
        components.scheme = "https"
        return components.url
    }
}

extension ImageView {
    public func loadGif(from path: String) {
        DispatchQueue.global().async {
//            let cachedKey = NSString(string: path)
            
            if let cachedImage = ImageCacheManager.shared.image(for: path) {
                DispatchQueue.main.async {
                    self.image = cachedImage
                }
            } else {
                let image = UIImage.gif(from: path)
                if let image = image {
                    ImageCacheManager.shared.cacheImage(image, for: path)
                }
                DispatchQueue.main.async {
                    self.image = image
                }
            }
        }
    }
}

extension UIImage {
    
    public class func gif(from path: String) -> UIImage? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            consoleLogInfo("SwiftGif: Cannot turn image at path \"\(path)\" into NSData", type: .error)
            return nil
        }
        return gif(data: data)
    }

    public class func gif(data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            consoleLogInfo("SwiftGif: Source for the image does not exist", type: .error)
            return nil
        }
        return UIImage.animatedImageWithSource(source)
    }

    class func delayForImageAtIndex(_ index: Int, source: CGImageSource!) -> Double {
        var delay = 0.1

        let cfProperties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
        let gifProperties: CFDictionary = unsafeBitCast(
            CFDictionaryGetValue(cfProperties,
                                 Unmanaged.passUnretained(kCGImagePropertyGIFDictionary).toOpaque()),
            to: CFDictionary.self)

        var delayObject: AnyObject = unsafeBitCast(
            CFDictionaryGetValue(gifProperties,
                                 Unmanaged.passUnretained(kCGImagePropertyGIFUnclampedDelayTime).toOpaque()),
            to: AnyObject.self)
        if delayObject.doubleValue == 0 {
            delayObject = unsafeBitCast(
                CFDictionaryGetValue(gifProperties,
                                     Unmanaged.passUnretained(kCGImagePropertyGIFDelayTime).toOpaque()),
                to: AnyObject.self)
        }

        if let delayObject = delayObject as? Double, delayObject > 0 {
            delay = delayObject
        }

        return delay
    }

    class func gcdForPair(_ a: Int?, _ b: Int?) -> Int {
        var a = a
        var b = b
        if b == nil || a == nil {
            if b != nil {
                return b!
            } else if a != nil {
                return a!
            } else {
                return 0
            }
        }

        if a! < b! {
            let c = a
            a = b
            b = c
        }

        var rest: Int
        while true {
            rest = a! % b!

            if rest == 0 {
                return b!
            } else {
                a = b
                b = rest
            }
        }
    }

    class func gcdForArray(_ array: Array<Int>) -> Int {
        if array.isEmpty {
            return 1
        }

        var gcd = array[0]

        for val in array {
            gcd = UIImage.gcdForPair(val, gcd)
        }

        return gcd
    }

    class func animatedImageWithSource(_ source: CGImageSource) -> UIImage? {
        let count = CGImageSourceGetCount(source)
        var images = [CGImage]()
        var delays = [Int]()

        for i in 0..<count {
            if let image = CGImageSourceCreateImageAtIndex(source, i, nil) {
                images.append(image)
            }

            let delaySeconds = UIImage.delayForImageAtIndex(Int(i),
                                                            source: source)
            delays.append(Int(delaySeconds * 1000.0)) // Seconds to ms
        }

        let duration: Int = {
            var sum = 0

            for val: Int in delays {
                sum += val
            }

            return sum
        }()

        let gcd = gcdForArray(delays)
        var frames = [UIImage]()

        var frame: UIImage
        var frameCount: Int
        for i in 0..<count {
            frame = UIImage(cgImage: images[Int(i)])
            frameCount = Int(delays[Int(i)] / gcd)

            for _ in 0..<frameCount {
                frames.append(frame)
            }
        }

        let animation = UIImage.animatedImage(with: frames,
                                              duration: Double(duration) / 1000.0)

        return animation
    }
}
