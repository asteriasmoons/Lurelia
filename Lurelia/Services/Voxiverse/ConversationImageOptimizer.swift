import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ConversationImageOptimizer {
    static let maximumAttachmentBytes = 10_000_000
    static let maximumSourceImageBytes = 50_000_000
    private static let maximumDimension = 2560

    static func prepare(data: Data, name: String, typeIdentifier: String) throws -> (data: Data, name: String, typeIdentifier: String) {
        let declaredType = UTType(typeIdentifier)
        let source = CGImageSourceCreateWithData(data as CFData, nil)
        let actualType = source.flatMap { CGImageSourceGetType($0) }.flatMap { UTType($0 as String) }
        guard declaredType?.conforms(to: .image) == true || actualType?.conforms(to: .image) == true else {
            return (data, name, typeIdentifier)
        }
        let type = actualType ?? declaredType ?? .image
        guard data.count <= maximumSourceImageBytes else { throw OptimizationError.imageTooLarge }
        guard let source,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw OptimizationError.invalidImage
        }

        let baseName = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
        if max(width, height) <= maximumDimension && data.count <= maximumAttachmentBytes {
            let ext = type.preferredFilenameExtension ?? "jpg"
            return (data, "\(baseName).\(ext)", type.identifier)
        }
        for dimension in [maximumDimension, 2048, 1600] {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: dimension
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                throw OptimizationError.invalidImage
            }
            let hasAlpha: Bool
            switch image.alphaInfo {
            case .none, .noneSkipFirst, .noneSkipLast: hasAlpha = false
            default: hasAlpha = true
            }
            let candidates: [(UTType, CGFloat)] = hasAlpha
                ? [(.png, 1)]
                : type.conforms(to: .png)
                    ? [(.png, 1), (.heic, 0.9), (.jpeg, 0.88)]
                    : [(.heic, 0.9), (.jpeg, 0.9), (.jpeg, 0.82)]
            for (outputType, quality) in candidates {
                guard let encoded = encode(image, type: outputType, quality: quality) else { continue }
                if encoded.count <= maximumAttachmentBytes {
                    let ext = outputType.preferredFilenameExtension ?? "jpg"
                    return (encoded, "\(baseName).\(ext)", outputType.identifier)
                }
            }
        }
        throw OptimizationError.imageTooLarge
    }

    private static func encode(_ image: CGImage, type: UTType, quality: CGFloat) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: quality
        ] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    private enum OptimizationError: LocalizedError {
        case invalidImage
        case imageTooLarge

        var errorDescription: String? {
            switch self {
            case .invalidImage: "This image could not be opened."
            case .imageTooLarge: "This image is too large to attach after optimization."
            }
        }
    }
}
