import Foundation

enum ReadsbEnvelopeAdapter {
    static func adapt(_ data: Data) throws -> Data {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ADSBV2DecodingError.invalidEnvelope
        }
        guard var envelope = object as? [String: Any],
              let aircraft = envelope.removeValue(forKey: "aircraft") as? [Any]
        else {
            throw ADSBV2DecodingError.invalidEnvelope
        }
        envelope["ac"] = aircraft
        do {
            return try JSONSerialization.data(withJSONObject: envelope)
        } catch {
            throw ADSBV2DecodingError.invalidEnvelope
        }
    }
}
