//
//  OtterIdentity.swift
//  Otter
//
//  Created by Elmee on 10/08/26.
//  Copyright © 2026 KaMy Studio. All rights reserved.
//

import Foundation
import CryptoKit
import Security
import Network

struct OtterIdentity {
    let identity: SecIdentity
    let derCertificate: Data
    let fingerprint: String

    var tlsIdentity: sec_identity_t? {
        sec_identity_create(identity)
    }

    /// Loads a persisted identity from a state directory, or creates a new one.
    static func loadOrCreate(stateDirectory: URL) -> OtterIdentity? {
        try? FileManager.default.createDirectory(
            at: stateDirectory, withIntermediateDirectories: true)

        if let stored = StoredIdentity.load(from: stateDirectory),
           let loaded = stored.restore() {
            return loaded
        }

        guard let created = generate() else { return nil }
        StoredIdentity(from: created).save(to: stateDirectory)
        return created
    }

    /// Generates a fresh P-256 self-signed identity.
    static func generate() -> OtterIdentity? {
        var error: Unmanaged<CFError>?
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrIsPermanent as String: false
        ]

        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            OtterLog.write("generate: SecKeyCreateRandomKey failed: \(String(describing: error))")
            return nil
        }
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            OtterLog.write("generate: SecKeyCopyPublicKey failed")
            return nil
        }

        let builder = CertificateBuilder(
            subject: "Otter", privateKey: privateKey, publicKey: publicKey)
        guard let der = builder.build() else {
            OtterLog.write("generate: CertificateBuilder.build failed")
            return nil
        }
        guard let cert = SecCertificateCreateWithData(nil, der as CFData) else {
            OtterLog.write("generate: SecCertificateCreateWithData failed (der=\(der.count) bytes)")
            let debugURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Downloads/Otter/.otter/debug-cert.der")
            try? der.write(to: debugURL)
            OtterLog.write("generate: wrote DER to \(debugURL.path)")
            return nil
        }
        guard let identity = SecIdentityCreate(nil, cert, privateKey) else {
            OtterLog.write("generate: SecIdentityCreate failed")
            return nil
        }

        return OtterIdentity(
            identity: identity,
            derCertificate: der,
            fingerprint: fingerprint(of: der))
    }

    static func fingerprint(of der: Data) -> String {
        SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
    }

    /// Serialises the private key + certificate for persistence across restarts.
    private struct StoredIdentity {
        let privateKeyData: Data
        let certificateData: Data
        let fingerprint: String

        init(from identity: OtterIdentity) {
            var privateKey: SecKey?
            _ = SecIdentityCopyPrivateKey(identity.identity, &privateKey)
            // External representation for an EC key is the raw 32-byte scalar,
            // which SecKeyCreateWithData can re-import with the same attributes.
            let raw = privateKey.flatMap { SecKeyCopyExternalRepresentation($0, nil) as Data? }
            self.privateKeyData = raw ?? Data()
            self.certificateData = identity.derCertificate
            self.fingerprint = identity.fingerprint
        }

        private init(privateKeyData: Data, certificateData: Data, fingerprint: String) {
            self.privateKeyData = privateKeyData
            self.certificateData = certificateData
            self.fingerprint = fingerprint
        }

        func restore() -> OtterIdentity? {
            let keyData = privateKeyData
            guard !keyData.isEmpty else { return nil }

            let attrs: [String: Any] = [
                kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
                kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
                kSecAttrKeySizeInBits as String: 256
            ]
            var error: Unmanaged<CFError>?
            guard let privateKey = SecKeyCreateWithData(
                    keyData as CFData, attrs as CFDictionary, &error),
                  let cert = SecCertificateCreateWithData(nil, certificateData as CFData),
                  let identity = SecIdentityCreate(nil, cert, privateKey) else { return nil }

            return OtterIdentity(
                identity: identity,
                derCertificate: certificateData,
                fingerprint: self.fingerprint)
        }

        func save(to directory: URL) {
            let url = directory.appendingPathComponent("otter-identity.bin")
            var payload = Data()
            var certLength = UInt32(certificateData.count).bigEndian
            withUnsafeBytes(of: &certLength) { payload.append(contentsOf: $0) }
            payload.append(certificateData)
            payload.append(privateKeyData)
            try? payload.write(to: url)
        }

        static func load(from directory: URL) -> StoredIdentity? {
            let url = directory.appendingPathComponent("otter-identity.bin")
            guard let data = try? Data(contentsOf: url) else { return nil }
            // Split: certificate length is a 4-byte big-endian prefix.
            guard data.count > 4 else { return nil }
            let certLength = data.prefix(4).withUnsafeBytes {
                $0.load(as: UInt32.self).bigEndian
            }
            let start = 4
            let end = start + Int(certLength)
            guard end <= data.count else { return nil }
            let cert = data.subdata(in: start..<end)
            let key = data.subdata(in: end..<data.count)
            let fp = OtterIdentity.fingerprint(of: cert)
            return StoredIdentity(privateKeyData: key, certificateData: cert, fingerprint: fp)
        }
    }
}
