// whatdid?
#if UI_TEST
import Cocoa
extension FlatEntry {
    
    init?(fromSerialized json: String) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        if let jsonData = json.data(using: .utf8) {
            do {
                self = try decoder.decode(FlatEntry.self, from: jsonData)
            } catch {
                NSLog("Error deserializing \(json): \(error)")
                return nil
            }
        } else {
            NSLog("Couldn't get UTF-8 data from string: \(json)")
            return nil
        }
    }
    
    func serialize() -> String? {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .millisecondsSince1970
            let jsonData = try encoder.encode(self)
            return String(data: jsonData, encoding: .utf8)
        } catch {
            NSLog("failed to encode \(self): \(error)")
            return nil
        }
    }
}
#endif
