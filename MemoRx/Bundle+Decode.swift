import Foundation

enum BundleDecodeError: LocalizedError {
    case fileNotFound(String)
    case dataReadFailed(String, underlying: Error)
    case decodeFailed(String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let file):
            return "Failed to locate \(file) in the main bundle."
        case .dataReadFailed(let file, let underlying):
            return "Failed to load \(file) from the main bundle: \(underlying.localizedDescription)"
        case .decodeFailed(let file, let underlying):
            return "Failed to decode \(file): \(underlying.localizedDescription)"
        }
    }
}

extension Bundle {
    func decodeOrThrow<T: Decodable>(_ type: T.Type, from file: String) throws -> T {
        guard let url = Bundle.main.url(forResource: file, withExtension: nil) else {
            throw BundleDecodeError.fileNotFound(file)
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw BundleDecodeError.dataReadFailed(file, underlying: error)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw BundleDecodeError.decodeFailed(file, underlying: error)
        }
    }

    func decode<T: Decodable>(_ type: T.Type, from file: String) -> T? {
        do {
            return try decodeOrThrow(type, from: file)
        } catch {
            #if DEBUG
        print("Bundle.decode: Failed to decode \(file): \(error.localizedDescription)")
        #endif
            return nil
        }
    }
}
