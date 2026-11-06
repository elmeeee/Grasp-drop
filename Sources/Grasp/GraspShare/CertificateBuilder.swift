//
//  CertificateBuilder.swift
//  Grasp
//
//  Created by Elmee on 10/08/26.
//  Copyright © 2026 KaMy Studio. All rights reserved.
//

import Foundation
import Security

struct CertificateBuilder {
    let subject: String
    let privateKey: SecKey
    let publicKey: SecKey

    func build() -> Data? {
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            return nil
        }

        let tbs = tbsCertificate(
            serialNumber: randomSerial(),
            notBefore: Date().addingTimeInterval(-3600),
            notAfter: Date().addingTimeInterval(60 * 60 * 24 * 3650),
            subjectPublicKey: publicKeyData)

        guard let signature = sign(tbs) else { return nil }

        var body = Data()
        body.append(tbs)
        body.append(algorithmIdentifier())
        body.append(ASN1.bitString(signature))
        return ASN1.sequence(body)
    }

    private func tbsCertificate(
        serialNumber: Data,
        notBefore: Date,
        notAfter: Date,
        subjectPublicKey: Data
    ) -> Data {
        var tbs = ASN1.sequence()
        // version [0] EXPLICIT INTEGER 2 (v3)
        tbs.append(ASN1.contextTagged(0, content: ASN1.integer(Data([0x02]))))
        tbs.append(ASN1.integer(serialNumber))
        tbs.append(algorithmIdentifier())
        tbs.append(name(subject))
        tbs.append(validity(notBefore: notBefore, notAfter: notAfter))
        tbs.append(name(subject))
        tbs.append(subjectPublicKeyInfo(publicKey: subjectPublicKey))
        return tbs.data
    }

    private func algorithmIdentifier() -> Data {
        // ecdsa-with-SHA256 : 1.2.840.10045.4.3.2
        ASN1.sequence(ASN1.oid([0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x04, 0x03, 0x02]))
    }

    private func name(_ commonName: String) -> Data {
        var atv = ASN1.sequence()
        atv.append(ASN1.oid([0x55, 0x04, 0x03])) // commonName
        atv.append(ASN1.utf8String(commonName))

        var rdn = ASN1.set()
        rdn.append(atv.data)

        var name = ASN1.sequence()
        name.append(rdn.data)
        return name.data
    }

    private func validity(notBefore: Date, notAfter: Date) -> Data {
        var seq = ASN1.sequence()
        seq.append(ASN1.utcTime(notBefore))
        seq.append(ASN1.utcTime(notAfter))
        return seq.data
    }

    private func subjectPublicKeyInfo(publicKey: Data) -> Data {
        var alg = ASN1.sequence()
        alg.append(ASN1.oid([0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01])) // ecPublicKey
        alg.append(ASN1.oid([0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07])) // prime256v1

        var info = ASN1.sequence()
        info.append(alg.data)
        info.append(ASN1.bitString(publicKey))
        return info.data
    }

    private func sign(_ data: Data) -> Data? {
        let algorithm = SecKeyAlgorithm.ecdsaSignatureMessageX962SHA256
        guard SecKeyIsAlgorithmSupported(privateKey, .sign, algorithm) else { return nil }
        var error: Unmanaged<CFError>?
        return SecKeyCreateSignature(
            privateKey, algorithm, data as CFData, &error) as Data?
    }

    private func randomSerial() -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        bytes[0] &= 0x7F
        if bytes[0] == 0 { bytes[0] = 1 }
        return Data(bytes)
    }
}

/// Tiny ASN.1 DER encoding helpers.
enum ASN1 {
    struct Builder {
        private let tag: UInt8
        private var parts = [Data]()

        init(tag: UInt8) { self.tag = tag }

        mutating func append(_ part: Data) { parts.append(part) }

        var data: Data {
            wrap(tag: tag, content: parts.reduce(Data(), +))
        }
    }

    static func sequence() -> Builder { Builder(tag: 0x30) }
    static func set() -> Builder { Builder(tag: 0x31) }

    static func sequence(_ content: Data) -> Data { wrap(tag: 0x30, content: content) }

    static func wrap(tag: UInt8, content: Data) -> Data {
        var out = Data([tag])
        out.append(length(content.count))
        out.append(content)
        return out
    }

    static func integer(_ value: Data) -> Data {
        var v = value
        if let first = v.first, first & 0x80 != 0 {
            v.insert(0x00, at: 0)
        }
        return wrap(tag: 0x02, content: v)
    }

    static func oid(_ bytes: [UInt8]) -> Data { wrap(tag: 0x06, content: Data(bytes)) }

    static func utf8String(_ string: String) -> Data {
        wrap(tag: 0x0C, content: Data(string.utf8))
    }

    static func bitString(_ value: Data) -> Data {
        var content = Data([0x00])
        content.append(value)
        return wrap(tag: 0x03, content: content)
    }

    static func utcTime(_ date: Date) -> Data {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyMMddHHmmss'Z'"
        return wrap(tag: 0x17, content: Data(formatter.string(from: date).utf8))
    }

    static func contextTagged(_ tag: UInt8, content: Data) -> Data {
        wrap(tag: 0xA0 | tag, content: content)
    }

    static func length(_ count: Int) -> Data {
        if count < 0x80 {
            return Data([UInt8(count)])
        }
        var bytes = [UInt8]()
        var value = count
        while value > 0 {
            bytes.insert(UInt8(value & 0xFF), at: 0)
            value >>= 8
        }
        var out = Data([0x80 | UInt8(bytes.count)])
        out.append(contentsOf: bytes)
        return out
    }
}
