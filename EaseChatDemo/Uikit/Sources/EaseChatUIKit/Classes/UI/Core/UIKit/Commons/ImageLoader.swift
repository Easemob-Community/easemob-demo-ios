//
//  ImageLoader.swift
//  ChatUIKit
//
//  Created by 朱继超 on 2023/9/1.
//

import Foundation

import UIKit
import Combine

/**
 private var cancellables = Set<AnyCancellable>()
 let imageURL = URL(string: "https://example.com/image.jpg")!
 
 ImageLoader.shared.loadImage(from: imageURL)
     .sink(receiveValue: { [weak self] image in
         self?.imageView.image = image
     })
     .store(in: &cancellables)
 */

/// An Image loader
public struct ImageLoader {
    public static let shared = ImageLoader()
    private let cache = ImageCacheManager.shared
    
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        // 图片很多时并发过高会放大同时下载/解码带来的内存峰值，这里保守一些更稳。
        config.httpMaximumConnectionsPerHost = 9
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        
        config.requestCachePolicy = .useProtocolCachePolicy
        config.urlCache = URLCache(memoryCapacity: 500 * 1024 * 1024,diskCapacity: 500 * 1024 * 1024,diskPath: "EaseChatUIKit.ImageLoader")
        return URLSession(configuration: config)
    }()
    
    /// Load image from url.
    /// - Parameter url: image url
    /// - Returns: An
    /// - How to user? See above the ImageLoader.
    public func loadImage(from url: URL) -> AnyPublisher<UIImage?, Never> {
        if let cachedImage = cache.image(for: url.absoluteString) {
            return Just(cachedImage).eraseToAnyPublisher()
        } else {
            return self.session.dataTaskPublisher(for: url)
                .map { output -> UIImage? in
                    guard let response = output.response as? HTTPURLResponse,
                          (200..<300).contains(response.statusCode),
                          let image = UIImage(data: output.data), image.size != .zero else { return nil }
                    self.cache.cacheImage(image, for: url.absoluteString)
                    return image
                }
                .replaceError(with: nil)
                .receive(on: DispatchQueue.main)
                .eraseToAnyPublisher()
        }
    }
}
